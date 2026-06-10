import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/stores/members_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart'
    show iconFromKey, IconPickerField;
import '../../design_system/spacing.dart';
import '../../design_system/themed_dropdown.dart';
import '../../design_system/typography.dart';
import '../../models/member.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// Modal sheet that lists every plan template the owner has set up
/// and lets them add / edit / remove. Sits behind the "Manage plans"
/// button on the Members page header.
class PlansManagerSheet extends StatelessWidget {
  const PlansManagerSheet({super.key});

  /// Pretty accent swatches shared with bookable resources so the
  /// owner can pick one palette and have it apply everywhere.
  static const palette = <(String, String, Color)>[
    ('Brand', '#B07C4F', Color(0xFFB07C4F)),
    ('Olive', '#7C8F65', Color(0xFF7C8F65)),
    ('Slate', '#6E7A8A', Color(0xFF6E7A8A)),
    ('Claret', '#A04545', Color(0xFFA04545)),
    ('Forest', '#5C8A6B', Color(0xFF5C8A6B)),
    ('Navy', '#3D5A7A', Color(0xFF3D5A7A)),
    ('Mustard', '#C29A36', Color(0xFFC29A36)),
    ('Plum', '#8A5A8A', Color(0xFF8A5A8A)),
  ];

  static Color hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return YColor.brand;
    final clean = hex.replaceFirst('#', '');
    final v = int.tryParse('FF$clean', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MembersStore>();
    final plans = state.memberPlans;
    final size = MediaQuery.sizeOf(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        top: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: size.height * 0.85),
        child: Container(
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: YColor.brandTint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune,
                        color: YColor.brandDeep, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Plan templates',
                            style: YFont.titleLG().copyWith(fontSize: 20)),
                        const SizedBox(height: 2),
                        Text(
                          'Set up these once — every new member picks from this list.',
                          style: YFont.caption(),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ]),
              ),
              Container(height: 0.5, color: YColor.hairline),
              Flexible(
                child: plans.isEmpty
                    ? _empty(context)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        itemCount: plans.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _PlanRow(plan: plans[i]),
                      ),
              ),
              Container(height: 0.5, color: YColor.hairline),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _openForm(context, null),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add plan template'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: YColor.brandTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_membership_outlined,
                size: 32, color: YColor.brandDeep),
          ),
          const SizedBox(height: 14),
          Text('No plan templates yet', style: YFont.bodyStrong()),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'A template defines what you sell to members — e.g. '
              '"Resident Monthly ₱2500/30 days" or "10-Hour Pack '
              '₱800/60 days". Add one to start signing members up.',
              textAlign: TextAlign.center,
              style: YFont.caption(),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _openForm(
      BuildContext context, MemberPlan? existing) async {
    final saved = await showDialog<MemberPlan>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PlanFormDialog(existing: existing),
    );
    if (saved == null || !context.mounted) return;
    final state = context.read<MembersStore>();
    final err = existing == null
        ? await state.addMemberPlan(saved)
        : await state.updateMemberPlan(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save plan',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: existing == null ? 'Plan added' : 'Plan updated',
        subtitle: saved.name,
        leadingIcon: Icons.check_circle_outline);
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan});
  final MemberPlan plan;

  @override
  Widget build(BuildContext context) {
    final accent = PlansManagerSheet.hexToColor(plan.color);
    final icon = iconFromKey(plan.iconName) ?? plan.kind.icon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PlansManagerSheet._openForm(context, plan),
        borderRadius: BorderRadius.circular(YRadius.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(plan.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YFont.bodyStrong().copyWith(fontSize: 14)),
                    ),
                    if (!plan.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: YColor.inkMuted.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('HIDDEN',
                            style: YFont.caption().copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: YColor.inkMuted,
                            )),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(plan.summary,
                      style: YFont.caption().copyWith(fontSize: 11)),
                  if (plan.perks.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final p in plan.perks)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(p,
                                style: YFont.caption().copyWith(
                                  fontSize: 10,
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove',
              onPressed: () => _confirmRemove(context, plan),
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: YColor.inkMuted),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, MemberPlan plan) async {
    final state = context.read<MembersStore>();
    final inUse = state.members.where((m) => m.planId == plan.id).length;
    final ok = await showConfirm(
      context,
      title: 'Remove "${plan.name}"?',
      message: inUse == 0
          ? 'This plan template will be deleted. No members are '
              'currently assigned to it.'
          : '$inUse member${inUse == 1 ? "" : "s"} currently on this '
              'plan will be marked "No plan" — you can reassign them '
              'after.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !context.mounted) return;
    final err = await state.removeMemberPlan(plan.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Plan removed',
        subtitle: plan.name,
        leadingIcon: Icons.delete_outline);
  }
}

class _PlanFormDialog extends StatefulWidget {
  const _PlanFormDialog({this.existing});
  final MemberPlan? existing;

  @override
  State<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends State<_PlanFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _units;
  late final TextEditingController _perk;
  late final TextEditingController _sort;

  MemberPlanKind _kind = MemberPlanKind.monthly;
  String _color = '#B07C4F';
  String? _iconName;
  bool _isActive = true;
  List<String> _perks = const [];

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _price = TextEditingController(
        text: p == null ? '' : p.pricePesos.toStringAsFixed(0));
    _duration = TextEditingController(
        text: (p?.durationDays ?? 30).toString());
    _units = TextEditingController(
        text: p?.includedUnits?.toString() ?? '');
    _perk = TextEditingController();
    _sort = TextEditingController(text: (p?.sortOrder ?? 100).toString());
    _kind = p?.kind ?? MemberPlanKind.monthly;
    _color = p?.color ?? '#B07C4F';
    _iconName = p?.iconName;
    _isActive = p?.isActive ?? true;
    _perks = [...(p?.perks ?? const [])];
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _duration.dispose();
    _units.dispose();
    _perk.dispose();
    _sort.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    final priceRaw = double.tryParse(_price.text) ?? 0;
    final dur = int.tryParse(_duration.text) ?? 30;
    final units = int.tryParse(_units.text);
    final saved = MemberPlan(
      id: widget.existing?.id ?? '00000000-0000-0000-0000-000000000000',
      name: _name.text.trim(),
      kind: _kind,
      priceCents: (priceRaw * 100).round(),
      durationDays: dur < 1 ? 1 : dur,
      includedUnits:
          _kind == MemberPlanKind.monthly ? null : (units == null || units <= 0 ? null : units),
      perks: List.unmodifiable(_perks),
      color: _color,
      iconName: _iconName,
      sortOrder: int.tryParse(_sort.text) ?? 100,
      isActive: _isActive,
    );
    Navigator.of(context).pop(saved);
  }

  void _addPerk() {
    final t = _perk.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _perks = [..._perks, t];
      _perk.clear();
    });
  }

  /// Friendly hint for the "included" field — switches based on the
  /// chosen kind so the owner never has to guess what to type.
  String get _unitsLabel => switch (_kind) {
        MemberPlanKind.monthly => 'Not used for monthly plans',
        MemberPlanKind.hours =>
          'Total minutes included (e.g. 600 for 10 hours)',
        MemberPlanKind.passes =>
          'Total passes included (e.g. 5 day-passes)',
      };

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(children: [
                Text(
                  widget.existing == null
                      ? 'Add plan template'
                      : 'Edit plan template',
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('KIND',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final k in MemberPlanKind.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _kindTile(k),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                                fallbackName: _name.text.isEmpty
                                    ? _kind.label
                                    : _name.text,
                                fallbackIcon: _kind.icon,
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
                            label: 'Plan name',
                            accessoryLabel: 'NAME',
                            hint:
                                'e.g. Resident Monthly, 10-Hour Pack',
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
                    Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _price,
                          label: 'Price (₱)',
                          accessoryLabel: 'PRICE',
                          hint: '0',
                          keyboardType: TextInputType.number,
                          formatPreview: (raw) {
                            final n = double.tryParse(raw) ?? 0;
                            return '₱${n.toStringAsFixed(0)}';
                          },
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _duration,
                          label: 'Lasts (days)',
                          accessoryLabel: 'DURATION',
                          hint: '30',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ]),
                    if (_kind != MemberPlanKind.monthly) ...[
                      const SizedBox(height: 14),
                      KeyboardAccessoryField(
                        controller: _units,
                        label: _kind == MemberPlanKind.hours
                            ? 'Included minutes'
                            : 'Included passes',
                        accessoryLabel: 'INCLUDED',
                        hint: _kind == MemberPlanKind.hours ? '600' : '5',
                        keyboardType: TextInputType.number,
                        fillColor: YColor.surface1,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(_unitsLabel, style: YFont.caption()),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text('ACCENT COLOUR',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: PlansManagerSheet.palette.map((entry) {
                        final (label, hex, preview) = entry;
                        final selected =
                            _color.toLowerCase() == hex.toLowerCase();
                        return GestureDetector(
                          onTap: () => setState(() => _color = hex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? preview.withValues(alpha: 0.18)
                                  : YColor.surface1,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected ? preview : YColor.hairline,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: preview,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(label,
                                    style: YFont.bodyStrong().copyWith(
                                      fontSize: 12,
                                      color: selected ? preview : YColor.ink,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text('PERKS (OPTIONAL)',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in _perks)
                          Container(
                            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                            decoration: BoxDecoration(
                              color: YColor.brandTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(p,
                                    style: YFont.caption().copyWith(
                                      fontSize: 11,
                                      color: YColor.brandDeep,
                                      fontWeight: FontWeight.w700,
                                    )),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  iconSize: 14,
                                  constraints: const BoxConstraints(
                                      minWidth: 22, minHeight: 22),
                                  onPressed: () => setState(
                                      () => _perks = _perks
                                          .where((x) => x != p)
                                          .toList()),
                                  icon: const Icon(Icons.close,
                                      size: 12,
                                      color: YColor.brandDeep),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _perk,
                          onSubmitted: (_) => _addPerk(),
                          decoration: InputDecoration(
                            hintText:
                                'e.g. Free coffee, Priority seating, 10% off products',
                            isDense: true,
                            filled: true,
                            fillColor: YColor.surface1,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(YRadius.md),
                              borderSide:
                                  const BorderSide(color: YColor.hairline),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(YRadius.md),
                              borderSide:
                                  const BorderSide(color: YColor.hairline),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(YRadius.md),
                              borderSide: const BorderSide(
                                  color: YColor.brand, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addPerk,
                        icon: const Icon(Icons.add, size: 18),
                        style: IconButton.styleFrom(
                          backgroundColor: YColor.brand,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: ThemedDropdown<int>(
                          label: 'Sort order (low = first)',
                          value: int.tryParse(_sort.text) ?? 100,
                          items: const [10, 50, 100, 150, 200],
                          labelOf: (n) => '$n',
                          onChanged: (n) {
                            if (n != null) {
                              setState(() => _sort.text = n.toString());
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: YColor.brand,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isActive ? 'Visible to cashier' : 'Hidden',
                        style: YFont.caption(),
                      ),
                    ]),
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
                  onPressed: _canSave ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                  child: Text(widget.existing == null
                      ? 'Add plan'
                      : 'Save changes'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindTile(MemberPlanKind k) {
    final on = _kind == k;
    final accent = on ? YColor.brand : YColor.hairline;
    return GestureDetector(
      onTap: () => setState(() => _kind = k),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: on
              ? YColor.brand.withValues(alpha: 0.08)
              : YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: accent, width: on ? 1.5 : 1),
        ),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (on ? YColor.brand : YColor.inkMuted)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(k.icon,
                size: 18, color: on ? YColor.brand : YColor.inkMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(k.label,
                    style: YFont.bodyStrong().copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(k.description,
                    style: YFont.caption().copyWith(fontSize: 11)),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: on
                ? const Icon(Icons.check_circle,
                    key: ValueKey('on'), color: YColor.brand)
                : const Icon(Icons.radio_button_unchecked,
                    key: ValueKey('off'), color: YColor.hairline),
          ),
        ]),
      ),
    );
  }
}
