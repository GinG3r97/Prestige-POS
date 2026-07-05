#!/usr/bin/env bash
# Push branded email templates + OTP TTL to Supabase via Management API.
#
# Usage:
#   1. Generate a Personal Access Token at
#      https://supabase.com/dashboard/account/tokens (scope: Manage projects)
#   2. Export it:
#      export SUPABASE_ACCESS_TOKEN="sbp_..."
#   3. Run from the project root:
#      ./scripts/push_auth_config.sh
#
# The script reads the project ref from .env (SUPABASE_URL).
# Safe to re-run — PATCH endpoints are idempotent.

set -euo pipefail

cd "$(dirname "$0")/.."

# ── Validate prerequisites ───────────────────────────────────────────────
if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "❌ SUPABASE_ACCESS_TOKEN is not set."
  echo "   Generate one at https://supabase.com/dashboard/account/tokens"
  echo "   then run:  export SUPABASE_ACCESS_TOKEN='sbp_...'"
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "❌ .env not found. Run from the project root."
  exit 1
fi

if [[ ! -f email_templates/magic_link.html ]]; then
  echo "❌ email_templates/magic_link.html not found."
  exit 1
fi

# ── Derive project ref from SUPABASE_URL ─────────────────────────────────
SUPABASE_URL=$(grep -E '^SUPABASE_URL=' .env | cut -d'=' -f2)
PROJECT_REF=$(echo "$SUPABASE_URL" | sed -E 's|https://([^.]+)\.supabase\.co.*|\1|')

if [[ -z "$PROJECT_REF" || "$PROJECT_REF" == "$SUPABASE_URL" ]]; then
  echo "❌ Could not derive project ref from SUPABASE_URL ($SUPABASE_URL)"
  exit 1
fi

echo "▸ Project ref: $PROJECT_REF"

# ── Read template body + JSON-escape it ──────────────────────────────────
# jq -Rs '.' reads stdin as a single raw string and emits a JSON-quoted version.
TEMPLATE_JSON=$(jq -Rs '.' < email_templates/magic_link.html)

# ── Build the PATCH body ─────────────────────────────────────────────────
# We update three templates with the same branded HTML so users see a
# consistent experience whether they're new or returning:
#   • confirmation     — first email to a brand-new user (signup confirm)
#   • magic_link       — returning-user sign-in email
#   • recovery         — password reset (unused but kept on-brand if enabled)
#
# We also drop OTP expiration to 600s (10 min) for tighter security.
# Read OTP length from .env so the dashboard config stays in sync with the
# Flutter app's UI. Valid range per GoTrue is 6–10.
OTP_LENGTH=$(grep -E '^SUPABASE_OTP_LENGTH=' .env | cut -d'=' -f2)
OTP_LENGTH=${OTP_LENGTH:-6}

BODY=$(cat <<EOF
{
  "mailer_subjects_confirmation": "Your Prestige Café sign-in code",
  "mailer_templates_confirmation_content": $TEMPLATE_JSON,
  "mailer_subjects_magic_link": "Your Prestige Café sign-in code",
  "mailer_templates_magic_link_content": $TEMPLATE_JSON,
  "mailer_subjects_recovery": "Your Prestige Café sign-in code",
  "mailer_templates_recovery_content": $TEMPLATE_JSON,
  "mailer_otp_exp": 600,
  "mailer_otp_length": $OTP_LENGTH
}
EOF
)

# ── PATCH ────────────────────────────────────────────────────────────────
echo "▸ PATCH /v1/projects/$PROJECT_REF/config/auth"
HTTP_STATUS=$(curl -sS -o /tmp/supabase_auth_patch.json -w '%{http_code}' \
  -X PATCH "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY")

if [[ "$HTTP_STATUS" -ge 200 && "$HTTP_STATUS" -lt 300 ]]; then
  echo "✅ Auth config updated (HTTP $HTTP_STATUS)"
  echo "   • Confirm signup template → branded"
  echo "   • Magic Link template     → branded"
  echo "   • Recovery template       → branded"
  echo "   • OTP expiration          → 600s (10 min)"
  echo "   • OTP length              → $OTP_LENGTH digits"
else
  echo "❌ Request failed with HTTP $HTTP_STATUS"
  echo "Response body:"
  cat /tmp/supabase_auth_patch.json
  echo
  exit 1
fi
