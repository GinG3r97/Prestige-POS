import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';
import '../../models/category.dart' as cat;
import '../../models/employee.dart';
import '../../models/money.dart';
import '../../models/inventory.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import 'add_on_form_dialog.dart';
import 'bookable_resources_tab.dart';
import 'payroll_rules_tab.dart';

class MaintenanceView extends StatelessWidget {
  const MaintenanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Only surface the Bookable tab when the store enabled bookings/co-working
    // at setup (same flag that drives the Bookings nav). Otherwise it's noise.
    final showBookable = state.features.reserveEnabled;
    return DefaultTabController(
      length: showBookable ? 7 : 6,
      child: Container(
        color: YColor.surface2,
        child: Column(
          children: [
            // Header
            Container(
              color: YColor.surface1,
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Maintenance',
                      style: YFont.titleLG()
                          .copyWith(fontSize: 30, letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  TabBar(
                    isScrollable: true,
                    // center the row when it fits the viewport, scroll when
                    // it overflows on narrower screens.
                    tabAlignment: TabAlignment.center,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorColor: YColor.brand,
                    indicatorWeight: 3,
                    labelColor: YColor.brand,
                    unselectedLabelColor: YColor.inkMuted,
                    labelStyle: YFont.bodyStrong().copyWith(fontSize: 14),
                    unselectedLabelStyle:
                        YFont.bodyStrong().copyWith(fontSize: 14),
                    tabs: [
                      const Tab(
                        icon: Icon(Icons.tune_outlined, size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Modifiers',
                      ),
                      const Tab(
                        icon: Icon(Icons.add_circle_outline, size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Add-ons',
                      ),
                      const Tab(
                        icon: Icon(Icons.inventory_2_outlined, size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Inventory',
                      ),
                      const Tab(
                        icon: Icon(Icons.label_outline, size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Product',
                      ),
                      const Tab(
                        icon: Icon(Icons.badge_outlined, size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Roles',
                      ),
                      const Tab(
                        icon: Icon(Icons.account_balance_wallet_outlined,
                            size: 18),
                        iconMargin: EdgeInsets.only(bottom: 2),
                        text: 'Payroll',
                      ),
                      if (showBookable)
                        const Tab(
                          icon: Icon(Icons.event_available_outlined, size: 18),
                          iconMargin: EdgeInsets.only(bottom: 2),
                          text: 'Bookable',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: TabBarView(
                // Tabs only switch via the TabBar — no left/right swipe.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ModifierGroupsTab(state: state),
                  _AddOnsTab(state: state),
                  _InventoryCategoriesTab(state: state),
                  _ProductAreaTab(state: state),
                  _RolesTab(state: state),
                  PayrollRulesTab(state: state),
                  if (showBookable) BookableResourcesTab(state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───── Product area: Types + Sub-types as a Sell-style two-pane ─────

class _ProductAreaTab extends StatefulWidget {
  const _ProductAreaTab({required this.state});
  final AppState state;
  @override
  State<_ProductAreaTab> createState() => _ProductAreaTabState();
}

class _ProductAreaTabState extends State<_ProductAreaTab> {
  String? _typeId;
  bool _showTracking = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final types = state.productTypes;
    if (_typeId == null || !types.any((t) => t.id == _typeId)) {
      _typeId = types.isNotEmpty ? types.first.id : null;
    }
    final selType = _typeId == null ? null : state.productTypeById(_typeId);
    final subs = _typeId == null
        ? const <cat.Category>[]
        : state.categoriesForType(_typeId);

    return Row(
      // Top-align both panes so the detail header sits up with the rail
      // instead of being vertically centred (which read as a big gap above it).
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left nav rail: Product Types + the selected type's Sub-types ──
        Container(
          width: 252,
          decoration: const BoxDecoration(
            color: YColor.surface1,
            border: Border(right: BorderSide(color: YColor.hairline)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
            children: [
              _railHeader('PRODUCT TYPES',
                  () => showProductTypeEditor(context)),
              const SizedBox(height: 8),
              for (final t in types)
                _navRow(
                  label: t.name,
                  iconName: t.iconName,
                  fallback: Icons.label_outline,
                  selected: !_showTracking && t.id == _typeId,
                  onTap: () => setState(() {
                    _typeId = t.id;
                    _showTracking = false;
                  }),
                ),
              if (types.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text('No types yet',
                      style:
                          YFont.caption().copyWith(color: YColor.inkMuted)),
                ),
              const SizedBox(height: 12),
              const Divider(color: YColor.hairline, height: 1),
              const SizedBox(height: 8),
              _navRow(
                label: 'Inventory tracking',
                fallback: Icons.inventory_2_outlined,
                selected: _showTracking,
                onTap: () => setState(() => _showTracking = true),
              ),
            ],
          ),
        ),
        // ── Right detail pane ──
        Expanded(
          child: _showTracking
              ? _trackingPane(context, state)
              : selType == null
                  ? Center(
                      child: _emptyCard(
                        icon: Icons.label_outline,
                        title: 'No product types yet',
                        subtitle:
                            'Add a type like Drinks, Foods, or Service to start.',
                      ),
                    )
                  : _detail(context, state, selType, subs),
        ),
      ],
    );
  }

  /// Right pane shown when "Inventory tracking" is selected in the rail — the
  /// store-wide master switch + a plain-English explanation.
  Widget _trackingPane(BuildContext context, AppState state) {
    final on = state.inventoryTrackingEnabled;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(on ? Icons.inventory_2 : Icons.inventory_2_outlined,
                size: 26, color: YColor.brandDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Inventory tracking',
                      style: YFont.titleMD().copyWith(fontSize: 22)),
                  const SizedBox(height: 2),
                  Text(on ? 'On for this store' : 'Off for this store',
                      style: YFont.caption().copyWith(
                          color: on ? YColor.brand : YColor.inkMuted)),
                ],
              ),
            ),
            Switch(
              value: on,
              onChanged: (v) async {
                final err = await state.setInventoryTrackingEnabled(v);
                if (!context.mounted) return;
                if (err != null) {
                  PushToast.show(context,
                      title: 'Could not update',
                      subtitle: err,
                      leadingIcon: Icons.error_outline);
                }
              },
              activeThumbColor: YColor.brand,
            ),
          ]),
          const SizedBox(height: 20),
          const Divider(color: YColor.hairline),
          const SizedBox(height: 16),
          Text('What this does',
              style: YFont.bodyStrong().copyWith(fontSize: 14)),
          const SizedBox(height: 10),
          _trackExplainRow(Icons.check_circle_outline, 'When ON',
              'Products that have a recipe and their own "Track inventory" toggle on deduct ingredients on every sale, and stop selling when an ingredient runs out.'),
          const SizedBox(height: 10),
          _trackExplainRow(Icons.do_not_disturb_on_outlined, 'When OFF',
              'Nothing is deducted — every product sells freely regardless of stock. The per-product toggles are ignored until you switch this back on.'),
          const SizedBox(height: 10),
          _trackExplainRow(Icons.tune, 'Per product',
              'Each product also has its own "Track inventory" switch (product editor → Options). This store switch is the master that gates them all.'),
        ],
      ),
    );
  }

  Widget _trackExplainRow(IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: YColor.brandDeep),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: YFont.bodyStrong().copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: YFont.caption()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railHeader(String title, VoidCallback onAdd) {
    return Row(children: [
      Expanded(
        child: Text(title,
            style: YFont.caption().copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: YColor.inkMuted)),
      ),
      GestureDetector(
        onTap: onAdd,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add, size: 16, color: YColor.brandDeep),
        ),
      ),
    ]);
  }

  Widget _navRow({
    required String label,
    String? iconName,
    required IconData fallback,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.sm),
            border:
                Border.all(color: selected ? YColor.brand : YColor.hairline),
          ),
          child: Row(children: [
            SizedBox(
              width: 17,
              height: 17,
              child: NameIconOrEmoji(
                  name: label, iconName: iconName, fallbackIcon: fallback),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 12.5,
                      color: selected ? Colors.white : YColor.ink)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, AppState state, ProductType type,
      List<cat.Category> subs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 30,
              height: 30,
              child: NameIconOrEmoji(
                  name: type.name,
                  iconName: type.iconName,
                  fallbackIcon: Icons.label_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.name,
                      style: YFont.titleMD().copyWith(fontSize: 22)),
                  const SizedBox(height: 2),
                  Text(
                      '${subs.length} categor${subs.length == 1 ? 'y' : 'ies'}',
                      style: YFont.caption()),
                ],
              ),
            ),
            _ghostBtn(Icons.edit_outlined, 'Edit',
                () => showProductTypeEditor(context, initial: type)),
            const SizedBox(width: 8),
            _ghostBtn(Icons.delete_outline, 'Remove',
                () => _removeType(context, state, type),
                danger: true),
          ]),
          const SizedBox(height: 20),
          const Divider(color: YColor.hairline),
          const SizedBox(height: 16),
          Row(children: [
            Text('Categories in ${type.name}',
                style: YFont.titleMD().copyWith(fontSize: 16)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () =>
                  showSubTypeEditor(context, presetTypeId: type.id),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add category'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (subs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: _emptyCard(
                  icon: Icons.category_outlined,
                  title: 'No categories yet',
                  subtitle:
                      'Add a category like "Coffee" under Drinks or "Rice Meals" under Foods.',
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final cc in subs) _categoryChip(context, state, cc),
              ],
            ),
        ],
      ),
    );
  }

  /// Compact category chip — icon + name, tap to edit, × to remove (a lock for
  /// built-in ones). Same compact footprint as the Product Type rail tiles so
  /// the right pane shows many at a glance instead of a few big cards.
  Widget _categoryChip(BuildContext context, AppState state, cat.Category cc) {
    return Material(
      color: YColor.surface1,
      borderRadius: BorderRadius.circular(YRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(YRadius.md),
        onTap: () => showSubTypeEditor(context, initial: cc),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 18,
              height: 18,
              child: NameIconOrEmoji(name: cc.name, iconName: cc.iconName),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(cc.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(fontSize: 13)),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => _removeSub(context, state, cc),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded,
                    size: 15, color: YColor.inkMuted),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _ghostBtn(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final c = danger ? YColor.danger : YColor.brandDeep;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.md)),
      ),
    );
  }

  Future<void> _removeType(
      BuildContext context, AppState state, ProductType t) async {
    final ok = await showConfirm(context,
        title: 'Remove ${t.name}?',
        message:
            'Products using this type become untyped — you\'ll need to reassign them.',
        confirmLabel: 'Remove',
        danger: true,
        icon: Icons.delete_outline);
    if (!ok || !context.mounted) return;
    final err = await state.removeProductType(t.id);
    if (!context.mounted) return;
    PushToast.show(context,
        title: err == null ? 'Type removed' : 'Could not remove',
        subtitle: err ?? t.name,
        leadingIcon:
            err == null ? Icons.delete_outline : Icons.error_outline);
  }

  Future<void> _removeSub(
      BuildContext context, AppState state, cat.Category c) async {
    final ok = await showConfirm(context,
        title: 'Remove ${c.name}?',
        message:
            'Products in this category keep their Product Type but lose this grouping.',
        confirmLabel: 'Remove',
        danger: true,
        icon: Icons.delete_outline);
    if (!ok || !context.mounted) return;
    final err = await state.removeCategory(c.id);
    if (!context.mounted) return;
    PushToast.show(context,
        title: err == null ? 'Category removed' : 'Could not remove',
        subtitle: err ?? c.name,
        leadingIcon:
            err == null ? Icons.delete_outline : Icons.error_outline);
  }
}

