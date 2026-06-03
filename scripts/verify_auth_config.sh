#!/usr/bin/env bash
# Reads the current auth config from Supabase Management API and prints the
# subjects + first 200 chars of each template body, so we can confirm what's
# actually persisted (vs what we think we pushed).
#
# Usage:
#   export SUPABASE_ACCESS_TOKEN="sbp_..."
#   ./scripts/verify_auth_config.sh

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "❌ SUPABASE_ACCESS_TOKEN is not set."
  exit 1
fi

SUPABASE_URL=$(grep -E '^SUPABASE_URL=' .env | cut -d'=' -f2)
PROJECT_REF=$(echo "$SUPABASE_URL" | sed -E 's|https://([^.]+)\.supabase\.co.*|\1|')

echo "▸ GET /v1/projects/$PROJECT_REF/config/auth"
echo

curl -sS "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  | jq '{
      otp_expiration_s: .mailer_otp_exp,
      otp_length: .mailer_otp_length,
      autoconfirm: .mailer_autoconfirm,
      sender_email: .smtp_sender_name,
      smtp_host: .smtp_host,
      smtp_admin_email: .smtp_admin_email,
      smtp_user: .smtp_user,
      site_url: .site_url,
      confirm_signup: {
        subject: .mailer_subjects_confirmation,
        body_starts_with: (.mailer_templates_confirmation_content // "" | .[0:160])
      },
      magic_link: {
        subject: .mailer_subjects_magic_link,
        body_starts_with: (.mailer_templates_magic_link_content // "" | .[0:160])
      },
      recovery: {
        subject: .mailer_subjects_recovery,
        body_starts_with: (.mailer_templates_recovery_content // "" | .[0:160])
      }
    }'
