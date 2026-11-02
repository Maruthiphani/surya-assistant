"""Shared test fixtures.

Dependencies are overridden with fakes so the real LangGraph flow runs without
any API keys or network calls. Auth is overridden to a fixed uid.
"""

import pytest
from fastapi.testclient import TestClient

from app.auth import verify_token
from app.config import Settings, get_settings
from app.deps import get_extractor, get_places
from app.gemini import AiExtractor
from app.main import app
from app.places import Candidate, PlacesClient


class FakeExtractor(AiExtractor):
    """Returns a scripted sequence of raw dicts (to test retry/validation)."""

    def __init__(self, outputs: list[dict]):
        self._outputs = outputs
        self.calls = 0

    def extract_raw(self, text, lat, lng) -> dict:
        out = self._outputs[min(self.calls, len(self._outputs) - 1)]
        self.calls += 1
        return out


class FakePlaces(PlacesClient):
    def __init__(self, candidates=None, nearby=None):
        self._candidates = candidates or []
        self._nearby = nearby or []

    def find_candidates(self, query, lat, lng):
        return list(self._candidates)

    def find_nearby(self, query, lat, lng, radius_meters, limit):
        return list(self._nearby)[:limit]


@pytest.fixture
def make_client():
    """Factory: build a TestClient wired with the given fakes/settings."""

    def _make(extractor=None, places=None, settings=None):
        if extractor is not None:
            app.dependency_overrides[get_extractor] = lambda: extractor
        if places is not None:
            app.dependency_overrides[get_places] = lambda: places
        if settings is not None:
            app.dependency_overrides[get_settings] = lambda: settings
        app.dependency_overrides[verify_token] = lambda: "test-uid"
        return TestClient(app)

    yield _make
    app.dependency_overrides.clear()


@pytest.fixture
def candidate():
    return Candidate(name="Costco", address="1 Main St", lat=34.2, lng=-84.1)


def settings_with(**kwargs) -> Settings:
    base = dict(auth_disabled=False, gemini_api_key="x", google_places_api_key="")
    base.update(kwargs)
    return Settings(**base)
