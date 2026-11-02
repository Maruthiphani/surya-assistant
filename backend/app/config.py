"""Application configuration.

Settings are loaded from environment variables (and a local `.env` file during
development) via pydantic-settings. On Cloud Run the same variables are injected
from Google Secret Manager, so no code change is needed between environments.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed, validated application settings."""

    # Human-readable environment name, handy in logs and the /health payload.
    app_env: str = "development"

    # Cloud Run injects the port the container must listen on via $PORT.
    port: int = 8080

    # --- AI (Phase 3) ---
    gemini_api_key: str = ""
    # Resilient alias → latest stable Flash (pinned model ids like gemini-2.0-flash
    # get retired; the alias avoids 404s when a version is removed).
    gemini_model: str = "gemini-flash-latest"

    # --- Places (Phase 3) ---
    google_places_api_key: str = ""

    # --- Firebase auth ---
    firebase_project_id: str = "surya-assistance"
    # Dev escape hatch: when true (development only), endpoints skip Firebase
    # token verification so the API can be exercised locally without a real ID
    # token. NEVER enable in production.
    auth_disabled: bool = False

    # --- Langfuse tracing (optional; no-op when keys are blank) ---
    langfuse_public_key: str = ""
    langfuse_secret_key: str = ""
    langfuse_host: str = "https://cloud.langfuse.com"

    @property
    def places_enabled(self) -> bool:
        return bool(self.google_places_api_key)

    @property
    def gemini_enabled(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def langfuse_enabled(self) -> bool:
        return bool(self.langfuse_public_key and self.langfuse_secret_key)

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",  # Ignore unrelated env vars instead of erroring.
    )


@lru_cache
def get_settings() -> Settings:
    """Return a cached Settings instance (parsed once per process)."""
    return Settings()
