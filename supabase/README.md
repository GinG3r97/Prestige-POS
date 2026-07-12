# Supabase

Source-controlled schema and config for the Prestige Café Supabase project.

## `migrations/`

One SQL file per schema change, named `YYYYMMDDHHMMSS_short_slug.sql`. Format
matches the Supabase CLI convention so `supabase db push` works out of the box
if/when we adopt the CLI locally.

**Rules**

- **Never edit an applied migration.** If you need to change something, write
  a new migration that ALTERs / DROPs / REPLACEs. Applied migrations are
  immutable — the timestamp is their identity.
- **Filename = ordering.** Migrations are applied in lexicographic order, so
  the `YYYYMMDDHHMMSS` prefix is load-bearing. Don't use random IDs.
- **Idempotent where possible.** Prefer `create extension if not exists`,
  `create or replace function`, `add column if not exists`, etc. so partial
  re-runs don't blow up.

## Applied migrations to date

| Version | Name | What it does |
|---|---|---|
| `20260519182109` | `harden_rls_auto_enable_grants` | Revokes EXECUTE on the Supabase-managed `rls_auto_enable()` function from `anon` / `authenticated` / `PUBLIC`. The function is invoked by the `ensure_rls` event trigger which runs as `postgres`, so revoking direct callers is safe and silences a security advisor. |
| `20260519191456` | `tenants_branches_owner_pins` | Creates the core tables `public.tenants`, `public.branches`, `public.owner_pins` with full RLS scoped to `auth.uid() = owner_id`. Adds the `set_owner_pin` and `verify_owner_pin` RPC functions (bcrypt-hashed PIN with 5-attempt lockout). |
| `20260519192423` | `fix_owner_pin_pgcrypto_path` | Schema-qualifies `crypt()` / `gen_salt()` calls to `extensions.crypt` / `extensions.gen_salt` and adds `extensions` to the RPCs' `search_path`. Fixes a runtime error when calling `set_owner_pin` because pgcrypto lives in the `extensions` schema, not `public`. |

## How we apply migrations today

For now, migrations are authored in this folder AND applied to the hosted
project through the Supabase MCP (`mcp__supabase__apply_migration`). The MCP
records the migration in Supabase's own `supabase_migrations.schema_migrations`
ledger, so the two sources of truth stay in sync as long as we:

1. Write the SQL into a new file here first (next available timestamp)
2. Invoke `apply_migration` via MCP with the **same** name slug
3. Commit the file to git

In the future, when we adopt the Supabase CLI locally, `supabase db push`
will pick this folder up and reconcile against the remote ledger
automatically.

## Naming a new migration

```bash
date -u +"%Y%m%d%H%M%S"        # → 20260520143052 (UTC, for monotonic ordering)
# new file:
# supabase/migrations/20260520143052_what_this_does.sql
```

Then either:

- Apply via MCP (`mcp__supabase__apply_migration` with the same name), or
- (Later) `supabase db push` from the project root
