# Yosef Coffee — worked example

Reference data we use to validate the seeder + show new clients what a
filled template looks like. Two files matter:

- `source.xlsx` — the client's **original** spreadsheet, exactly as
  received. Ad-hoc layout: section banners as headers, mixed units,
  typos (`worcetershire`, `red oinion`, `sphagetti`), draft blocks
  with `php20` placeholders. **Do not import this directly** — it
  predates the canonical schema.
- `canonical.xlsx` — the same data **re-shaped into the 5-sheet
  template** documented in `../../README.md`. This is what we'd ask
  Yosef to fill if they were onboarding today, and what the importer
  consumes.

`parsed/` holds the intermediate JSON produced while reshaping the
original (`inventory_items.json`, `products.json`, `books.json`,
`spell_fix_map.json`). Kept around so the JSON-style diff between
source and canonical is easy to review.

## Numbers

| Sheet | Rows | Notes |
| --- | --- | --- |
| Categories | 5 | Coffee, Tea, Pastry, Food, Books — seeded explicitly so the Sell grid has chips out of the box. |
| Inventory | 66 | 52 from Sheet 1 of `source.xlsx` + 14 placeholders generated for ingredients referenced in recipes but missing from the master list. Placeholders carry `category: "Placeholder"` so the owner can find and edit them after seeding. |
| Products | 15 | All 16 menu items from Sheet 3 of `source.xlsx`, minus `beef nachos` which only appeared in the matrix view (no recipe block). All defaulted to `type: Food` + `category: Food`; owner re-categorises in-app. |
| Recipes | 74 | All recipe lines normalised to base units (g / ml / pcs). `cup`, `tbsp`, `tsp` from draft blocks were converted to ml via standard ratios. |
| Books | 51 | Unique titles from `books.xlsx` Sheet 1 + supplier cost merged in from Sheet 2's `30% Disc` column (40 of 51 matched). |

## Reshape decisions worth flagging

These would all be obvious during a guided onboarding, but they're the
non-trivial calls the reshape made:

1. **Typos were normalised**, not preserved. `red oinion` → `red onion`.
   The alias map lives at `parsed/spell_fix_map.json`.
2. **Section banner "Entrees"** in Sheet 2 isn't a product — it's the
   header for `pumpkin soup` whose name sits on the next row. The
   reshape uses `pumpkin soup` as the canonical product name.
3. **Two `garlic peppered beef` blocks** in `source.xlsx` — one fully
   costed (rows 47–58), one incomplete (rows 161–167). Kept the
   costed version, dropped the duplicate.
4. **`pizza dough` sub-recipe** is referenced under `pesto parmesan
   pizza` but not sold on its own; dropped as a standalone product.
   Sub-recipes are flattened into the parent recipe.
5. **All products priced ₱250.** Matches what `source.xlsx` showed for
   the costed entries. Draft entries that didn't list a Menu Price
   defaulted to the same.

## Integration fixture for the importer

```bash
dart run supabase/migrations/seeder/importer/import.dart \
  --tenant <yosef_tenant_id> \
  --file supabase/migrations/seeder/examples/yosef_coffee/canonical.xlsx \
  --dry-run
```

Expected output (dry-run): `262 ops · 5 categories · 66 inventory · 15
products · 74 recipe lines · 51 books · 0 errors`.
