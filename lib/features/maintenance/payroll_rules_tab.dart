import 'package:flutter/material.dart';

import '../../app/stores/hr_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/payroll_rules.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import '../../design_system/icons.dart'
    show IconPickerField, iconFromKey, materialIconForName;

/// Owner-facing payroll configuration. A left rail switches between three
/// sections:
///   1. Hours & rates  — standard hours, allowed OT, labor-law multipliers
///   2. Deductions     — undertime, lateness grace, government / 13th-month
///   3. Leave types    — buckets staff can draw from
///
/// All persist to Supabase via [HrStore].
class PayrollRulesTab extends StatefulWidget {
  const PayrollRulesTab({super.key, required this.state});
  final HrStore state;

  @override
  State<PayrollRulesTab> createState() => _PayrollRulesTabState();
}

class _PayrollRulesTabState extends State<PayrollRulesTab> {
  late PayrollRules _draft;
  bool _saving = false;

  late final TextEditingController _regHours;
  late final TextEditingController _otHours;
  late final TextEditingController _restMul;
  late final TextEditingController _regHolMul;
  late final TextEditingController _specHolMul;
  late final TextEditingController _ndMul;
  late final TextEditingController _grace;

  @override
  void initState() {
    super.initState();
    _draft = widget.state.payrollRules.copy();
    _regHours = TextEditingController(text: _fmt(_draft.regularHoursPerDay));
    _otHours =
        TextEditingController(text: _fmt(_draft.maxOvertimeHoursPerDay));
    _restMul = TextEditingController(text: _fmt(_draft.restDayMultiplier));
    _regHolMul =
        TextEditingController(text: _fmt(_draft.regularHolidayMultiplier));
    _specHolMul =
        TextEditingController(text: _fmt(_draft.specialHolidayMultiplier));
    _ndMul = TextEditingController(
        text: _fmt(_draft.nightDifferentialMultiplier));
    _grace = TextEditingController(
        text: _draft.latenessGraceMinutes.toString());
  }

  @override
  void dispose() {
    _regHours.dispose();
    _otHours.dispose();
    _restMul.dispose();
    _regHolMul.dispose();
    _specHolMul.dispose();
    _ndMul.dispose();
    _grace.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Future<void> _save() async {
    _draft.regularHoursPerDay =
        double.tryParse(_regHours.text) ?? _draft.regularHoursPerDay;
    _draft.maxOvertimeHoursPerDay =
        (double.tryParse(_otHours.text) ?? _draft.maxOvertimeHoursPerDay)
            .clamp(0, 24)
            .toDouble();
    _draft.restDayMultiplier =
        double.tryParse(_restMul.text) ?? _draft.restDayMultiplier;
    _draft.regularHolidayMultiplier =
        double.tryParse(_regHolMul.text) ?? _draft.regularHolidayMultiplier;
    _draft.specialHolidayMultiplier =
        double.tryParse(_specHolMul.text) ?? _draft.specialHolidayMultiplier;
    _draft.nightDifferentialMultiplier =
        double.tryParse(_ndMul.text) ?? _draft.nightDifferentialMultiplier;
    _draft.latenessGraceMinutes =
        int.tryParse(_grace.text) ?? _draft.latenessGraceMinutes;

    setState(() => _saving = true);
    final err = await widget.state.updatePayrollRules(_draft.copy());
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Payroll rules saved',
        subtitle: 'Applied to future pay runs',
        leadingIcon: Icons.check_circle_outline);
  }

  // Which payroll setup section the rail is showing.
  int _section = 0;