// ───── Modifier groups tab (Size / Temperature / Strength + custom) ─────

class _ModifierGroupsTab extends StatelessWidget {
  const _ModifierGroupsTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final groups = state.modifierGroups;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Modifier groups',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        'Reusable option groups like Size, Temperature, Strength. Products link to these — rename here and every product follows.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: () => _openGroupForm(context, state, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add group'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (groups.isEmpty)
                _emptyCard(
                  icon: Icons.tune_outlined,
                  title: 'No modifier groups yet',
                  subtitle:
                      'Add a group like Size or Milk Type — its options will be available across every product.',
                )
              else
                for (final g in groups) ...[
                  _ModifierGroupCard(
                    group: g,
                    onEdit: () => _openGroupForm(context, state, g),
                    onRemove: () =>
                        _confirmRemoveGroup(context, state, g),
                  ),
                  const SizedBox(height: 14),
                ],
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openGroupForm(BuildContext context, AppState state,
      MasterModifierGroup? existing) async {
    final saved = await showDialog<MasterModifierGroup>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ModifierGroupDialog(initial: existing),
    );
    if (saved == null || !context.mounted) return;
    final err = existing == null
        ? await state.addModifierGroup(saved)
        : await state.updateModifierGroup(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: existing == null ? 'Group added' : 'Group updated',
        subtitle: saved.name,
        leadingIcon: Icons.tune_outlined);
  }

