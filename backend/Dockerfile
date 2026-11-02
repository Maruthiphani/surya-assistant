# Surya backend container image (Cloud Run target).
# Pinned to Python 3.12 per CLAUDE.md §2, independent of the local toolchain.
FROM python:3.12-slim

# Keep Python lean and logs unbuffered (so Cloud Run shows logs immediately).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

WORKDIR /app

# Install dependencies first so Docker layer caching skips reinstall on code-only
# changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code.
COPY app ./app

# Cloud Run sends traffic to $PORT; bind uvicorn to it. Use the shell form so
# the $PORT env var is expanded at runtime.
EXPOSE 8080
CMD exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT}
