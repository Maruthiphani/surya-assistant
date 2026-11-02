"""FastAPI dependency providers for the AI/Places services.

Endpoints depend on these; tests override them with fakes (so no real keys are
needed). Each provider raises 503 when its backend isn't configured, except
Places in the parse path which degrades to "no candidates".
"""

from __future__ import annotations

from fastapi import Depends, HTTPException, status

from .config import Settings, get_settings
from .gemini import AiExtractor, GeminiExtractor
from .graph import build_parse_graph
from .places import Candidate, GooglePlacesClient, PlacesClient


class _NullPlaces(PlacesClient):
    """Used when no Places key is set: parse still works (no candidates)."""

    def find_candidates(self, query, lat, lng) -> list[Candidate]:
        return []

    def find_nearby(self, query, lat, lng, radius_meters, limit) -> list[Candidate]:
        return []


def get_extractor(settings: Settings = Depends(get_settings)) -> AiExtractor:
    if not settings.gemini_enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Gemini is not configured (set GEMINI_API_KEY).",
        )
    return GeminiExtractor(settings.gemini_api_key, settings.gemini_model)


def get_places(settings: Settings = Depends(get_settings)) -> PlacesClient:
    if settings.places_enabled:
        return GooglePlacesClient(settings.google_places_api_key)
    return _NullPlaces()


def get_parse_graph(
    extractor: AiExtractor = Depends(get_extractor),
    places: PlacesClient = Depends(get_places),
):
    return build_parse_graph(extractor, places)