  Future<void> _confirmRemoveGroup(
      BuildContext context, AppState state, MasterModifierGroup g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${g.name}?'),
        content: Text(
            'Products will lose access to "${g.name}" options. Existing orders are unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await state.removeModifierGroup(g.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Group removed',
        subtitle: g.name,
        leadingIcon: Icons.delete_outline);
  }
}

class _ModifierGroupCard extends StatelessWidget {
  const _ModifierGroupCard({
    required this.group,
    required this.onEdit,
    required this.onRemove,
  });
  final MasterModifierGroup group;
  final VoidCallback onEdit;
  /// Null when the group is built-in (renders no delete button).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: YColor.brandTint.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: NameIconOrEmoji(
                  name: group.name,
                  iconName: group.iconName,
                  fallbackIcon: Icons.tune_outlined,
                  iconSize: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(group.name, style: YFont.bodyStrong()),
                      const SizedBox(width: 6),
                      if (group.required)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: YColor.brandTint,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'REQUIRED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: YColor.brand,
                            ),
                          ),
                        ),
                      if (group.isSystem) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: YColor.inkMuted.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'BUILT-IN',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: YColor.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ]),
                    Text(
                      '${group.options.length} option${group.options.length == 1 ? '' : 's'}',
                      style: YFont.caption(),
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                _TileMoreMenu(
                  onEdit: onEdit,
                  onRemove: onRemove!,
                )
              else
                _TileIconBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  onTap: onEdit,
                ),
            ]),
          ),
          Container(
            height: 0.5,
            color: YColor.hairline,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < group.options.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: i == group.defaultIndex
                          ? YColor.brandTint
                          : YColor.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: i == group.defaultIndex
                            ? YColor.brand
                            : YColor.hairline,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        group.options[i].name,
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 12,
                          color: i == group.defaultIndex
                              ? YColor.brandDeep
                              : YColor.ink,
                        ),
                      ),
                      if (i == group.defaultIndex) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: YColor.brandTint,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'DEFAULT',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: YColor.brand,
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModifierGroupDialog extends StatefulWidget {
  const _ModifierGroupDialog({this.initial});
  final MasterModifierGroup? initial;

  @override
  State<_ModifierGroupDialog> createState() => _ModifierGroupDialogState();
}

class _ModifierGroupDialogState extends State<_ModifierGroupDialog> {
  late final TextEditingController _name;
  String? _iconName;
  late String _emoji;
  late bool _required;
  late int _defaultIndex;
  late List<MasterOption> _options;
  final Map<String, TextEditingController> _optCtrls = {};
  final Map<String, TextEditingController> _priceCtrls = {};

  @override
  void initState() {
    super.initState();
    final g = widget.initial;
    _name = TextEditingController(text: g?.name ?? '');
    // New modifier groups default to the themed Material "tune" icon (same
    // glyph the empty-state card uses) so the picker tile matches what's
    // rendered everywhere else.
    _iconName = g?.iconName ?? (g == null ? 'tune_outlined' : null);
    _emoji = (g?.emoji.isNotEmpty == true) ? g!.emoji : '⚙';
    _required = g?.required ?? false;
    _defaultIndex = g?.defaultIndex ?? 0;
    // Preserve `priceDelta` when copying — earlier this dropped the price
    // on every edit, which is why "Medium = +₱20" never persisted.
    _options = (g?.options ?? <MasterOption>[])
        .map((o) => MasterOption(
              id: o.id,
              name: o.name,
              priceDelta: o.priceDelta,
            ))
        .toList();
  }

  TextEditingController _ctrl(MasterOption o) {
    final c = _optCtrls[o.id];
    if (c != null) return c;
    return _optCtrls[o.id] = TextEditingController(text: o.name);
  }

  TextEditingController _priceCtrl(MasterOption o) {
    final c = _priceCtrls[o.id];
    if (c != null) return c;
    final pesos = o.priceDelta.centavos / 100.0;
    return _priceCtrls[o.id] = TextEditingController(
        text: pesos == 0 ? '' : pesos.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _optCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final canSave =
        _name.text.trim().isNotEmpty && _options.isNotEmpty;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 200,
        height: size.height - 120,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null
                    ? 'Add modifier group'
                    : 'Edit modifier group',
                style: YFont.titleLG().copyWith(fontSize: 22),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ICON',
                                  style: YFont.caption().copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                    color: YColor.brandDeep,
                                  )),
                              const SizedBox(height: 6),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text,
                                fallbackIcon: Icons.tune_outlined,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Group name',
                            accessoryLabel: 'GROUP NAME',
                            hint: 'e.g., Size, Milk Type',
                            fillColor: YColor.surface2,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      value: _required,
                      onChanged: (v) => setState(() => _required = v),
                      activeThumbColor: YColor.brand,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Required',
                          style:
                              YFont.bodyStrong().copyWith(fontSize: 14)),
                      subtitle: Text(
                        'Cashiers must pick one option to add the product to the cart.',
                        style: YFont.caption(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('OPTIONS',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    if (_options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'No options yet. Add at least one (e.g., Short / Tall / Grande).',
                          style: YFont.caption(),
                        ),
                      )
                    else
                      for (var i = 0; i < _options.length; i++)
                        _buildOptionRow(i),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _options.add(MasterOption(name: ''));
                          });
                        },
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add option'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: YColor.brand,
                          side: const BorderSide(color: YColor.hairline),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(YRadius.md)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Price (₱) bumps a product\'s base price when that '
                      'option is picked — e.g. Medium "+20" charges +₱20 '
                      'on every product using this group. Leave blank or '
                      '0 for no charge.',
                      style: YFont.caption(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(widget.initial == null ? 'Add' : 'Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildOptionRow(int i) {
    final o = _options[i];
    final ctrl = _ctrl(o);
    final isDefault = i == _defaultIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 18,
            tooltip: isDefault ? 'Default option' : 'Set as default',
            onPressed: () => setState(() => _defaultIndex = i),
            icon: Icon(
              isDefault ? Icons.star : Icons.star_border,
              color: isDefault ? YColor.brand : YColor.inkMuted,
            ),
          ),
          Expanded(
            flex: 3,
            child: KeyboardAccessoryField(
              controller: ctrl,
              accessoryLabel: 'OPTION NAME',
              hint: 'e.g., Short, Tall, Hot, Iced',
              fillColor: YColor.surface2,
              borderColor: YColor.hairline,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              onChanged: (v) {
                o.name = v;
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: KeyboardAccessoryField(
              controller: _priceCtrl(o),
              accessoryLabel: 'PRICE (₱)',
              hint: '+0',
              keyboardType: TextInputType.number,
              fillColor: YColor.surface2,
              borderColor: YColor.hairline,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              formatPreview: (raw) {
                final n = double.tryParse(raw) ?? 0;
                if (n == 0) return 'no charge';
                return '+₱${n.toStringAsFixed(0)}';
              },
              onChanged: (v) {
                final pesos = double.tryParse(v) ?? 0;
                o.priceDelta = Money((pesos * 100).round());
                setState(() {});
              },
            ),
          ),
          IconButton(
            iconSize: 18,
            onPressed: () {
              setState(() {
                final removed = _options.removeAt(i);
                _optCtrls.remove(removed.id)?.dispose();
                _priceCtrls.remove(removed.id)?.dispose();
                if (_defaultIndex >= _options.length) {
                  _defaultIndex =
                      _options.isEmpty ? 0 : _options.length - 1;
                }
              });
            },
            icon: const Icon(Icons.delete_outline,
                color: YColor.inkMuted),
          ),
        ],
      ),
    );
  }

  void _save() {
    // Strip empty option names before saving. Preserve `priceDelta` so the
    // per-option price bump persists through the round-trip (this used to
    // be dropped, which made "Medium = +₱20" invisible on every save).
    final cleaned = _options
        .where((o) => o.name.trim().isNotEmpty)
        .map((o) => MasterOption(
              id: o.id,
              name: o.name.trim(),
              priceDelta: o.priceDelta,
            ))
        .toList();
    if (cleaned.isEmpty) return;
    final saved = MasterModifierGroup(
      id: widget.initial?.id,
      name: _name.text.trim(),
      emoji: _emoji,
      iconName: _iconName,
      required: _required,
      defaultIndex: _defaultIndex.clamp(0, cleaned.length - 1),
      sortOrder: widget.initial?.sortOrder ?? 0,
      options: cleaned,
    );
    Navigator.of(context).pop(saved);
  }
}

