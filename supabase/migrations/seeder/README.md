# Prestige POS — client onboarding data format

This is the **canonical xlsx schema** every new tenant fills out before
seeding. One template, one importer, every store. The xlsx is sent to
us (or, later, uploaded in-app at Settings → Import data) and we run a
one-shot Dart importer that writes everything to their tenant in a single
transaction.

The goal isn't to match how owners *already* track their data — most of
them keep ad-hoc spreadsheets with mixed units and typos. The goal is to
teach the right shape from day one so:

- Recipes auto-deduct from inventory cleanly (no unit conversion fights).
- Cost-per-unit comes from a single source of truth.
- Re-imports are idempotent (keyed on lowercased `name`).
- Owners can keep editing in-app after the initial seed.

## Folder map

```
supabase/migrations/seeder/
├── README.md                    ← this file (the standard)
├── template.xlsx                ← blank we send to new clients (TODO)
├── importer/                    ← Dart one-shot script (TODO)
└── examples/
    └── yosef_coffee/            ← reference: a real client's data,
        ├── source.xlsx          ← their original (non-standard) sheet
        ├── README.md            ← notes on how we mapped it
        └── parsed/              ← what the importer would produce
            ├── inventory_items.json
            ├── products.json
            ├── books.json
            └── spell_fix_map.json
```

## The xlsx schema

Five sheets, in this order. Empty sheets are skipped. Header row 1
(case-sensitive) defines columns. Empty rows are skipped. Trim
whitespace.

### 1. `Categories` (optional)

Tenant-level categories shown in the Sell grid. If omitted, the
importer auto-creates categories from any name referenced in
`Products.category` that doesn't already exist.

| Column | Required | Notes |
| --- | --- | --- |
| `name` | yes | Unique per tenant. Case-insensitive. |
| `icon_name` | no | One of the keys in our curated icon set (see `lib/design_system/icons.dart`). Falls back to keyword auto-match if blank. |
| `sort_order` | no | Integer. Defaults to insertion order × 10. |

### 2. `Inventory`

Physical stock the kitchen / bar / shelf consumes. One row per item.

| Column | Required | Notes |
| --- | --- | --- |
| `name` | yes | Unique per tenant, case-insensitive. |
| `category` | yes | Free text. Owners use this for filtering in Stock. |
| `unit` | yes | One of: `g`, `ml`, `pcs`. **This is the base unit recipes refer to.** Use grams for solids, ml for liquids, pcs for countables. Internally we still support `kg` / `L` for entry but normalise to `g` / `ml`. |
| `unit_label` | no | Display override (e.g. type `shot`, `slice`, `tray`). Recipe math still uses `unit`. |
| `pack_size` | yes | Quantity in one purchased pack, expressed in `unit`. e.g. a 1kg bag of bacon → `pack_size = 1000` with `unit = g`. |
| `pack_price` | yes | What you pay for one pack, in PHP. Cost-per-unit is derived: `pack_price / pack_size`. |
| `starting_stock` | no | Current stock, in `unit`. Defaults to 0. |
| `low_stock_threshold` | no | In `unit`. Defaults to 0 (no alert). |
| `supplier` | no | Free text. |

### 3. `Products`

The menu — everything sold. One row per product. Modifiers (size,
temperature, strength) are added later in-app; the importer keeps the
schema minimal.

| Column | Required | Notes |
| --- | --- | --- |
| `name` | yes | Unique per tenant. |
| `type` | yes | One of: `Drink`, `Food`, `Pastry`, `Book`, `Retail`, `Service`. Drives `supports_modifiers` + `deducts_stock` behaviour. |
| `category` | yes | Must match a `Categories` row (or one we auto-create). |
| `base_price` | yes | In PHP. |
| `subtitle` | no | Single-line description shown on the product detail sheet. |
| `image_url` | no | If empty, the product tile renders a Material icon based on name / category. Owners can upload images in-app after seeding. |
| `available` | no | `yes` / `no`. Defaults to `yes`. |

### 4. `Recipes`

Links products to inventory items. **Quantities are in the inventory
item's `unit`**, so a recipe line "Americano needs 18g coffee beans"
becomes `quantity = 18` (because the coffee-beans inventory row was
defined with `unit = g`).

If a product is a `Service` or `Book`, leave it out of this sheet — the
importer wires Book to `[{self: 1 pcs}]` automatically and Service to no
recipe.

| Column | Required | Notes |
| --- | --- | --- |
| `product_name` | yes | Must match a row in `Products`. |
| `ingredient_name` | yes | Must match a row in `Inventory`. |
| `quantity` | yes | Numeric. Same unit as the inventory item. |

### 5. `Books` (optional shortcut)

For bookstore tenants. One row creates **both** an inventory item
(`unit: pcs`) and a 1:1 product (`type: Book`, recipe = 1 pc of itself).
Avoids the duplication of listing every book in three sheets.

| Column | Required | Notes |
| --- | --- | --- |
| `sku` | yes | Product ID / ISBN. Stored on the inventory item. |
| `title` | yes | Used as both inventory item name and product name. |
| `selling_price` | yes | In PHP. |
| `cost_price` | no | Supplier cost. If blank, defaults to 30% of selling price (standard book margin). |
| `starting_stock` | no | Defaults to 0. |
| `category` | no | Defaults to `Books`. |

## Normalisation rules the importer enforces

- **Names are de-duplicated case-insensitively.** "Coffee Beans" and
  "coffee beans" become the same row. Last-write wins.
- **All quantities are converted to the base unit at write time.** If
  someone types `1` with unit `kg`, we store `1000` and `g`.
- **Cost-per-unit is derived, never stored as-typed.** That keeps it
  consistent across imports if the pack size changes later.
- **Unknown ingredient names abort the row, not the whole import.** The
  importer prints the unresolved name and skips that recipe line.
  Owners fix the spelling and re-run; the re-run is idempotent.

## Out of scope for the template

These are added in-app, not via the import:

- Modifier groups (Size / Temperature / Strength) and their pricing
  adjustments — too tangled to express in a flat spreadsheet, and the
  in-app editor with the live recipe preview is the right tool.
- Employee accounts, roles, PINs.
- Payroll templates, leave types.
- Add-ons (`+ extra shot`, `+ whipped cream`).
- Tax / receipt configuration.

## See `examples/yosef_coffee/`

A real client's pre-standard data (`source.xlsx`) + the README explaining
how it was reshaped into our schema. Useful as a worked example when
training new clients on how to fill the template.
