"""FastAPI application entry point for the Surya backend (CLAUDE.md §4).

Endpoints:
  GET  /health      - public liveness probe
  POST /v1/parse    - text -> {task, locationType, candidates|query}
  POST /v1/nearby   - discover matching branches near the user (dynamic reminders)
  POST /v1/confirm  - friendly confirmation message

All /v1 endpoints require a Firebase ID token (see auth.verify_token).
"""

from fastapi import Depends, FastAPI, HTTPException, status
from pydantic import BaseModel

from .auth import verify_token
from .config import Settings, get_settings
from .deps import get_parse_graph, get_places
from .graph import InvalidLlmOutput, run_parse
from .places import PlacesClient
from .schemas import (
    ConfirmRequest,
    ConfirmResponse,
    NearbyRequest,
    NearbyResponse,
    ParseRequest,
    ParseResponse,
)
from .tracing import trace

app = FastAPI(
    title="Surya API",
    version="0.3.0",
    summary="Backend for the Surya voice/location reminder app.",
)


class HealthResponse(BaseModel):
    status: str
    env: str


@app.get("/health", response_model=HealthResponse, tags=["system"])
def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    """Public liveness probe (the only anonymous endpoint, §5)."""
    return HealthResponse(status="ok", env=settings.app_env)


@app.post("/v1/parse", response_model=ParseResponse, tags=["ai"])
def parse(
    req: ParseRequest,
    uid: str = Depends(verify_token),
    graph=Depends(get_parse_graph),
) -> ParseResponse:
    """Extract task + location from free text, classifying specific vs dynamic."""
    with trace("parse", text=req.text, uid=uid):
        try:
            return run_parse(graph, req.text, req.lat, req.lng)
        except InvalidLlmOutput as exc:
            # Never save unvalidated LLM output (§5).
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=str(exc),
            ) from exc


@app.post("/v1/nearby", response_model=NearbyResponse, tags=["ai"])
def nearby(
    req: NearbyRequest,
    uid: str = Depends(verify_token),
    places: PlacesClient = Depends(get_places),
    settings: Settings = Depends(get_settings),
) -> NearbyResponse:
    """Discover matching branches near the user (dynamic reminder refresh)."""
    if not settings.places_enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Places is not configured (set GOOGLE_PLACES_API_KEY).",
        )
    with trace("nearby", query=req.query, uid=uid):
        found = places.find_nearby(
            req.query, req.lat, req.lng, req.radius_meters, req.limit
        )
    return NearbyResponse(places=found)


@app.post("/v1/confirm", response_model=ConfirmResponse, tags=["ai"])
def confirm(
    req: ConfirmRequest,
    uid: str = Depends(verify_token),
) -> ConfirmResponse:
    """Build a confirmation line using the user's assistant name."""
    message = (
        f"Got it — I'll remind you to {req.task} when you reach "
        f"{req.location_name}."
    )
    return ConfirmResponse(message=message)
