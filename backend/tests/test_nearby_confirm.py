"""Tests for /v1/nearby and /v1/confirm."""

from tests.conftest import FakePlaces, settings_with


def test_nearby_returns_branches(make_client, candidate):
    client = make_client(
        places=FakePlaces(nearby=[candidate, candidate]),
        settings=settings_with(google_places_api_key="x"),
    )
    resp = client.post(
        "/v1/nearby",
        json={"query": "Costco", "lat": 34.2, "lng": -84.1, "limit": 20},
    )
    assert resp.status_code == 200
    assert len(resp.json()["places"]) == 2


def test_nearby_503_when_places_not_configured(make_client, candidate):
    client = make_client(
        places=FakePlaces(nearby=[candidate]),
        settings=settings_with(google_places_api_key=""),  # not configured
    )
    resp = client.post(
        "/v1/nearby", json={"query": "Costco", "lat": 34.2, "lng": -84.1}
    )
    assert resp.status_code == 503


def test_nearby_respects_limit(make_client, candidate):
    client = make_client(
        places=FakePlaces(nearby=[candidate] * 10),
        settings=settings_with(google_places_api_key="x"),
    )
    resp = client.post(
        "/v1/nearby",
        json={"query": "Costco", "lat": 34.2, "lng": -84.1, "limit": 3},
    )
    assert resp.status_code == 200
    assert len(resp.json()["places"]) == 3


def test_confirm_uses_assistant_name(make_client):
    client = make_client()
    resp = client.post(
        "/v1/confirm",
        json={"task": "buy rice", "location_name": "Costco", "assistant_name": "Hanu"},
    )
    assert resp.status_code == 200
    assert resp.json()["message"] == (
        "Got it — I'll remind you to buy rice when you reach Costco."
    )