  static const _sections = <({String title, String sub, IconData icon})>[
    (
      title: 'Hours & rates',
      sub:
          'Standard hours and the labor-law multipliers applied on top of base pay.',
      icon: Icons.schedule_outlined,
    ),
    (
      title: 'Deductions',
      sub:
          'Undertime, lateness grace, and the government / 13th-month line items.',
      icon: Icons.receipt_long_outlined,
    ),
    (
      title: 'Leave types',
      sub: 'Buckets staff can draw from — names, days per year, paid status.',
      icon: Icons.event_available_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final showSave = _section == 0 || _section == 1;
    return Container(
      color: YColor.surface2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Rail ──
          SizedBox(
            width: 212,
            child: Container(
              decoration: const BoxDecoration(
                color: YColor.surface1,
                border: Border(right: BorderSide(color: YColor.hairline)),
              ),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                    child: Text('PAYROLL SETUP',
                        style: YFont.caption().copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: YColor.inkMuted,
                        )),
                  ),
                  for (var i = 0; i < _sections.length; i++)
                    _railRow(i, _sections[i].title, _sections[i].icon),
                ],
              ),
            ),
          ),
          // ── Content ──
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_sections[_section].title,
                              style: YFont.titleMD().copyWith(fontSize: 19)),
                          const SizedBox(height: 2),
                          Text(_sections[_section].sub, style: YFont.caption()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (_section == 2)
                      ElevatedButton.icon(
                        onPressed: () => _editLeave(null),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add type'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YRadius.md)),
                        ),
                      )
                    else if (showSave)
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined, size: 16),
                        label: Text(_saving ? 'Saving…' : 'Save changes'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.brand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YRadius.md)),
                        ),
                      ),
                  ]),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 36),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _sectionContent(state),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _railRow(int i, String label, IconData icon) {
    final on = _section == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _section = i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        decoration: BoxDecoration(
          color: on ? YColor.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(YRadius.md),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: on ? Colors.white : YColor.brandDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: YFont.bodyStrong().copyWith(
                  fontSize: 13.5,
                  color: on ? Colors.white : YColor.ink,
                )),
          ),
        ]),
      ),
    );
  }

  List<Widget> _sectionContent(HrStore state) {
    switch (_section) {
      case 0:
        return [
          _SectionCard(
            title: 'Standard hours & overtime',
            subtitle:
                'Work beyond regular hours counts as overtime, capped by the allowed OT hours.',
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: 240,
                    child: _numField(
                        label: 'Regular hours / day',
                        controller: _regHours,
                        suffix: 'hr'),
                  ),
                  SizedBox(
                    width: 240,
                    child: _numField(
                        label: 'Allowed OT hours / day',
                        controller: _otHours,
                        suffix: 'hr'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 8),
            child: Text('Allowed OT hours: 0 = no cap.',
                style: YFont.caption()),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Labor-law multipliers',
            subtitle:
                'Applied on top of the employee\'s base rate. Standard overtime lives on each template.',
            child: Column(children: [
              _multRow(
                label: 'Rest day work',
                hint: 'Working on scheduled day off',
                controller: _restMul,
              ),
              const _CardDivider(),
              _multRow(
                label: 'Regular holiday',
                hint: '12 PH regular holidays — double pay',
                controller: _regHolMul,
              ),
              const _CardDivider(),
              _multRow(
                label: 'Special holiday',
                hint: 'Special non-working days — 30% premium',
                controller: _specHolMul,
              ),
              const _CardDivider(),
              _multRow(
                label: 'Night differential',
                hint: 'Default window 10 PM → 6 AM',
                controller: _ndMul,
              ),
            ]),
          ),
        ];
      case 1:
        return [
          _SectionCard(
            title: 'Undertime & lateness',
            child: Column(children: [
              _switchRow(
                icon: Icons.timer_off_outlined,
                title: 'Deduct undertime',
                subtitle:
                    'Subtract missed hours when an employee clocks out early',
                value: _draft.deductUndertime,
                onChanged: (v) => setState(() => _draft.deductUndertime = v),
              ),
              const _CardDivider(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const Icon(Icons.alarm, size: 18, color: YColor.brandDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lateness grace period',
                            style: YFont.bodyStrong()),
                        Text(
                          'Minutes of clock-in slack before deductions kick in',
                          style: YFont.caption(),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 132,
                    child: _numField(
                        label: '', controller: _grace, suffix: 'min'),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Government & 13th month',
            subtitle:
                'Show these line items on payslips. Tables coming in a later release.',
            child: Column(children: [
              _switchRow(
                icon: Icons.card_giftcard_outlined,
                title: '13th-month pay',
                subtitle: 'Mandatory in the Philippines — accrued monthly',
                value: _draft.include13thMonth,
                onChanged: (v) => setState(() => _draft.include13thMonth = v),
              ),
              const _CardDivider(),
              _switchRow(
                icon: Icons.account_balance_outlined,
                title: 'SSS contribution',
                value: _draft.deductSSS,
                onChanged: (v) => setState(() => _draft.deductSSS = v),
              ),
              const _CardDivider(),
              _switchRow(
                icon: Icons.medical_services_outlined,
                title: 'PhilHealth contribution',
                value: _draft.deductPhilHealth,
                onChanged: (v) => setState(() => _draft.deductPhilHealth = v),
              ),
              const _CardDivider(),
              _switchRow(
                icon: Icons.home_work_outlined,
                title: 'Pag-IBIG contribution',
                value: _draft.deductPagIBIG,
                onChanged: (v) => setState(() => _draft.deductPagIBIG = v),
              ),
              const _CardDivider(),
              _switchRow(
                icon: Icons.receipt_long_outlined,
                title: 'BIR withholding tax',
                value: _draft.withholdBIR,
                onChanged: (v) => setState(() => _draft.withholdBIR = v),
              ),
            ]),
          ),
        ];
      default:
        final leaves = state.leaveTypes;
        return [
          _SectionCard(
            title: 'Leave types',
            subtitle:
                'Buckets staff can draw from. Use the 3-dot menu to edit or delete.',
            child: leaves.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No leave types yet. Tap "Add type" to start tracking time off.',
                        style: YFont.caption(),
                      ),
                    ),
                  )
                : Column(children: [
                    for (var i = 0; i < leaves.length; i++) ...[
                      _leaveRow(leaves[i]),
                      if (i != leaves.length - 1) const _CardDivider(),
                    ],
                  ]),
          ),
        ];
    }
  }

  Widget _multRow({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: YFont.bodyStrong()),
              Text(hint, style: YFont.caption()),
            ],
          ),
        ),
        SizedBox(
          width: 140,
          child: _numField(label: '', controller: controller, suffix: '×'),
        ),
      ]),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 18, color: YColor.brandDeep),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: YFont.bodyStrong()),
              if (subtitle != null) Text(subtitle, style: YFont.caption()),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: YColor.brand,
        ),
      ]),
    );
  }

  Widget _leaveRow(LeaveType lt) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(leaveIconFor(lt),
              size: 18, color: YColor.brandDeep),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lt.name, style: YFont.bodyStrong()),
              Text(
                '${lt.annualDays == 0 ? 'No cap' : '${lt.annualDays} day${lt.annualDays == 1 ? '' : 's'} / yr'}'
                ' · ${lt.paid ? 'Paid' : 'Unpaid'}'
                '${lt.notes.isEmpty ? '' : ' · ${lt.notes}'}',
                style: YFont.caption(),
              ),
            ],
          ),
        ),
        _rowMenu(
          onEdit: () => _editLeave(lt),
          onDelete: () => _confirmDeleteLeave(lt),
        ),
      ]),
    );
  }

  /// Shared 3-dot overflow menu for an editable / deletable row.
  Widget _rowMenu({required VoidCallback onEdit, VoidCallback? onDelete}) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 19, color: YColor.inkMuted),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      color: YColor.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YRadius.md),
        side: const BorderSide(color: YColor.hairline),
      ),
      onSelected: (v) {
        if (v == 'edit') onEdit();
        if (v == 'delete') onDelete?.call();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          height: 40,
          child: Text('Edit', style: YFont.body()),
        ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            height: 40,
            child: Text('Delete',
                style: YFont.body().copyWith(color: YColor.danger)),
          ),
      ],
    );
  }

  Widget _numField({
    required String label,
    required TextEditingController controller,
    String? suffix,
  }) {
    return KeyboardAccessoryField(
      controller: controller,
      label: label,
      accessoryLabel: label.isEmpty ? 'VALUE' : label.toUpperCase(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      fillColor: YColor.surface2,
      borderColor: YColor.hairline,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      textStyle: const TextStyle(
        fontFamily: 'Menlo',
        fontWeight: FontWeight.w600,
      ),
      suffix: suffix == null ? null : _unitSuffix(suffix),
    );
  }

  Widget _unitSuffix(String unit) =>
      _UnitBadge(label: unit == '×' ? '×' : unit.toUpperCase());

  Future<void> _editLeave(LeaveType? initial) async {
    final saved = await showDialog<LeaveType>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LeaveTypeDialog(initial: initial),
    );
    if (saved == null || !mounted) return;
    final err = initial == null
        ? await widget.state.addLeaveType(saved)
        : await widget.state.updateLeaveType(saved);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: initial == null ? 'Leave added' : 'Leave updated',
        subtitle: saved.name,
        leadingIcon: Icons.beach_access_outlined);
  }

  Future<void> _confirmDeleteLeave(LeaveType lt) async {
    final ok = await showConfirm(
      context,
      title: 'Delete "${lt.name}"?',
      message: 'Employees with pending balance for this leave will lose it.',
      confirmLabel: 'Delete',
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final err = await widget.state.removeLeaveType(lt.id);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not delete',
          subtitle: err,
          leadingIcon: Icons.error_outline);
    }
  }
}