// ───── Add-ons tab (full CRUD) ─────

class _AddOnsTab extends StatelessWidget {
  const _AddOnsTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final addOns = state.addOns;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Global add-ons',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        '${addOns.length} extras the cashier can attach to any product at order time.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: () => _openForm(context, state, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add add-on'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (addOns.isEmpty)
                _emptyCard(
                  icon: Icons.add_circle_outline,
                  title: 'No add-ons yet',
                  subtitle:
                      'Add things like "Extra shot", "Whipped cream", "Oat milk swap" — your cashiers can stack them onto any product at order time.',
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: YColor.surface1,
                    borderRadius: BorderRadius.circular(YRadius.lg),
                    border: Border.all(
                        color: YColor.hairline.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < addOns.length; i++) ...[
                        _AddOnRow(
                          addOn: addOns[i],
                          inventory: state.inventory,
                          onEdit: () =>
                              _openForm(context, state, addOns[i]),
                          onRemove: () =>
                              _confirmRemove(context, state, addOns[i]),
                        ),
                        if (i != addOns.length - 1)
                          Container(
                            height: 0.5,
                            color: YColor.hairline,
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16),
                          ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
      BuildContext context, AppState state, AddOn? existing) async {
    final saved = await showDialog<AddOn>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddOnFormDialog(
        initial: existing,
        inventory: state.inventory,
        categories: state.categories,
      ),
    );
    if (saved == null || !context.mounted) return;
    final err = existing == null
        ? await state.addAddOn(saved)
        : await state.updateAddOn(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: existing == null ? 'Add-on added' : 'Add-on updated',
      subtitle: existing == null
          ? '${saved.name} · +${saved.priceDelta.formatted}'
          : saved.name,
      leadingEmoji: saved.emoji,
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState state, AddOn addOn) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${addOn.name}?'),
        content: const Text(
            'This add-on will no longer appear at order time. Existing orders are unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await state.removeAddOn(addOn.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: 'Add-on removed',
      subtitle: addOn.name,
      leadingIcon: Icons.delete_outline,
    );
  }
}

class _AddOnRow extends StatelessWidget {
  const _AddOnRow({
    required this.addOn,
    required this.inventory,
    required this.onEdit,
    required this.onRemove,
  });
  final AddOn addOn;
  final List<InventoryItem> inventory;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ingredients = addOn.recipe
        .map((l) {
          final it =
              inventory.where((i) => i.id == l.inventoryItemId).firstOrNull;
          if (it == null) return null;
          return '${l.quantity.toStringAsFixed(0)}${it.displayUnit} ${it.name}';
        })
        .whereType<String>()
        .join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: NameIconOrEmoji(
                name: addOn.name,
                iconName: addOn.iconName,
                iconSize: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(addOn.name, style: YFont.bodyStrong()),
                    const SizedBox(width: 8),
                    if (addOn.maxQuantity > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: YColor.surface3,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'max ${addOn.maxQuantity}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: YColor.inkMuted,
                          ),
                        ),
                      ),
                  ]),
                  if (ingredients.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(ingredients, style: YFont.caption()),
                    ),
                  if (ingredients.isEmpty)
                    Text('No inventory deduction',
                        style: YFont.caption()),
                  const SizedBox(height: 6),
                  // Applicable categories
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      if (addOn.applicableCategoryIds.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: YColor.brandTint
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'All products',
                            style: YFont.caption().copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: YColor.brandDeep,
                            ),
                          ),
                        )
                      else
                        for (final catId in addOn.applicableCategoryIds)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: YColor.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: YColor.hairline
                                      .withValues(alpha: 0.6)),
                            ),
                            child: Text(
                              context
                                      .read<AppState>()
                                      .categories
                                      .where((c) => c.id == catId)
                                      .firstOrNull
                                      ?.name ??
                                  'Removed',
                              style: YFont.caption().copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: YColor.brandDeep,
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              addOn.priceDelta.centavos > 0
                  ? '+${addOn.priceDelta.formatted}'
                  : 'Free',
              style: YFont.bodyStrong().copyWith(color: YColor.brand),
            ),
            IconButton(
              iconSize: 18,
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline,
                  color: YColor.inkMuted),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───── Inventory categories tab ─────────────────────────────────────
// Mirrors _CategoriesTab but targets the inventory_categories table
// (Fresh Vegetables, Books, Placeholder, etc.). Same grid + icon picker
// pattern so owners learn it once and reuse the muscle memory.

