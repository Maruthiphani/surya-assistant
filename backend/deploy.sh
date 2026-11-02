#!/usr/bin/env bash
# Deploy the Surya backend to Google Cloud Run, with keys stored in Secret
# Manager (CLAUDE.md §2: never bake secrets into the image).
#
# Prerequisites (one-time):
#   gcloud auth login
#   gcloud config set project <YOUR_PROJECT_ID>
#   gcloud services enable run.googleapis.com secretmanager.googleapis.com \
#       aiplatform.googleapis.com places.googleapis.com
#   # Create secrets (run once; paste the value when prompted):
#   printf '%s' "$GEMINI_API_KEY"  | gcloud secrets create GEMINI_API_KEY --data-file=-
#   printf '%s' "$PLACES_API_KEY"  | gcloud secrets create GOOGLE_PLACES_API_KEY --data-file=-
#
# Usage:  ./deploy.sh <PROJECT_ID> [REGION]
set -euo pipefail

PROJECT_ID="${1:?Usage: ./deploy.sh <PROJECT_ID> [REGION]}"
REGION="${2:-us-central1}"
SERVICE="surya-api"

echo "Deploying $SERVICE to project=$PROJECT_ID region=$REGION ..."

gcloud run deploy "$SERVICE" \
  --source . \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --allow-unauthenticated \
  --set-env-vars "APP_ENV=production,FIREBASE_PROJECT_ID=${PROJECT_ID},GEMINI_MODEL=gemini-2.0-flash" \
  --update-secrets "GEMINI_API_KEY=GEMINI_API_KEY:latest,GOOGLE_PLACES_API_KEY=GOOGLE_PLACES_API_KEY:latest"

echo "Done. Service URL:"
gcloud run services describe "$SERVICE" --project "$PROJECT_ID" --region "$REGION" \
  --format 'value(status.url)'
