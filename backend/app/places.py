"""Google Places integration (CLAUDE.md §2).

`PlacesClient` is the interface; `GooglePlacesClient` calls the Places API (v1)
over HTTP. Tests inject a fake, so no key is needed to exercise the graph or the
endpoints. We use Text Search for both cases (it handles chain names and
categories, biased to the user's location) rather than type-based Nearby Search.
"""

from __future__ import annotations

import abc

import httpx

from .schemas import Candidate

_SEARCH_TEXT_URL = "https://places.googleapis.com/v1/places:searchText"
_FIELD_MASK = "places.displayName,places.formattedAddress,places.location"


class PlacesClient(abc.ABC):
    @abc.abstractmethod
    def find_candidates(
        self, query: str, lat: float | None, lng: float | None
    ) -> list[Candidate]:
        """Resolve a *specific* place to 1-3 candidates (picker if >1)."""
        raise NotImplementedError

    @abc.abstractmethod
    def find_nearby(
        self, query: str, lat: float, lng: float, radius_meters: int, limit: int
    ) -> list[Candidate]:
        """Discover matching branches near the user, nearest first."""
        raise NotImplementedError


class GooglePlacesClient(PlacesClient):
    def __init__(self, api_key: str, timeout: float = 10.0) -> None:
        self._api_key = api_key
        self._timeout = timeout

    def _search(
        self,
        query: str,
        lat: float | None,
        lng: float | None,
        *,
        radius_meters: int | None,
        limit: int,
        rank_by_distance: bool,
    ) -> list[Candidate]:
        body: dict = {"textQuery": query, "maxResultCount": limit}
        if lat is not None and lng is not None:
            circle = {
                "center": {"latitude": lat, "longitude": lng},
                "radius": float(radius_meters or 20000),
            }
            # Restriction when discovering nearby; bias when resolving a specific place.
            body["locationBias"] = {"circle": circle}
            if rank_by_distance:
                body["rankPreference"] = "DISTANCE"

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self._api_key,
            "X-Goog-FieldMask": _FIELD_MASK,
        }
        with httpx.Client(timeout=self._timeout) as client:
            resp = client.post(_SEARCH_TEXT_URL, json=body, headers=headers)
            resp.raise_for_status()
            data = resp.json()

        results: list[Candidate] = []
        for place in data.get("places", [])[:limit]:
            loc = place.get("location") or {}
            name = (place.get("displayName") or {}).get("text") or query
            results.append(
                Candidate(
                    name=name,
                    address=place.get("formattedAddress", ""),
                    lat=loc.get("latitude", 0.0),
                    lng=loc.get("longitude", 0.0),
                )
            )
        return results

    def find_candidates(
        self, query: str, lat: float | None, lng: float | None
    ) -> list[Candidate]:
        return self._search(
            query, lat, lng, radius_meters=20000, limit=3, rank_by_distance=False
        )

    def find_nearby(
        self, query: str, lat: float, lng: float, radius_meters: int, limit: int
    ) -> list[Candidate]:
        return self._search(
            query, lat, lng, radius_meters=radius_meters, limit=limit,
            rank_by_distance=True,
        )