class _InventoryCategoriesTab extends StatelessWidget {
  const _InventoryCategoriesTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final cats = state.inventoryCategories;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inventory categories',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        'Buckets for your stock items — Fresh Vegetables, '
                        'Books, Packaging. Each inventory item picks one.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: () => _openForm(context, state, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add category'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (cats.isEmpty)
                _emptyCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'No inventory categories yet',
                  subtitle:
                      'Tap "Add category" to create one — e.g. "Coffee & Tea", '
                      '"Dairy", "Packaging", "Books".',
                )
              else
                LayoutBuilder(builder: (ctx, c) {
                  final cols = c.maxWidth > 900
                      ? 4
                      : c.maxWidth > 640
                          ? 3
                          : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cats.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.9,
                    ),
                    itemBuilder: (_, i) {
                      final c = cats[i];
                      final itemCount = state.inventory
                          .where((it) => it.categoryId == c.id)
                          .length;
                      return _MaintGridTile(
                        icon: NameIconOrEmoji(
                          name: c.name,
                          iconName: c.iconName,
                        ),
                        label: c.name,
                        subtitle:
                            '$itemCount item${itemCount == 1 ? "" : "s"} · order ${c.sortOrder}',
                        badge: c.isSystem ? 'BUILT-IN' : null,
                        onTap: () => _openForm(context, state, c),
                        onRemove: () =>
                            _confirmRemove(context, state, c),
                      );
                    },
                  );
                }),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, AppState state,
      InventoryCategory? existing) async {
    final saved = await showDialog<InventoryCategory>(
      context: context,
      builder: (_) => _InventoryCategoryDialog(initial: existing),
    );
    if (saved == null || !context.mounted) return;
    final err = existing == null
        ? await state.addInventoryCategory(saved)
        : await state.updateInventoryCategory(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: existing == null
            ? 'Inventory category added'
            : 'Inventory category updated',
        subtitle: saved.name,
        leadingIcon: Icons.inventory_2_outlined);
  }

  Future<void> _confirmRemove(BuildContext context, AppState state,
      InventoryCategory category) async {
    final inUse = state.inventory
        .where((it) => it.categoryId == category.id)
        .length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove "${category.name}"?'),
        content: Text(inUse > 0
            ? '$inUse inventory item${inUse == 1 ? "" : "s"} reference '
                'this category. They\'ll keep their stored category name '
                'as a display fallback, but you\'ll want to re-categorise them.'
            : 'No items use this category — safe to delete.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await state.removeInventoryCategory(category.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Inventory category removed',
        subtitle: category.name,
        leadingIcon: Icons.delete_outline);
  }
}

class _InventoryCategoryDialog extends StatefulWidget {
  const _InventoryCategoryDialog({this.initial});
  final InventoryCategory? initial;

  @override
  State<_InventoryCategoryDialog> createState() =>
      _InventoryCategoryDialogState();
}

class _InventoryCategoryDialogState extends State<_InventoryCategoryDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  String? _iconName;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial?.name ?? '');
    _iconName = widget.initial?.iconName ??
        (widget.initial == null ? 'label_outlined' : null);
    _sortOrder = TextEditingController(
        text: (widget.initial?.sortOrder ?? 100).toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    final saved = InventoryCategory(
      id: widget.initial?.id ?? '00000000-0000-0000-0000-000000000000',
      name: _name.text.trim(),
      iconName: _iconName,
      sortOrder: int.tryParse(_sortOrder.text) ?? 100,
      isSystem: widget.initial?.isSystem ?? false,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                child: Row(children: [
                  Text(
                    widget.initial == null
                        ? 'Add Inventory Category'
                        : 'Edit Inventory Category',
                    style: YFont.titleLG().copyWith(fontSize: 20),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Container(height: 0.5, color: YColor.hairline),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4, bottom: 6),
                                child:
                                    Text('Icon', style: YFont.caption()),
                              ),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Name',
                            accessoryLabel: 'NAME',
                            hint:
                                'e.g. Books, Coffee & Tea, Packaging',
                            fillColor: YColor.surface1,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    KeyboardAccessoryField(
                      controller: _sortOrder,
                      label: 'Order',
                      accessoryLabel: 'ORDER',
                      hint: '100',
                      keyboardType: TextInputType.number,
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: YColor.hairline),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(YRadius.md)),
                    ),
                    child: Text(widget.initial == null
                        ? 'Add category'
                        : 'Save changes'),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Product Type editor — add when [initial] is null, else edit — and
/// persists via AppState (the same path Maintenance uses, so edits stay in sync
/// everywhere). Reusable from the Sell "arrange mode".
Future<void> showProductTypeEditor(BuildContext context,
    {ProductType? initial}) async {
  final state = context.read<AppState>();
  final saved = await showDialog<ProductType>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProductTypeDialog(initial: initial),
  );
  if (saved == null || !context.mounted) return;
  final err = initial == null
      ? await state.addProductType(saved)
      : await state.updateProductType(saved);
  if (!context.mounted) return;
  if (err != null) {
    PushToast.show(context,
        title: 'Could not save',
        subtitle: err,
        leadingIcon: Icons.error_outline);
    return;
  }
  PushToast.show(context,
      title: initial == null ? 'Type added' : 'Type updated',
      subtitle: saved.name,
      leadingIcon: Icons.check_circle_outline);
}

