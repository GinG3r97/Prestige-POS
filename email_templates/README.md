# Prestige Café — Email templates

Branded HTML emails for Supabase Auth. Designed to match the Prestige Café theme
(warm gold / cream palette, italic tagline, monospace code chip).

## How to apply

### Which Supabase templates do we update? — **all three of these**

`signInWithOtp(shouldCreateUser: true)` (used by both signup and login in
Prestige Café) routes through *different* Supabase templates depending on the
user's state:

| Template            | When Supabase uses it                                            |
|---------------------|------------------------------------------------------------------|
| **Confirm signup**  | Brand-new user's first email (the very first signup)             |
| **Magic Link**      | Returning user signing in again                                  |
| **Reset Password**  | Only if a password is ever set — kept on-brand as defense-in-depth |

So we paste the same branded HTML into all three. The template contents
include `{{ .Token }}`, which carries the 8-digit OTP for any of these.

### Option A — automated (recommended, uses Management API)

One-time setup:

1. Generate a Personal Access Token at
   https://supabase.com/dashboard/account/tokens
   (the "Manage projects" scope is enough)
2. Export it in your shell:
   ```bash
   export SUPABASE_ACCESS_TOKEN="sbp_..."
   ```
3. From the project root, run:
   ```bash
   ./scripts/push_auth_config.sh
   ```

The script pushes the branded HTML into all three templates **and** drops
the OTP expiration to 600 s (10 min). Re-run any time you tweak
[`magic_link.html`](./magic_link.html); it's idempotent.

### Option B — manual paste

If you don't want a PAT, you can paste in the dashboard instead:

1. Open Supabase Dashboard → your project
2. Go to **Authentication → Email Templates**
3. For **each** of these templates: **Confirm signup**, **Magic Link**, **Reset Password**
   1. Replace the **Source** with the full contents of [`magic_link.html`](./magic_link.html)
   2. Set the **Subject** to:
      ```
      Your Prestige Café sign-in code
      ```
      *Do not include `{{ .Token }}` in the subject — it would leak the code on
      lock-screen banners and inbox previews.*
   3. Click **Save**
4. Also: **Auth → Providers → Email** → set **Email OTP expiration** to `600`

### Subject alternatives

- `Your verification code for Prestige Café`
- `Prestige Café · Verify your sign-in`

### Variables available in the template

The template uses `{{ .Token }}` for the OTP. Other variables you could swap
in if you ever want a clickable button instead of a code:
- `{{ .ConfirmationURL }}` — magic-link URL
- `{{ .Email }}` — the recipient address
- `{{ .RedirectTo }}` — your configured site URL

## Tightening recommendations

After saving the template, also tighten these settings:

| Setting | Where | Default | Recommended | Why |
|---|---|---|---|---|
| Email OTP expiration | Auth → Providers → Email | 3600s | **600s** | 1 hour is too long; if email is forwarded or screenshotted, an attacker has a full hour |
| Email OTP length | Auth → Providers → Email | 6 | **8** ✅ | More entropy, harder to brute-force (already set to 8 in your project) |
| Confirm email | Auth → Sign Up | ON | **ON** | Required for OTP flow to work properly |
| Enable email + password | Auth → Providers → Email | ON | **OFF** (optional) | We're OTP-only; disabling password auth removes an attack surface |

If you change the OTP length, also update `SUPABASE_OTP_LENGTH` in `.env` so the
app's UI uses the right number of input boxes. The app refuses to verify codes
of the wrong length client-side as a sanity check.

## Email client compatibility

The template is built for max compatibility:
- Tables for layout (Outlook-safe)
- All CSS inlined on elements (Gmail strips `<style>` blocks)
- Hex colors only (no `rgba()` or named CSS colors)
- Web-safe fonts with full fallback stacks
- `☕` emoji for the logo (universal Unicode — no image hosting required)
- Tested visually against Apple Mail, Gmail web, Gmail iOS/Android, Outlook web

## Customizing further

If you want to tweak colors, the brand palette is:

| Token | Hex | Usage |
|---|---|---|
| `brand` | `#B7976E` | Primary accent (top strip middle, code chip border highlight) |
| `brandDeep` | `#8E6E49` | "POS" wordmark, brand text |
| `brandSoft` | `#EAD9C2` | Code chip border |
| `brandTint` | `#F7EFE4` | Body background, logo square, code chip background |
| `ink` | `#151515` | Primary text |
| `inkMuted` | `#6B6B6B` | Secondary text |
| `inkSubtle` | `#A0A0A0` | Footer / fine print |
