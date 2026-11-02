"""Tests for /v1/parse — exercises the real LangGraph flow with fake leaves."""

from tests.conftest import FakeExtractor, FakePlaces


def test_parse_dynamic_query_no_candidates(make_client):
    """A bare chain → locationType 'query', no candidates, carries the query."""
    extractor = FakeExtractor(
        [{"task": "buy rice", "location": "Costco", "location_type": "query"}]
    )
    client = make_client(extractor=extractor, places=FakePlaces())
    resp = client.post("/v1/parse", json={"text": "remind me to buy rice at Costco"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["task"] == "buy rice"
    assert body["location_type"] == "query"
    assert body["location_query"] == "Costco"
    assert body["candidates"] == []


def test_parse_specific_returns_candidates(make_client, candidate):
    """A named place → locationType 'specific' with Places candidates."""
    extractor = FakeExtractor(
        [{"task": "buy rice", "location": "Costco in Cumming",
          "location_type": "specific"}]
    )
    client = make_client(extractor=extractor, places=FakePlaces(candidates=[candidate]))
    resp = client.post(
        "/v1/parse",
        json={"text": "buy rice at Costco in Cumming", "lat": 34.2, "lng": -84.1},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["location_type"] == "specific"
    assert body["location_query"] is None
    assert len(body["candidates"]) == 1
    assert body["candidates"][0]["name"] == "Costco"


def test_parse_retries_once_then_succeeds(make_client):
    """First LLM output invalid, second valid → 200 (retry worked)."""
    extractor = FakeExtractor([
        {"task": "buy rice"},  # invalid: missing location/location_type
        {"task": "buy rice", "location": "Costco", "location_type": "query"},
    ])
    client = make_client(extractor=extractor, places=FakePlaces())
    resp = client.post("/v1/parse", json={"text": "..."})
    assert resp.status_code == 200
    assert extractor.calls == 2  # retried exactly once


def test_parse_invalid_twice_returns_422(make_client):
    """Invalid output on both attempts → 422, never saved."""
    extractor = FakeExtractor([{"bad": "data"}])  # always invalid
    client = make_client(extractor=extractor, places=FakePlaces())
    resp = client.post("/v1/parse", json={"text": "..."})
    assert resp.status_code == 422
    assert extractor.calls == 2  # initial + one retry, then give up
