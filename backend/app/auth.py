"""Firebase ID-token verification (CLAUDE.md §5).

Every endpoint except /health depends on `verify_token`, which validates the
`Authorization: Bearer <idToken>` header and returns the caller's uid.

- On Cloud Run the default service account supplies credentials; locally, token
  verification only needs the project id + Google's public certs.
- `AUTH_DISABLED=true` (development only) bypasses verification so the API can be
  exercised without a real token. Tests override this dependency directly.
"""

from __future__ import annotations

from fastapi import Depends, Header, HTTPException, status

from .config import Settings, get_settings

_initialized = False


def _ensure_firebase(project_id: str) -> None:
    """Initialise the Firebase Admin app once, lazily."""
    global _initialized
    if _initialized:
        return
    import firebase_admin

    if not firebase_admin._apps:
        firebase_admin.initialize_app(options={"projectId": project_id})
    _initialized = True


def verify_token(
    authorization: str = Header(default=""),
    settings: Settings = Depends(get_settings),
) -> str:
    """Return the caller's uid, or raise 401."""
    if settings.auth_disabled:
        return "dev-user"

    if not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or malformed Authorization header.",
        )
    id_token = authorization.split(" ", 1)[1].strip()

    _ensure_firebase(settings.firebase_project_id)
    from firebase_admin import auth as fb_auth

    try:
        decoded = fb_auth.verify_id_token(id_token)
    except Exception as exc:  # invalid/expired token
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token.",
        ) from exc

    return decoded["uid"]
