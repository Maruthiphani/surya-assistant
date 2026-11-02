"""Thin, defensive Langfuse tracing (CLAUDE.md §2).

A no-op unless Langfuse keys are configured, and it NEVER breaks a request —
any tracing error is swallowed. Usage:

    with trace("parse", text=...):
        ...
"""

from __future__ import annotations

import contextlib

from .config import get_settings


@contextlib.contextmanager
def trace(name: str, **metadata):
    settings = get_settings()
    if not settings.langfuse_enabled:
        yield
        return

    client = None
    try:
        from langfuse import Langfuse

        client = Langfuse(
            public_key=settings.langfuse_public_key,
            secret_key=settings.langfuse_secret_key,
            host=settings.langfuse_host,
        )
        # API shape varies across Langfuse versions; guard everything.
        try:
            client.trace(name=name, metadata=metadata)
        except Exception:
            pass
        yield
    except Exception:
        # Tracing must never affect the response.
        yield
    finally:
        if client is not None:
            with contextlib.suppress(Exception):
                client.flush()
