"""Pydantic schemas for the Surya API (CLAUDE.md §4).

Every LLM output is validated against one of these before we trust it; invalid
output is retried once then rejected with 422 (see graph.py).
"""

from typing import Literal

from pydantic import BaseModel, Field

LocationType = Literal["specific", "query"]


# --- Core value objects -----------------------------------------------------

class Candidate(BaseModel):
    """A concrete place returned by Google Places."""

    name: str
    address: str
    lat: float
    lng: float


# --- LLM extraction (internal) ---------------------------------------------

class LlmExtraction(BaseModel):
    """Structured result we force Gemini to return and then validate.

    `locationType`:
      - "specific": the user named a particular place ("Costco in Cumming").
      - "query":    a chain or category ("Costco", "a pharmacy") -> match any
                    nearby branch at runtime; no single branch is chosen.
    """

    task: str = Field(..., min_length=1, description="What to do, e.g. 'buy rice'.")
    location: str = Field(..., min_length=1, description="Place text as understood.")
    location_type: LocationType


# --- /v1/parse --------------------------------------------------------------

class ParseRequest(BaseModel):
    text: str = Field(..., min_length=1)
    # The user's current location, used to bias/geocode "specific" places.
    lat: float | None = None
    lng: float | None = None


class ParseResponse(BaseModel):
    task: str
    location_type: LocationType
    location_name: str
    # Only for dynamic reminders; the search term to discover branches with.
    location_query: str | None = None
    # Only for specific reminders; empty for dynamic. Picker only if len > 1.
    candidates: list[Candidate] = Field(default_factory=list)


# --- /v1/nearby -------------------------------------------------------------

class NearbyRequest(BaseModel):
    query: str = Field(..., min_length=1)
    lat: float
    lng: float
    radius_meters: int = 30000
    limit: int = Field(default=20, ge=1, le=50)


class NearbyResponse(BaseModel):
    places: list[Candidate] = Field(default_factory=list)


# --- /v1/confirm ------------------------------------------------------------

class ConfirmRequest(BaseModel):
    task: str = Field(..., min_length=1)
    location_name: str = Field(..., min_length=1)
    assistant_name: str = "Surya"


class ConfirmResponse(BaseModel):
    message: str