/// Opens the Sub-type editor — add when [initial] is null (defaulting its
/// Product Type to [presetTypeId]), else edit. Persists via AppState. Reusable
/// from the Sell "arrange mode".
Future<void> showSubTypeEditor(BuildContext context,
    {cat.Category? initial, String? presetTypeId}) async {
  final state = context.read<AppState>();
  final saved = await showDialog<cat.Category>(
    context: context,
    builder: (_) =>
        _CategoryDialog(initial: initial, presetTypeId: presetTypeId),
  );
  if (saved == null || !context.mounted) return;
  final err = initial == null
      ? await state.addCategory(
          name: saved.name,
          emoji: saved.emoji,
          iconName: saved.iconName,
          sortOrder: saved.sortOrder,
          typeId: saved.typeId,
          separateSales: saved.separateSales,
        )
      : await state.updateCategory(saved);
  if (!context.mounted) return;
  if (err != null) {
    PushToast.show(context,
        title: 'Could not save',
        subtitle: err,
        leadingIcon: Icons.error_outline);
    return;
  }
  PushToast.show(context,
      title: initial == null ? 'Category added' : 'Category updated',
      subtitle: saved.name,
      leadingIcon: Icons.check_circle_outline);
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.initial, this.presetTypeId});
  final cat.Category? initial;
  /// For a NEW sub-type, pre-selects this Product Type (used by Sell's
  /// "arrange mode" + box, which knows the current type).
  final String? presetTypeId;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sortOrder;
  String? _iconName;
  String? _typeId;
  late String _emoji;
  late bool _separateSales;

  @override
  void initState() {
    super.initState();
    _separateSales = widget.initial?.separateSales ?? false;
    _name = TextEditingController(text: widget.initial?.name ?? '');
    // New categories default to the themed Material "label" icon so the
    // picker tile and the resulting card both match the rest of the UI
    // instead of falling back to the 🏷 emoji.
    _iconName = widget.initial?.iconName ??
        (widget.initial == null ? 'label_outlined' : null);
    _emoji = widget.initial?.emoji.isNotEmpty == true
        ? widget.initial!.emoji
        : '🏷';
    _sortOrder = TextEditingController(
        text: (widget.initial?.sortOrder ?? 100).toString());
    _typeId = widget.initial?.typeId ?? widget.presetTypeId;
  }

  @override
  void dispose() {
    _name.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        // No fixed height — the dialog sizes to its contents so a 3-field
        // form doesn't render a giant empty rectangle below the inputs.
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null
                    ? 'Add category'
                    : 'Edit category',
                style: YFont.titleLG().copyWith(fontSize: 22),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ICON',
                                style: YFont.caption().copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                  color: YColor.brandDeep,
                                )),
                            const SizedBox(height: 6),
                            IconPickerField(
                              value: _iconName,
                              fallbackName: _name.text,
                              onChanged: (key) =>
                                  setState(() => _iconName = key),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _name,
                          label: 'Name',
                          accessoryLabel: 'NAME',
                          hint: 'e.g., Smoothies, Brunch, Books',
                          fillColor: YColor.surface2,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: KeyboardAccessoryField(
                          controller: _sortOrder,
                          label: 'Order',
                          accessoryLabel: 'ORDER',
                          hint: '100',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface2,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 12),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // The product type is already known — from the type you were
                  // in when adding, or the category's existing type when
                  // editing — so just show it. The picker only appears for the
                  // rare untyped ("Other") case so you can still assign one.
                  if (_typeId != null)
                    _presetTypeRow(context)
                  else
                    _typePicker(context),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _separateSales,
                    onChanged: (v) => setState(() => _separateSales = v),
                    activeThumbColor: YColor.brand,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Separate in Sales reports',
                        style: YFont.bodyStrong().copyWith(fontSize: 14)),
                    subtitle: Text(
                      'Settle this category as its own line in Reports → Sales '
                      '(e.g. consigned Books). Overrides the type\'s setting.',
                      style: YFont.caption(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canSave
                    ? () => Navigator.pop(
                          context,
                          cat.Category(
                            // For new categories, the id is a placeholder —
                            // AppState.addCategory ignores it and the DB
                            // generates the real uuid. For edits, we keep
                            // the existing id so updateCategory targets it.
                            id: widget.initial?.id ?? '',
                            name: _name.text.trim(),
                            emoji: _emoji,
                            iconName: _iconName,
                            sortOrder:
                                int.tryParse(_sortOrder.text) ?? 100,
                            typeId: _typeId,
                            separateSales: _separateSales,
                          ),
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(widget.initial == null ? 'Add' : 'Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Read-only Product Type confirmation — shown when adding a category from a
  /// type that's already chosen (the Maintenance rail or the Sell page), so the
  /// owner doesn't pick it twice.
  Widget _presetTypeRow(BuildContext context) {
    final type = context.read<AppState>().productTypeById(_typeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRODUCT TYPE',
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            )),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(children: [
            SizedBox(
              width: 18,
              height: 18,
              child: NameIconOrEmoji(
                  name: type?.name ?? '',
                  iconName: type?.iconName,
                  fallbackIcon: Icons.label_outline),
            ),
            const SizedBox(width: 8),
            Text(type?.name ?? 'Selected type',
                style: YFont.bodyStrong().copyWith(fontSize: 14)),
          ]),
        ),
      ],
    );
  }

  /// Picks which Product Type this sub-type belongs to. Optional — tapping the
  /// selected chip again clears it (the sub-type then lives under "Other" on
  /// the Sell page). Reads the live product-type list from AppState.
  Widget _typePicker(BuildContext context) {
    final types = context.watch<AppState>().productTypes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRODUCT TYPE',
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            )),
        const SizedBox(height: 4),
        Text(
          'The top-level group this category sits under on the Sell page. '
          'Optional — leave it off to keep it under "Other".',
          style: YFont.caption().copyWith(color: YColor.inkMuted),
        ),
        const SizedBox(height: 10),
        if (types.isEmpty)
          Text('No product types yet — add one in the Product types tab.',
              style: YFont.caption().copyWith(color: YColor.inkMuted))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in types) _typeChip(t.id, t.name, t.iconName)],
          ),
      ],
    );
  }

  Widget _typeChip(String id, String name, String? iconName) {
    final selected = _typeId == id;
    final icon = resolveIcon(iconName: iconName, name: name);
    return GestureDetector(
      onTap: () => setState(() => _typeId = selected ? null : id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? YColor.brand : YColor.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? YColor.brand : YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 14, color: selected ? Colors.white : YColor.brandDeep),
          const SizedBox(width: 6),
          Text(name,
              style: YFont.bodyStrong().copyWith(
                  fontSize: 13, color: selected ? Colors.white : YColor.ink)),
        ]),
      ),
    );
  }
}

Widget _emptyCard({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Container(
    padding: const EdgeInsets.all(36),
    decoration: BoxDecoration(
      color: YColor.surface1,
      borderRadius: BorderRadius.circular(YRadius.lg),
      border: Border.all(color: YColor.hairline),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: YColor.inkMuted),
        const SizedBox(height: 8),
        Text(title, style: YFont.bodyStrong()),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: YFont.caption(),
        ),
      ],
    ),
  );
}


// ───── Roles tab + dialog ──────────────────────────────────────────────

/// Permission catalog shown in the Role dialog. Each row maps a route key
/// (matches `AppRoute.name`) to the label and outlined Material icon shown
/// in the picker grid. Keep grouped by section so the picker reads top-down
/// the same way the bottom nav does.
class _RoutePerm {
  final String key;
  final String label;
  final IconData icon;
  const _RoutePerm(this.key, this.label, this.icon);
}

