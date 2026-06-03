# Prestige POS — onboarding importer

Standalone Dart CLI that reads the canonical client xlsx (see
[../README.md](../README.md)) and writes the data into a tenant via the
Supabase REST API. Pure Dart — no Flutter dependency — so it can run on
any machine with the Dart SDK installed.

## Setup

```bash
cd supabase/migrations/seeder/importer
dart pub get
```

## Dry-run (safe — no DB writes)

Always start here. Validates the spreadsheet, prints the row counts
and any issues, but doesn't write a single row.

```bash
dart run bin/import.dart \
  --file ../examples/yosef_coffee/canonical.xlsx
```

You should see something like:

```
━━━ Prestige POS importer ━━━
File:   ../examples/yosef_coffee/canonical.xlsx
Mode:   dry-run (no DB writes)

① Parsing workbook…
   · 5 categories
   · 66 inventory items
   · 15 products
   · 74 recipe lines
   · 51 books

② Validating…
   ✓ OK — 262 operations would run.

③ Dry-run complete. Re-run with --apply to write to the database.
```

## Applying to a real tenant

You need the service-role key for the project. Treat it like a
password — never commit it.

```bash
export SUPABASE_URL=https://<project>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=eyJ...

dart run bin/import.dart \
  --file ../examples/yosef_coffee/canonical.xlsx \
  --tenant 00000000-0000-0000-0000-000000000000 \
  --apply
```

## What it writes

| Sheet input | DB tables touched |
| --- | --- |
| Categories | `categories` (upsert on lowercased name within tenant) |
| Inventory | `inventory_items` (upsert on lowercased name; cost is derived from `pack_price / pack_size`) |
| Products | `products` (upsert on lowercased name; `type_id` resolved from `product_types`, `category_id` from `categories`) |
| Recipes | merged into `products.recipe` jsonb when the parent product is upserted |
| Books | each row → one `inventory_items` row (`unit: pcs`) + one `products` row (`type: Book`, `recipe: [{self, 1 pcs}]`) |

## Idempotency

Re-running the same import is safe — every row is keyed on lowercased
name within the tenant and **updated** if it already exists, never
duplicated. So the workflow is:

1. Send the client the [template](../template.xlsx).
2. Client fills it, sends it back.
3. Dry-run, share any warnings with the client.
4. They edit + resend if needed.
5. `--apply` once it's clean.
6. Owner opens the app and refines categories / modifiers / images.

## Error model

We surface row-and-column errors with suggested fixes. Examples:

```
⚠ Inventory row 14 "house mayo" missing a required field — skipped.
⚠ Recipes row 28: ingredient "Coffe Beans" not found in Inventory. Closest
  match: "Coffee Beans". Fix the spelling and re-run.
✗ Products: "Americano" appears 2 times. Each product name must be unique.
```

The dry-run aborts on any `✗` error. Re-run after fixing the
spreadsheet — re-runs are idempotent so no cleanup needed.
