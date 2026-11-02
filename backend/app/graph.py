"""LangGraph parse flow (CLAUDE.md §2, §5).

Flow:  extract (Gemini) -> validate (Pydantic, retry once) -> places (if specific)

- Validation failures retry the extraction ONCE, then raise InvalidLlmOutput,
  which the endpoint maps to HTTP 422 (never save unvalidated LLM output).
- "specific" reminders get Places candidates; "query" reminders carry the search
  term and are discovered at runtime via /v1/nearby (no branch chosen here).

Dependencies (extractor, places) are injected so tests run without real keys.
"""

from __future__ import annotations

from typing import TypedDict

from langgraph.graph import END, StateGraph
from pydantic import ValidationError

from .gemini import AiExtractor
from .places import PlacesClient
from .schemas import Candidate, LlmExtraction, ParseResponse

_MAX_ATTEMPTS = 2  # initial try + one retry


class InvalidLlmOutput(Exception):
    """Raised when the LLM output fails validation after the retry."""


class _State(TypedDict, total=False):
    text: str
    lat: float | None
    lng: float | None
    raw: dict
    attempts: int
    extraction: LlmExtraction
    candidates: list[Candidate]
    error: str


def build_parse_graph(extractor: AiExtractor, places: PlacesClient):
    """Compile the parse graph with the given dependencies."""

    def extract_node(state: _State) -> _State:
        raw = extractor.extract_raw(state["text"], state.get("lat"), state.get("lng"))
        return {"raw": raw, "attempts": state.get("attempts", 0) + 1}

    def validate_node(state: _State) -> _State:
        try:
            extraction = LlmExtraction(**(state.get("raw") or {}))
            return {"extraction": extraction}
        except ValidationError:
            return {}  # routing decides retry vs error

    def route_after_validate(state: _State) -> str:
        if state.get("extraction") is not None:
            return "places"
        if state.get("attempts", 0) < _MAX_ATTEMPTS:
            return "retry"
        return "error"

    def places_node(state: _State) -> _State:
        extraction = state["extraction"]
        if extraction.location_type == "specific":
            candidates = places.find_candidates(
                extraction.location, state.get("lat"), state.get("lng")
            )
            return {"candidates": candidates}
        return {"candidates": []}

    def error_node(state: _State) -> _State:
        return {"error": "invalid_llm_output"}

    g = StateGraph(_State)
    g.add_node("extract", extract_node)
    g.add_node("validate", validate_node)
    g.add_node("places", places_node)
    g.add_node("error", error_node)
    g.set_entry_point("extract")
    g.add_edge("extract", "validate")
    g.add_conditional_edges(
        "validate",
        route_after_validate,
        {"retry": "extract", "places": "places", "error": "error"},
    )
    g.add_edge("places", END)
    g.add_edge("error", END)
    return g.compile()


def run_parse(graph, text: str, lat: float | None, lng: float | None) -> ParseResponse:
    """Invoke the compiled graph and build the API response."""
    state: _State = graph.invoke({"text": text, "lat": lat, "lng": lng})

    if state.get("error") or state.get("extraction") is None:
        raise InvalidLlmOutput("Could not understand the reminder.")

    extraction = state["extraction"]
    candidates = state.get("candidates", [])

    if extraction.location_type == "query":
        return ParseResponse(
            task=extraction.task,
            location_type="query",
            location_name=extraction.location,
            location_query=extraction.location,
            candidates=[],
        )

    return ParseResponse(
        task=extraction.task,
        location_type="specific",
        location_name=extraction.location,
        location_query=None,
        candidates=candidates,
    )