const List<_RoutePerm> _kRoutePerms = [
  _RoutePerm('dashboard', 'Home', Icons.space_dashboard_outlined),
  _RoutePerm('sell', 'Sell', Icons.storefront_outlined),
  _RoutePerm('orders', 'Orders', Icons.receipt_long_outlined),
  _RoutePerm('bookings', 'Bookings', Icons.event_available_outlined),
  _RoutePerm('sessions', 'Sessions', Icons.timer_outlined),
  _RoutePerm('members', 'Members', Icons.card_membership_outlined),
  _RoutePerm('products', 'Products', Icons.coffee_outlined),
  _RoutePerm('inventory', 'Stock', Icons.inventory_2_outlined),
  _RoutePerm('employees', 'Staff', Icons.person_outline),
  _RoutePerm('payroll', 'Payroll', Icons.account_balance_wallet_outlined),
  _RoutePerm('reports', 'Reports', Icons.insights_outlined),
  _RoutePerm('maintenance', 'Maintenance', Icons.tune_outlined),
  _RoutePerm('settings', 'Settings', Icons.settings_outlined),
  // Capability (not a route): lets the holder switch the active branch from
  // the header. Owner always has it; off by default for every other role.
  _RoutePerm('switch_branch', 'Switch branch', Icons.location_city_outlined),
];

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final roles = state.employeeRoles;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Roles',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        'Define what each role can access. Cashier-style roles also require a PIN.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: () => _openRoleForm(context, state, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add role'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (roles.isEmpty)
                _emptyCard(
                  icon: Icons.badge_outlined,
                  title: 'No roles yet',
                  subtitle:
                      'Add a role to control which screens an employee can see.',
                )
              else
                for (final r in roles) ...[
                  _RoleCard(
                    role: r,
                    onEdit: () => _openRoleForm(context, state, r),
                    onRemove: () =>
                        _confirmRemoveRole(context, state, r),
                  ),
                  const SizedBox(height: 14),
                ],
              const SizedBox(height: 14),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRoleForm(
      BuildContext context, AppState state, EmployeeRole? existing) async {
    final saved = await showDialog<EmployeeRole>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoleDialog(initial: existing),
    );
    if (saved == null || !context.mounted) return;
    final err = existing == null
        ? await state.addEmployeeRole(saved)
        : await state.updateEmployeeRole(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: existing == null ? 'Role added' : 'Role updated',
        subtitle: saved.name,
        leadingIcon: Icons.badge_outlined);
  }

  Future<void> _confirmRemoveRole(
      BuildContext context, AppState state, EmployeeRole r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${r.name}?'),
        content: Text(
            'Employees with this role will lose their permissions until you assign them a new one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await state.removeEmployeeRole(r.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Role removed',
        subtitle: r.name,
        leadingIcon: Icons.delete_outline);
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.onEdit,
    required this.onRemove,
  });
  final EmployeeRole role;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final perms = role.permissions;
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: NameIconOrEmoji(
            name: role.name,
            iconName: role.iconName,
            fallbackIcon: Icons.badge_outlined,
            iconSize: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(role.name,
                    style: YFont.bodyStrong().copyWith(fontSize: 15)),
                const SizedBox(width: 8),
                if (role.isSystem) _pill('BUILT-IN', YColor.inkMuted),
                if (role.requiresPin) ...[
                  const SizedBox(width: 6),
                  _pill('PIN', YColor.brand),
                ],
              ]),
              const SizedBox(height: 6),
              if (perms.isEmpty)
                Text('No screens assigned.',
                    style: YFont.caption().copyWith(color: YColor.danger))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in _kRoutePerms.where((p) => perms.contains(p.key)))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: YColor.surface2,
                          borderRadius: BorderRadius.circular(YRadius.sm),
                          border: Border.all(color: YColor.hairline),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(p.icon, size: 12, color: YColor.brandDeep),
                          const SizedBox(width: 4),
                          Text(p.label,
                              style: YFont.caption().copyWith(fontSize: 11)),
                        ]),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _TileMoreMenu(
          onEdit: onEdit,
          onRemove: onRemove,
        ),
      ]),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: YFont.caption().copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: color,
          ),
        ),
      );
}

class _RoleDialog extends StatefulWidget {
  const _RoleDialog({this.initial});
  final EmployeeRole? initial;

  @override
  State<_RoleDialog> createState() => _RoleDialogState();
}

class _RoleDialogState extends State<_RoleDialog> {
  late final TextEditingController _name;
  String? _iconName;
  late bool _requiresPin;
  late Set<String> _permissions;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name = TextEditingController(text: r?.name ?? '');
    _iconName = r?.iconName ?? (r == null ? 'badge_outlined' : null);
    _requiresPin = r?.requiresPin ?? false;
    _permissions = {...(r?.permissions ?? const <String>{})};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _togglePerm(String key) {
    setState(() {
      if (_permissions.contains(key)) {
        _permissions.remove(key);
      } else {
        _permissions.add(key);
      }
    });
  }

