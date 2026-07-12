import 'dart:io';

import 'package:args/args.dart';
import 'package:supabase/supabase.dart';

import 'package:prestige_seeder/parser.dart';
import 'package:prestige_seeder/validator.dart';
import 'package:prestige_seeder/writer.dart';

/// One-shot client onboarding importer for Prestige Café.
///
/// Usage:
///   dart run bin/import.dart \
///     --file path/to/canonical.xlsx \
///     --tenant <uuid> \
///     [--apply]            # default is dry-run
///
/// Environment variables (required for --apply):
///   SUPABASE_URL
///   SUPABASE_SERVICE_ROLE_KEY    (bypasses RLS — keep out of git)
Future<void> main(List<String> argv) async {
  final args = (ArgParser()
        ..addOption('file', abbr: 'f', help: 'Path to canonical client xlsx')
        ..addOption('tenant', abbr: 't', help: 'Target tenant uuid')
        ..addOption('supabase-url',
            help: 'Supabase project URL. Falls back to SUPABASE_URL env var.')
        ..addOption('service-role-key',
            help: 'Service role key. Falls back to SUPABASE_SERVICE_ROLE_KEY env var.')
        ..addFlag('apply',
            defaultsTo: false,
            negatable: false,
            help: 'Actually write to the database. Without --apply we dry-run and only validate.')
        ..addFlag('help', abbr: 'h', defaultsTo: false, negatable: false))
      .parse(argv);

  if (args['help'] as bool || args['file'] == null) {
    _printHelp();
    exit(args['help'] as bool ? 0 : 1);
  }

  final filePath = args['file'] as String;
  if (!File(filePath).existsSync()) {
    stderr.writeln('✗ File not found: $filePath');
    exit(2);
  }

  print('━━━ Prestige Café importer ━━━');
  print('File:   $filePath');
  print('Mode:   ${args["apply"] as bool ? "APPLY (will write)" : "dry-run (no DB writes)"}');
  print('');

  // 1. Parse
  print('① Parsing workbook…');
  final wb = WorkbookParser().parseFile(filePath);
  print('   · ${wb.categories.length} categories');
  print('   · ${wb.inventory.length} inventory items');
  print('   · ${wb.products.length} products');
  print('   · ${wb.recipes.length} recipe lines');
  print('   · ${wb.books.length} books');
  if (wb.warnings.isNotEmpty) {
    print('');
    print('   Parser notes:');
    for (final w in wb.warnings) {
      print('   ⚠ $w');
    }
  }

  // 2. Validate
  print('');
  print('② Validating…');
  final result = validate(wb);
  if (result.warnings.isNotEmpty) {
    for (final w in result.warnings) {
      print('   ⚠ $w');
    }
  }
  if (!result.ok) {
    print('');
    print('   ✗ Found ${result.errors.length} error(s) — aborting:');
    for (final e in result.errors) {
      print('     · $e');
    }
    print('');
    print('Fix the spreadsheet and re-run.');
    exit(3);
  }
  print('   ✓ OK — ${wb.totalOps} operations would run.');

  // 3. Apply (optional)
  if (!(args['apply'] as bool)) {
    print('');
    print('③ Dry-run complete. Re-run with --apply to write to the database.');
    return;
  }

  // Real run from here on.
  final tenantId = args['tenant'] as String?;
  if (tenantId == null || tenantId.isEmpty) {
    stderr.writeln('✗ --tenant <uuid> is required for --apply');
    exit(4);
  }
  final url = (args['supabase-url'] as String?) ??
      Platform.environment['SUPABASE_URL'];
  final key = (args['service-role-key'] as String?) ??
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || key == null) {
    stderr.writeln('✗ Supabase URL + service role key required. Pass --supabase-url + --service-role-key, '
        'or set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in your environment.');
    exit(5);
  }

  print('');
  print('③ Writing to tenant $tenantId …');
  final client = SupabaseClient(url, key);
  final seeder = TenantSeeder(client: client, tenantId: tenantId);
  final report = await seeder.run(wb);

  print('');
  print('━━━ Result ━━━');
  print('Categories:        ${report.categories}');
  print('Inventory items:   ${report.inventoryItems} (${report.placeholders} placeholders)');
  print('Products:          ${report.products}');
  print('Recipe lines:      ${report.recipeLines}');
  if (report.errors.isNotEmpty) {
    print('');
    print('⚠ ${report.errors.length} error(s):');
    for (final e in report.errors) {
      print('  · $e');
    }
  } else {
    print('');
    print('✓ Import complete.');
    if (report.placeholders > 0) {
      print('  Next step: open Stock and edit the ${report.placeholders} placeholder items '
          '(category = "Placeholder") to set their real pack price + starting stock.');
    }
  }
}

void _printHelp() {
  print('''
Prestige Café — client onboarding importer

Usage:
  dart run bin/import.dart --file <canonical.xlsx> [options]

Options:
  -f, --file <path>           Path to the canonical client xlsx (required).
  -t, --tenant <uuid>         Target tenant id (required for --apply).
      --apply                 Write to the DB. Without this, dry-run only.
      --supabase-url <url>    Defaults to SUPABASE_URL env var.
      --service-role-key <k>  Defaults to SUPABASE_SERVICE_ROLE_KEY env var.
  -h, --help

Examples:
  # Dry-run against the worked Yosef Coffee example:
  dart run bin/import.dart \\
    --file ../examples/yosef_coffee/canonical.xlsx

  # Actually write:
  export SUPABASE_URL=https://your-project.supabase.co
  export SUPABASE_SERVICE_ROLE_KEY=eyJ...
  dart run bin/import.dart \\
    --file ../examples/yosef_coffee/canonical.xlsx \\
    --tenant 00000000-0000-0000-0000-000000000000 \\
    --apply
''');
}
