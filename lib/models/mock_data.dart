import 'catalog.dart';
import 'employee.dart';
import 'inventory.dart';
import 'money.dart';
import 'payroll.dart';
import 'payroll_rules.dart';

class MockData {
  static final branches = [
    Branch(name: 'Main Branch'),
    Branch(name: 'Tagaytay'),
  ];

  static List<InventoryItem> seedInventory() => [
        InventoryItem(
          name: 'Coffee Beans (House Blend)',
          sku: 'COF-001',
          category: 'Coffee & Tea',
          unit: StockUnit.grams,
          currentStock: 2400,
          lowStockThreshold: 500,
          costPerUnit: 1.20,
          supplier: 'Mountain Roasters Co.',
          lastRestockedAt: DateTime.now().subtract(const Duration(days: 4)),
        ),
        InventoryItem(
          name: 'Whole Milk',
          sku: 'MLK-001',
          category: 'Dairy',
          unit: StockUnit.milliliters,
          currentStock: 4500,
          lowStockThreshold: 2000,
          costPerUnit: 0.08,
          supplier: 'Daily Dairy',
          lastRestockedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
        InventoryItem(
          name: 'Oat Milk',
          sku: 'MLK-002',
          category: 'Dairy',
          unit: StockUnit.milliliters,
          currentStock: 800,
          lowStockThreshold: 1500,
          costPerUnit: 0.18,
          supplier: 'Daily Dairy',
        ),
        InventoryItem(
          name: 'Sugar (White)',
          sku: 'SUG-001',
          category: 'Food Ingredients',
          unit: StockUnit.grams,
          currentStock: 1800,
          lowStockThreshold: 500,
          costPerUnit: 0.05,
        ),
        InventoryItem(
          name: 'Vanilla Syrup',
          sku: 'SYR-001',
          category: 'Syrups & Sauces',
          unit: StockUnit.milliliters,
          currentStock: 600,
          lowStockThreshold: 250,
          costPerUnit: 0.12,
        ),
        InventoryItem(
          name: 'Chocolate Syrup',
          sku: 'SYR-002',
          category: 'Syrups & Sauces',
          unit: StockUnit.milliliters,
          currentStock: 350,
          lowStockThreshold: 250,
          costPerUnit: 0.14,
        ),
        InventoryItem(
          name: 'Paper Cups (12oz)',
          sku: 'CUP-012',
          category: 'Packaging',
          unit: StockUnit.pieces,
          currentStock: 120,
          lowStockThreshold: 50,
          costPerUnit: 3.50,
          supplier: 'Pack & Go',
        ),
        InventoryItem(
          name: 'Paper Cups (16oz)',
          sku: 'CUP-016',
          category: 'Packaging',
          unit: StockUnit.pieces,
          currentStock: 30,
          lowStockThreshold: 50,
          costPerUnit: 4.00,
        ),
        InventoryItem(
          name: 'Plastic Lids',
          sku: 'LID-001',
          category: 'Packaging',
          unit: StockUnit.pieces,
          currentStock: 240,
          lowStockThreshold: 100,
          costPerUnit: 1.50,
        ),
        InventoryItem(
          name: 'Ice (cubes)',
          sku: 'ICE-001',
          category: 'Other',
          unit: StockUnit.pieces,
          currentStock: 800,
          lowStockThreshold: 200,
          costPerUnit: 0.02,
        ),
      ];

  static final members = [
    Member(name: 'Anna Dela Cruz', tier: MemberTier.gold),
    Member(name: 'Lester Chan'),
    Member(name: 'Nina Patel', tier: MemberTier.gold),
    Member(name: 'Carlos Reyes', churned: true),
  ];

  /// Philippine-default leave bank for a fresh store. Owners edit in Maintenance.
  static List<LeaveType> seedLeaveTypes() => [
        LeaveType(
          name: 'Service Incentive Leave',
          emoji: '🌴',
          annualDays: 5,
          paid: true,
          notes: 'Mandatory under PH Labour Code (Art. 95)',
        ),
        LeaveType(
          name: 'Vacation Leave',
          emoji: '✈️',
          annualDays: 10,
          paid: true,
        ),
        LeaveType(
          name: 'Sick Leave',
          emoji: '🤒',
          annualDays: 7,
          paid: true,
        ),
        LeaveType(
          name: 'Emergency Leave',
          emoji: '🚨',
          annualDays: 3,
          paid: true,
          notes: 'Bereavement, family emergencies',
        ),
        LeaveType(
          name: 'Unpaid Leave',
          emoji: '🏖️',
          annualDays: 0,
          paid: false,
          notes: 'No cap, deducted from pay',
        ),
      ];


  /// Seeds the tenant's global add-ons catalog. Cashiers can attach any of
  /// these to any product at order time.
  // seedAddOns removed — add-ons are now DB-backed via the `add_ons` table.

  /// Seeds a tenant's product catalog with recipes that reference the freshly
  /// seeded inventory list. Pass `inventory` from [seedInventory].
  static List<CafeItem> seedCafeProducts(List<InventoryItem> inventory) {
    String idOf(String name) =>
        inventory.firstWhere((i) => i.name == name).id;

    final coffeeId = idOf('Coffee Beans (House Blend)');
    final milkId = idOf('Whole Milk');
    final sugarId = idOf('Sugar (White)');
    final vanillaId = idOf('Vanilla Syrup');
    final chocoId = idOf('Chocolate Syrup');
    final cup12Id = idOf('Paper Cups (12oz)');
    final lidId = idOf('Plastic Lids');
    final iceId = idOf('Ice (cubes)');

    ModifierGroup sizes() => ModifierGroup(
          name: 'Size',
          required: true,
          defaultIndex: 1, // Medium
          options: [
            ModifierOption(name: 'Small'),
            ModifierOption(name: 'Medium', priceDelta: Money.pesos(15)),
            ModifierOption(name: 'Large', priceDelta: Money.pesos(30)),
          ],
        );
    ModifierGroup temperature() => ModifierGroup(
          name: 'Temperature',
          required: true,
          options: [
            ModifierOption(name: 'Hot'),
            ModifierOption(name: 'Cold'),
          ],
        );
    ModifierGroup strength() => ModifierGroup(
          name: 'Strength',
          required: false,
          defaultIndex: 0, // Mild
          options: [
            ModifierOption(name: 'Mild'),
            ModifierOption(name: 'Strong', priceDelta: Money.pesos(15)),
          ],
        );

    /// Builds adjustments for size + temperature + strength variations.
    /// Sizes scale all base lines; Iced adds 5pcs ice; Strong adds 5g coffee.
    List<ModifierAdjustment> standardAdjustments({
      required ModifierGroup sizeGroup,
      required ModifierGroup tempGroup,
      ModifierGroup? strengthGroup,
    }) {
      final adj = <ModifierAdjustment>[];
      // Multipliers per size (Small=0.85, Medium=1.0, Large=1.4).
      const sizeFactors = [0.85, 1.0, 1.4];
      for (var i = 0; i < sizeGroup.options.length; i++) {
        if (i == sizeGroup.defaultIndex) continue;
        adj.add(ModifierAdjustment(
          groupId: sizeGroup.id,
          optionId: sizeGroup.options[i].id,
          kind: AdjustmentKind.multiplier,
          multiplier: sizeFactors[i],
        ));
      }
      // Cold drinks consume extra ice.
      final coldOpt =
          tempGroup.options.firstWhere((o) => o.name == 'Cold');
      adj.add(ModifierAdjustment(
        groupId: tempGroup.id,
        optionId: coldOpt.id,
        kind: AdjustmentKind.addLines,
        addLines: [
          RecipeLine(inventoryItemId: iceId, quantity: 5),
        ],
      ));
      if (strengthGroup != null) {
        final strongOpt = strengthGroup.options
            .firstWhere((o) => o.name == 'Strong');
        adj.add(ModifierAdjustment(
          groupId: strengthGroup.id,
          optionId: strongOpt.id,
          kind: AdjustmentKind.addLines,
          addLines: [
            RecipeLine(inventoryItemId: coffeeId, quantity: 5),
          ],
        ));
      }
      return adj;
    }

    final americanoSizes = sizes();
    final americanoTemp = temperature();
    final americanoStrength = strength();
    final latteSizes = sizes();
    final latteTemp = temperature();
    final cappSizes = sizes();
    final cappTemp = temperature();
    final spanishSizes = sizes();
    final spanishTemp = temperature();
    final mochaSizes = sizes();
    final mochaTemp = temperature();
    final earlSizes = sizes();
    final earlTemp = temperature();
    final strawSizes = sizes();

    return [
      CafeItem(
        name: 'Americano',
        subtitle: 'Signature espresso + hot water',
        category: CafeCategory.coffee,
        basePrice: Money.pesos(145),
        emoji: '☕',
        tag: TagKind.hit,
        modifierGroups: [americanoSizes, americanoTemp, americanoStrength],
        recipe: [
          RecipeLine(inventoryItemId: coffeeId, quantity: 10),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: americanoSizes,
          tempGroup: americanoTemp,
          strengthGroup: americanoStrength,
        ),
      ),
      CafeItem(
        name: 'Cafe Latte',
        subtitle: 'Espresso with steamed milk',
        category: CafeCategory.coffee,
        basePrice: Money.pesos(165),
        emoji: '🥛',
        modifierGroups: [latteSizes, latteTemp],
        recipe: [
          RecipeLine(inventoryItemId: coffeeId, quantity: 10),
          RecipeLine(inventoryItemId: milkId, quantity: 150),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: latteSizes,
          tempGroup: latteTemp,
        ),
      ),
      CafeItem(
        name: 'Cappuccino',
        subtitle: 'Espresso, milk, and foam',
        category: CafeCategory.coffee,
        basePrice: Money.pesos(165),
        emoji: '☕',
        modifierGroups: [cappSizes, cappTemp],
        recipe: [
          RecipeLine(inventoryItemId: coffeeId, quantity: 10),
          RecipeLine(inventoryItemId: milkId, quantity: 100),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: cappSizes,
          tempGroup: cappTemp,
        ),
      ),
      CafeItem(
        name: 'Spanish Latte',
        subtitle: 'Sweet latte with condensed milk',
        category: CafeCategory.coffee,
        basePrice: Money.pesos(185),
        emoji: '🥛',
        tag: TagKind.$new,
        modifierGroups: [spanishSizes, spanishTemp],
        recipe: [
          RecipeLine(inventoryItemId: coffeeId, quantity: 10),
          RecipeLine(inventoryItemId: milkId, quantity: 150),
          RecipeLine(inventoryItemId: sugarId, quantity: 8),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: spanishSizes,
          tempGroup: spanishTemp,
        ),
      ),
      CafeItem(
        name: 'Mocha',
        subtitle: 'Espresso with chocolate',
        category: CafeCategory.coffee,
        basePrice: Money.pesos(175),
        emoji: '🍫',
        modifierGroups: [mochaSizes, mochaTemp],
        recipe: [
          RecipeLine(inventoryItemId: coffeeId, quantity: 10),
          RecipeLine(inventoryItemId: milkId, quantity: 130),
          RecipeLine(inventoryItemId: chocoId, quantity: 15),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: mochaSizes,
          tempGroup: mochaTemp,
        ),
      ),
      CafeItem(
        name: 'Earl Grey',
        subtitle: 'Bergamot black tea',
        category: CafeCategory.tea,
        basePrice: Money.pesos(120),
        emoji: '🍵',
        modifierGroups: [earlSizes, earlTemp],
        recipe: [
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
        modifierAdjustments: standardAdjustments(
          sizeGroup: earlSizes,
          tempGroup: earlTemp,
        ),
      ),
      CafeItem(
        name: 'Strawberry Frappé',
        subtitle: 'Blended strawberry with cream',
        category: CafeCategory.frappe,
        basePrice: Money.pesos(195),
        emoji: '🍓',
        tag: TagKind.sale,
        modifierGroups: [strawSizes],
        recipe: [
          RecipeLine(inventoryItemId: milkId, quantity: 200),
          RecipeLine(inventoryItemId: sugarId, quantity: 12),
          RecipeLine(inventoryItemId: vanillaId, quantity: 10),
          RecipeLine(inventoryItemId: iceId, quantity: 8),
          RecipeLine(inventoryItemId: cup12Id, quantity: 1),
          RecipeLine(inventoryItemId: lidId, quantity: 1),
        ],
      ),
      CafeItem(
        name: 'Croissant',
        subtitle: 'Buttery flaky pastry',
        category: CafeCategory.pastry,
        basePrice: Money.pesos(95),
        emoji: '🥐',
        itemType: ItemType.food,
      ),
      CafeItem(
        name: 'Chocolate Cake',
        subtitle: 'Rich dark chocolate slice',
        category: CafeCategory.pastry,
        basePrice: Money.pesos(135),
        emoji: '🍰',
        itemType: ItemType.food,
      ),
      CafeItem(
        name: 'Pesto Pasta',
        subtitle: 'Fresh basil, parmesan',
        category: CafeCategory.food,
        basePrice: Money.pesos(245),
        emoji: '🍝',
        itemType: ItemType.food,
      ),
    ];
  }

  /// Seeds a starter timesheet — last 7 days of varied hours per employee.
  /// Salaried staff also get logged hours (used only for display / OT tracking,
  /// not multiplied against their rate).
  static List<TimeEntry> seedTimeEntries(List<Employee> employees) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 6));
    final entries = <TimeEntry>[];
    for (final e in employees) {
      if (e.status != EmployeeStatus.active) continue;
      for (var d = 0; d < 7; d++) {
        final date = start.add(Duration(days: d));
        final weekday = date.weekday;
        final shift = e.schedule
            .where((s) => s.weekday == weekday)
            .firstOrNull;
        if (shift == null) continue;
        final h = _hoursBetween(shift.start, shift.end);
        if (h <= 0) continue;
        entries.add(TimeEntry(
          employeeId: e.id,
          date: date,
          hours: h,
        ));
      }
    }
    return entries;
  }

  static double _hoursBetween(String start, String end) {
    final s = start.split(':');
    final e = end.split(':');
    final sm = int.parse(s[0]) * 60 + int.parse(s[1]);
    final em = int.parse(e[0]) * 60 + int.parse(e[1]);
    return (em - sm) / 60.0;
  }
}