  void _save() {
    final saved = EmployeeRole(
      id: widget.initial?.id ?? '',
      name: _name.text.trim(),
      iconName: _iconName,
      permissions: {..._permissions},
      requiresPin: _requiresPin,
      isSystem: widget.initial?.isSystem ?? false,
      sortOrder: widget.initial?.sortOrder ?? 1000,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final canSave = _name.text.trim().isNotEmpty;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 200,
        height: size.height - 120,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null ? 'Add role' : 'Edit role',
                style: YFont.titleLG().copyWith(fontSize: 22),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 84,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ICON',
                                  style: YFont.caption().copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                    color: YColor.brandDeep,
                                  )),
                              const SizedBox(height: 6),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text,
                                fallbackIcon: Icons.badge_outlined,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Role name',
                            accessoryLabel: 'ROLE NAME',
                            hint: 'e.g., Barista, Manager',
                            fillColor: YColor.surface2,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      value: _requiresPin,
                      onChanged: (v) => setState(() => _requiresPin = v),
                      activeThumbColor: YColor.brand,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Requires PIN',
                          style:
                              YFont.bodyStrong().copyWith(fontSize: 14)),
                      subtitle: Text(
                        'Employees with this role enter a 4–8 digit PIN to ring up sales.',
                        style: YFont.caption(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('SCREENS THIS ROLE CAN ACCESS',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _kRoutePerms.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.6,
                      ),
                      itemBuilder: (_, i) {
                        final p = _kRoutePerms[i];
                        final on = _permissions.contains(p.key);
                        return InkWell(
                          borderRadius: BorderRadius.circular(YRadius.md),
                          onTap: () => _togglePerm(p.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: on
                                  ? YColor.brand.withValues(alpha: 0.08)
                                  : YColor.surface2,
                              borderRadius:
                                  BorderRadius.circular(YRadius.md),
                              border: Border.all(
                                color:
                                    on ? YColor.brand : YColor.hairline,
                                width: on ? 1.4 : 1,
                              ),
                            ),
                            child: Row(children: [
                              Icon(p.icon,
                                  size: 18,
                                  color: on
                                      ? YColor.brand
                                      : YColor.brandDeep),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(p.label,
                                    style: YFont.bodyStrong()
                                        .copyWith(fontSize: 13)),
                              ),
                              Icon(
                                on
                                    ? Icons.check_box_outlined
                                    : Icons.check_box_outline_blank,
                                size: 18,
                                color: on
                                    ? YColor.brand
                                    : YColor.inkMuted,
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(widget.initial == null ? 'Add' : 'Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ProductTypeDialog extends StatefulWidget {
  const _ProductTypeDialog({this.initial});
  final ProductType? initial;

  @override
  State<_ProductTypeDialog> createState() => _ProductTypeDialogState();
}

class _ProductTypeDialogState extends State<_ProductTypeDialog> {
  late final TextEditingController _name;
  String? _iconName;
  late bool _separateSales;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name ?? '');
    _iconName = t?.iconName ?? (t == null ? 'label_outlined' : null);
    _separateSales = t?.separateSales ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(ProductType(
      id: widget.initial?.id ?? '',
      name: _name.text.trim(),
      iconName: _iconName,
      // Behaviour moved to per-product; preserve existing values (default on)
      // so the now-unused columns stay valid.
      supportsModifiers: widget.initial?.supportsModifiers ?? true,
      deductsStock: widget.initial?.deductsStock ?? true,
      isSystem: widget.initial?.isSystem ?? false,
      sortOrder: widget.initial?.sortOrder ?? 1000,
      separateSales: _separateSales,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null ? 'Add product type' : 'Edit product type',
                style: YFont.titleLG().copyWith(fontSize: 22),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ICON',
                                  style: YFont.caption().copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                    color: YColor.brandDeep,
                                  )),
                              const SizedBox(height: 6),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text,
                                fallbackIcon: Icons.label_outline,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Type name',
                            accessoryLabel: 'TYPE NAME',
                            hint: 'e.g., Drink, Book, Service',
                            fillColor: YColor.surface2,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _separateSales,
                      onChanged: (v) => setState(() => _separateSales = v),
                      activeThumbColor: YColor.brand,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Separate in Sales reports',
                          style: YFont.bodyStrong().copyWith(fontSize: 14)),
                      subtitle: Text(
                        'Settle this type as its own line in Reports → Sales '
                        '(e.g. consigned goods), instead of merging into '
                        'General.',
                        style: YFont.caption(),
                      ),
                    ),
                  ],
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(widget.initial == null ? 'Add' : 'Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Shared compact grid tile used by Categories + Product Types tabs.
/// Visual: icon top-left, BUILT-IN badge top-right (optional), label below
/// + one-line subtitle, soft drop shadow for a floating feel. The whole
/// tile is tappable (edit); a tiny X in the top-right anchors the delete.
class _MaintGridTile extends StatelessWidget {
  const _MaintGridTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.onRemove,
    this.badge,
  });

  final Widget icon;
  final String label;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(YRadius.lg),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YRadius.lg),
              border: Border.all(
                  color: YColor.hairline.withValues(alpha: 0.4)),
            ),
            child: Stack(children: [
              Padding(
                // Right padding reserves room (~44px) for the absolutely
                // positioned more-menu in the top-right corner so long
                // names like "Dry, Wet & Canned" wrap to a second line
                // instead of disappearing under the three-dot button.
                padding: const EdgeInsets.fromLTRB(12, 10, 44, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: YColor.brandTint.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: icon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: YFont.bodyStrong()
                                  .copyWith(fontSize: 14, letterSpacing: -0.2)),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  YFont.caption().copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: YColor.inkMuted.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(badge!,
                        style: YFont.caption().copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: YColor.inkMuted,
                        )),
                  ),
                ),
              // Three-dot more menu in the top-right. Tile tap already
              // opens edit, so the menu surfaces labelled secondary
              // actions (Edit + Remove) — clearer than guessing what
              // a pen / trash icon means, and extensible later
              // (Duplicate, Move, etc.).
              if (onRemove != null)
                Positioned(
                  right: 6,
                  top: 6,
                  child: _TileMoreMenu(
                    onEdit: onTap,
                    onRemove: onRemove!,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three-dot popup menu used in the top-right of grid tiles. Replaces
/// the old pen + trash icon pair — tile tap still edits, this menu adds
/// labelled actions (clearer than icons) and leaves room to grow.
class _TileMoreMenu extends StatelessWidget {
  const _TileMoreMenu({required this.onEdit, this.onRemove});

  final VoidCallback onEdit;
  // Null for system rows that can be edited but not removed — the
  // Remove entry simply isn't rendered in those cases.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        tooltip: 'More',
        position: PopupMenuPosition.under,
        elevation: 8,
        offset: const Offset(0, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YRadius.md),
          side: const BorderSide(color: YColor.hairline),
        ),
        color: YColor.surface1,
        icon: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.surface1.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            border: Border.all(
                color: YColor.hairline.withValues(alpha: 0.6)),
          ),
          child: const Icon(Icons.more_horiz,
              size: 16, color: YColor.inkMuted),
        ),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            value: 'edit',
            height: 40,
            child: Row(children: [
              const Icon(Icons.edit_outlined,
                  size: 16, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Text('Edit',
                  style: YFont.bodyStrong().copyWith(fontSize: 13)),
            ]),
          ),
          if (onRemove != null) const PopupMenuDivider(height: 1),
          if (onRemove != null)
            PopupMenuItem<String>(
              value: 'remove',
              height: 40,
              child: Row(children: [
                const Icon(Icons.delete_outline,
                    size: 16, color: YColor.danger),
                const SizedBox(width: 10),
                Text('Remove',
                    style: YFont.bodyStrong()
                        .copyWith(fontSize: 13, color: YColor.danger)),
              ]),
            ),
        ],
        onSelected: (v) {
          switch (v) {
            case 'edit':
              onEdit();
              break;
            case 'remove':
              onRemove?.call();
              break;
          }
        },
      ),
    );
  }
}

/// Compact 28×28 icon button used in the top-right of grid tiles for edit
/// and delete affordances. The InkWell sits above the tile's whole-tile
/// InkWell so taps register on these buttons even though they overlap.
class _TileIconBtn extends StatelessWidget {
  const _TileIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(icon, size: 15, color: YColor.inkMuted),
            ),
          ),
        ),
      ),
    );
  }
}