/// Pick a themed Material icon for a leave. Precedence:
///   1. owner-picked `iconName` from the icon picker,
///   2. keyword auto-map (handles seeded names like "Vacation Leave"),
///   3. generic fallback so we never render an emoji.
IconData leaveIconFor(LeaveType lt) =>
    iconFromKey(lt.iconName) ??
    materialIconForName(lt.name) ??
    Icons.beach_access_outlined;

// ───── helpers ─────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style:
                            YFont.bodyStrong().copyWith(fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: YFont.caption()),
                    ],
                  ],
                ),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          child,
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        color: YColor.hairline,
        margin: const EdgeInsets.symmetric(horizontal: 16),
      );
}

// ───── Leave type editor dialog ─────

class _LeaveTypeDialog extends StatefulWidget {
  const _LeaveTypeDialog({this.initial});
  final LeaveType? initial;

  @override
  State<_LeaveTypeDialog> createState() => _LeaveTypeDialogState();
}

class _LeaveTypeDialogState extends State<_LeaveTypeDialog> {
  late final TextEditingController _name;
  late final TextEditingController _days;
  late final TextEditingController _notes;
  String? _iconName;
  late bool _paid;

  @override
  void initState() {
    super.initState();
    final lt = widget.initial;
    _name = TextEditingController(text: lt?.name ?? '');
    _iconName = lt?.iconName ??
        (lt == null ? 'beach_access_outlined' : null);
    _days = TextEditingController(text: (lt?.annualDays ?? 5).toString());
    _notes = TextEditingController(text: lt?.notes ?? '');
    _paid = lt?.paid ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    final saved = LeaveType(
      id: widget.initial?.id,
      name: _name.text.trim(),
      emoji: widget.initial?.emoji ?? '🌴',
      iconName: _iconName,
      annualDays: int.tryParse(_days.text) ?? 0,
      paid: _paid,
      notes: _notes.text.trim(),
      sortOrder: widget.initial?.sortOrder ?? 100,
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
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
                widget.initial == null ? 'Add leave type' : 'Edit leave type',
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
                constraints: const BoxConstraints(maxWidth: 540),
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
                                fallbackIcon: Icons.beach_access_outlined,
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
                            hint: 'e.g., Vacation Leave',
                            fillColor: YColor.surface1,
                            borderColor: YColor.hairline,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _days,
                          label: 'Days per year',
                          accessoryLabel: 'DAYS',
                          hint: '5',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: YColor.surface1,
                            borderRadius: BorderRadius.circular(YRadius.md),
                            border: Border.all(color: YColor.hairline),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('Paid', style: YFont.bodyStrong()),
                                  Text(
                                    _paid
                                        ? 'Hours paid even when on leave'
                                        : 'Hours deducted from pay',
                                    style: YFont.caption(),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _paid,
                              onChanged: (v) => setState(() => _paid = v),
                              activeThumbColor: YColor.brand,
                            ),
                          ]),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    KeyboardAccessoryField(
                      controller: _notes,
                      label: 'Notes (optional)',
                      accessoryLabel: 'NOTES',
                      hint: 'e.g., Mandatory under PH Labour Code',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
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

/// A brand-colored chip suffix used inside numeric input fields to label the
/// unit (× MULT, HR, MIN, PER DAY, etc.). Replaces the previous plain-grey
/// '×' suffix that read like a close/clear button.
class _UnitBadge extends StatelessWidget {
  const _UnitBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: YColor.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: YFont.caption().copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
            color: YColor.brand,
          ),
        ),
      ),
    );
  }
}
