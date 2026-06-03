import 'models.dart';

/// Cross-sheet validation pass. Reports issues in plain English with
/// row counts so the owner can fix the spreadsheet without grepping the
/// DB for FK errors.
ValidationResult validate(ParsedWorkbook wb) {
  final errors = <String>[];
  final warnings = <String>[];

  // 1. Duplicate inventory names (case-insensitive)
  final invSeen = <String, int>{};
  for (final r in wb.inventory) {
    final k = r.name.toLowerCase();
    invSeen[k] = (invSeen[k] ?? 0) + 1;
  }
  for (final e in invSeen.entries.where((e) => e.value > 1)) {
    errors.add('Inventory: "${e.key}" appears ${e.value} times. Keep only one row per item (last wins on re-import, but a duplicate in the same file is ambiguous).');
  }

  // 2. Duplicate product names
  final prodSeen = <String, int>{};
  for (final r in wb.products) {
    final k = r.name.toLowerCase();
    prodSeen[k] = (prodSeen[k] ?? 0) + 1;
  }
  for (final e in prodSeen.entries.where((e) => e.value > 1)) {
    errors.add('Products: "${e.key}" appears ${e.value} times. Each product name must be unique.');
  }

  // 3. Recipe references resolve
  final invNames = wb.inventory.map((r) => r.name.toLowerCase()).toSet();
  final prodNames = wb.products.map((r) => r.name.toLowerCase()).toSet();
  for (final r in wb.recipes) {
    if (!prodNames.contains(r.productName.toLowerCase())) {
      errors.add('Recipes: product "${r.productName}" not found in the Products sheet. Check the spelling.');
    }
    if (!invNames.contains(r.ingredientName.toLowerCase())) {
      warnings.add('Recipes: ingredient "${r.ingredientName}" not found in Inventory. A placeholder will be auto-created — edit it on the Stock page after import.');
    }
  }

  // 4. Book sku uniqueness — warning only (the DB doesn't enforce
  //    unique SKU; owners just find duplicate SKUs hard to scan later).
  final bookSku = <String, int>{};
  for (final b in wb.books) {
    bookSku[b.sku] = (bookSku[b.sku] ?? 0) + 1;
  }
  final dupSkus = bookSku.entries.where((e) => e.value > 1).toList();
  if (dupSkus.isNotEmpty) {
    warnings.add('Books: ${dupSkus.length} SKU(s) appear more than once '
        '(${dupSkus.take(3).map((e) => "${e.key}×${e.value}").join(", ")}'
        '${dupSkus.length > 3 ? "…" : ""}). The import will succeed but '
        'consider assigning each book a unique SKU for easier reconciliation.');
  }

  // Book TITLE uniqueness IS enforced (title becomes inventory name +
  // product name, both of which must be unique within the tenant).
  final bookTitle = <String, int>{};
  for (final b in wb.books) {
    bookTitle[b.title.toLowerCase()] = (bookTitle[b.title.toLowerCase()] ?? 0) + 1;
  }
  for (final e in bookTitle.entries.where((e) => e.value > 1)) {
    errors.add('Books: title "${e.key}" appears ${e.value} times. Each book title must be unique.');
  }

  // 5. Products referencing categories — flag if no Categories sheet declares them, just FYI
  final declaredCats = wb.categories.map((c) => c.name.toLowerCase()).toSet();
  final referenced = wb.products.map((p) => p.category.toLowerCase()).toSet();
  final autoCreate = referenced.difference(declaredCats);
  if (autoCreate.isNotEmpty) {
    warnings.add('Products reference ${autoCreate.length} category not declared in Categories: ${autoCreate.join(", ")}. They will be auto-created.');
  }

  return ValidationResult(errors: errors, warnings: warnings);
}
