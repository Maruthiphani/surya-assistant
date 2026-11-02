
"""LLM extraction via Gemini Flash (CLAUDE.md §2).

`AiExtractor` is the interface the parse graph depends on; `GeminiExtractor` is
the Google-genai implementation. Tests inject a fake extractor, so none of the
graph/endpoint logic needs a real API key.

The extractor returns a raw dict (the model's JSON). Pydantic validation — with
one retry, then 422 — happens in graph.py, so the "never trust unvalidated LLM
output" rule lives in one place.
"""

from __future__ import annotations

import abc
import json
import time

# HTTP statuses worth retrying (transient capacity/rate issues).
_TRANSIENT = {429, 500, 503}

PROMPT = """You convert a spoken reminder into structured JSON.

Extract:
- task: the thing to do, imperative and concise (e.g. "buy rice"). Strip any
  "remind me to" phrasing.
- location: the place as the user said it (e.g. "Costco", "Costco in Cumming",
  "a pharmacy").
- location_type: "specific" if the user named a PARTICULAR place/branch
  (has a city, street, or clearly one location, e.g. "Costco in Cumming",
  "the Walmart on Peachtree"); otherwise "query" for a bare chain or a category
  ("Costco", "Walmart", "a pharmacy", "grocery store", "gas station").

Rules:
- Default to "query" for bare chain names and categories.
- Only use "specific" when a particular location is clearly identified.

Return ONLY JSON with keys: task, location, location_type.

User said: {text}
"""


class AiExtractor(abc.ABC):
    """Extracts {task, location, location_type} from free text."""

    @abc.abstractmethod
    def extract_raw(self, text: str, lat: float | None, lng: float | None) -> dict:
        """Return the model's JSON as a dict (unvalidated)."""
        raise NotImplementedError


class GeminiExtractor(AiExtractor):
    def __init__(self, api_key: str, model: str = "gemini-2.0-flash") -> None:
        # Imported lazily so the package (and tests) don't require google-genai
        # unless a real extractor is actually constructed.
        from google import genai

        self._client = genai.Client(api_key=api_key)
        self._model = model

    def extract_raw(self, text: str, lat: float | None, lng: float | None) -> dict:
        from google.genai import types

        config = types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0,
        )

        # Retry transient 429/503 with short backoff (Flash is often busy).
        last_exc: Exception | None = None
        for attempt in range(3):
            try:
                resp = self._client.models.generate_content(
                    model=self._model,
                    contents=PROMPT.format(text=text),
                    config=config,
                )
                raw = (resp.text or "").strip()
                try:
                    return json.loads(raw)
                except json.JSONDecodeError:
                    # Graph validation will reject {} -> retry/422.
                    return {}
            except Exception as exc:  # noqa: BLE001
                code = getattr(exc, "code", None)
                last_exc = exc
                if code in _TRANSIENT and attempt < 2:
                    time.sleep(1.5 * (attempt + 1))
                    continue
                raise
        assert last_exc is not None
        raise last_exc
