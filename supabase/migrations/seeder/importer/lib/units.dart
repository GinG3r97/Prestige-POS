/// Maps anything an owner might type for a unit to our canonical g / ml / pcs.
/// `kg` and `L` are accepted on entry but normalised so all downstream
/// quantities are in the base unit.
({String unit, double multiplier})? normaliseUnit(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'g':
    case 'gram':
    case 'grams':
    case 'grm':
    case 'grms':
      return (unit: 'g', multiplier: 1);
    case 'kg':
    case 'kilo':
    case 'kilos':
    case 'kilogram':
    case 'kilograms':
      return (unit: 'g', multiplier: 1000);
    case 'ml':
    case 'mls':
    case 'milliliter':
    case 'milliliters':
      return (unit: 'ml', multiplier: 1);
    case 'l':
    case 'ltr':
    case 'liter':
    case 'liters':
    case 'litre':
    case 'litres':
      return (unit: 'ml', multiplier: 1000);
    case 'pc':
    case 'pcs':
    case 'piece':
    case 'pieces':
      return (unit: 'pcs', multiplier: 1);
    default:
      return null;
  }
}

/// Allowed values for the `Products.type` column. Drives the product-type FK
/// in the DB (which decides whether a product `supports_modifiers` and
/// `deducts_stock`).
const productTypeLabels = {
  'drink': 'Drink',
  'food': 'Food',
  'pastry': 'Pastry',
  'book': 'Book',
  'retail': 'Retail',
  'service': 'Service',
};

String? canonicaliseProductType(String raw) =>
    productTypeLabels[raw.trim().toLowerCase()];
