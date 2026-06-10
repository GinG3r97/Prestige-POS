import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/payroll_rules.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import '../../design_system/icons.dart'
    show IconPickerField, iconFromKey, materialIconForName;

/// Owner-facing payroll configuration. The tab now has four cards:
///   1. Employment templates  — per-type compensation, default rate, OT, leaves
///   2. Global multipliers     — rest day / holiday / night diff
///   3. Hours, undertime, gov  — standard hours + lateness + 13th-month etc.
///   4. Leave types            — buckets templates can draw from
///
/// All four persist to Supabase via [AppState] (no more in-memory drafts).
class PayrollRulesTab extends StatefulWidget {
  const PayrollRulesTab({super.key, required this.state});
  final AppState state;

  @override
  State<PayrollRulesTab> createState() => _PayrollRulesTabState();
}

class _PayrollRulesTabState extends State<PayrollRulesTab> {
  late PayrollRules _draft;
  bool _saving = false;

  late final TextEditingController _regHours;
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

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final templates = state.employmentTemplates;
    final leaves = state.leaveTypes;
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
                      Text('Payroll',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        'Set up rates and rules once — they auto-fill when you add an employee, and feed every pay run.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
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
              const SizedBox(height: 20),

              // ─── Employment templates (NEW, on top) ───
              _SectionCard(
                title: 'Employment templates',
                subtitle:
                    'Pre-fill compensation, default rate, OT, and available leaves per employment type. The Add Employee modal reads from here.',
                child: Column(children: [
                  for (var i = 0; i < templates.length; i++) ...[
                    _TemplateRow(
                      state: state,
                      template: templates[i],
                      onTap: () => _editTemplate(templates[i]),
                    ),
                    if (i != templates.length - 1) const _CardDivider(),
                  ],
                ]),
              ),

              const SizedBox(height: 16),

              // ─── Standard hours ───
              _SectionCard(
                title: 'Standard hours',
                subtitle:
                    'Beyond this in a single day counts as overtime.',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(children: [
                    SizedBox(
                      width: 200,
                      child: _numField(
                          label: 'Regular hours / day',
                          controller: _regHours,
                          suffix: 'hr'),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 16),

              // ─── Global multipliers (no more standard OT here) ───
              _SectionCard(
                title: 'Labor-law multipliers',
                subtitle:
                    'Applied on top of the employee\'s base rate. Standard overtime lives on each template above.',
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

              const SizedBox(height: 16),

              _SectionCard(
                title: 'Undertime & lateness',
                child: Column(children: [
                  _switchRow(
                    icon: Icons.timer_off_outlined,
                    title: 'Deduct undertime',
                    subtitle:
                        'Subtract missed hours when an employee clocks out early',
                    value: _draft.deductUndertime,
                    onChanged: (v) =>
                        setState(() => _draft.deductUndertime = v),
                  ),
                  const _CardDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.alarm,
                          size: 18, color: YColor.brandDeep),
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
                        width: 110,
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
                    subtitle:
                        'Mandatory in the Philippines — accrued monthly',
                    value: _draft.include13thMonth,
                    onChanged: (v) =>
                        setState(() => _draft.include13thMonth = v),
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
                    onChanged: (v) =>
                        setState(() => _draft.deductPhilHealth = v),
                  ),
                  const _CardDivider(),
                  _switchRow(
                    icon: Icons.home_work_outlined,
                    title: 'Pag-IBIG contribution',
                    value: _draft.deductPagIBIG,
                    onChanged: (v) =>
                        setState(() => _draft.deductPagIBIG = v),
                  ),
                  const _CardDivider(),
                  _switchRow(
                    icon: Icons.receipt_long_outlined,
                    title: 'BIR withholding tax',
                    value: _draft.withholdBIR,
                    onChanged: (v) =>
                        setState(() => _draft.withholdBIR = v),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: 'Leave types',
                subtitle:
                    'Buckets staff can draw from. Edit names, days/year, paid status.',
                action: TextButton.icon(
                  onPressed: () => _editLeave(null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add type'),
                  style: TextButton.styleFrom(foregroundColor: YColor.brand),
                ),
                child: leaves.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Center(
                          child: Text(
                            'No leave types yet. Add one to start tracking time off.',
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

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
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
          width: 110,
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
        IconButton(
          tooltip: 'Edit',
          onPressed: () => _editLeave(lt),
          icon: const Icon(Icons.edit_outlined,
              size: 18, color: YColor.inkMuted),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => _confirmDeleteLeave(lt),
          icon: const Icon(Icons.delete_outline,
              size: 18, color: YColor.danger),
        ),
      ]),
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
      _UnitBadge(label: unit == '×' ? '× MULT' : unit.toUpperCase());

  Future<void> _editTemplate(EmploymentTemplate t) async {
    final saved = await showDialog<EmploymentTemplate>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateDialog(
        initial: t,
        leaveTypes: widget.state.leaveTypes,
      ),
    );
    if (saved == null || !mounted) return;
    final err = await widget.state.updateEmploymentTemplate(saved);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Template updated',
        subtitle: _employmentLabel(saved.employmentType),
        leadingIcon: Icons.work_outline);
  }

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

String _employmentLabel(EmploymentType t) => switch (t) {
      EmploymentType.fullTime => 'Full-time',
      EmploymentType.partTime => 'Part-time',
      EmploymentType.contract => 'Contract',
      EmploymentType.seasonal => 'Seasonal',
    };

IconData _employmentIcon(EmploymentType t) => switch (t) {
      EmploymentType.fullTime => Icons.work_outline,
      EmploymentType.partTime => Icons.schedule_outlined,
      EmploymentType.contract => Icons.assignment_outlined,
      EmploymentType.seasonal => Icons.eco_outlined,
    };

/// Pick a themed Material icon for a leave. Precedence:
///   1. owner-picked `iconName` from the icon picker,
///   2. keyword auto-map (handles seeded names like "Vacation Leave"),
///   3. generic fallback so we never render an emoji.
IconData leaveIconFor(LeaveType lt) =>
    iconFromKey(lt.iconName) ??
    materialIconForName(lt.name) ??
    Icons.beach_access_outlined;

// ───── Template row ─────

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.state,
    required this.template,
    required this.onTap,
  });
  final AppState state;
  final EmploymentTemplate template;
  final VoidCallback onTap;

  String _rateLabel() {
    final v = template.defaultRate;
    if (v == 0) return 'Rate not set';
    final formatted = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
    return '₱$formatted${template.compensationType.rateSuffix}';
  }

  @override
  Widget build(BuildContext context) {
    final leaves = state.leaveTypes
        .where((l) => template.leaveTypeIds.contains(l.id))
        .toList();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_employmentIcon(template.employmentType),
                size: 20, color: YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(_employmentLabel(template.employmentType),
                      style: YFont.bodyStrong().copyWith(fontSize: 15)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: YColor.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(template.compensationType.label.toUpperCase(),
                        style: YFont.caption().copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: YColor.brand,
                        )),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${_rateLabel()} · OT ×${template.overtimeMultiplier.toStringAsFixed(2)}',
                  style: YFont.caption(),
                ),
                if (leaves.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final l in leaves)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: YColor.surface2,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: YColor.hairline),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(leaveIconFor(l),
                                    size: 11, color: YColor.brandDeep),
                                const SizedBox(width: 4),
                                Text(l.name,
                                    style: YFont.caption()
                                        .copyWith(fontSize: 10)),
                              ]),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 20, color: YColor.inkMuted),
        ]),
      ),
    );
  }
}

// ───── Template edit dialog ─────

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({required this.initial, required this.leaveTypes});
  final EmploymentTemplate initial;
  final List<LeaveType> leaveTypes;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late CompensationType _compType;
  late final TextEditingController _hourly;
  late final TextEditingController _daily;
  late final TextEditingController _monthly;
  late final TextEditingController _ot;
  late Set<String> _leaves;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _compType = t.compensationType;
    _hourly = TextEditingController(text: _fmt(t.defaultHourlyRate));
    _daily = TextEditingController(text: _fmt(t.defaultDailyRate));
    _monthly = TextEditingController(text: _fmt(t.defaultMonthlySalary));
    _ot = TextEditingController(text: t.overtimeMultiplier.toStringAsFixed(2));
    _leaves = {...t.leaveTypeIds};
  }

  @override
  void dispose() {
    _hourly.dispose();
    _daily.dispose();
    _monthly.dispose();
    _ot.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  void _save() {
    final saved = EmploymentTemplate(
      id: widget.initial.id,
      employmentType: widget.initial.employmentType,
      compensationType: _compType,
      defaultHourlyRate: double.tryParse(_hourly.text) ?? 0,
      defaultDailyRate: double.tryParse(_daily.text) ?? 0,
      defaultMonthlySalary: double.tryParse(_monthly.text) ?? 0,
      overtimeMultiplier:
          double.tryParse(_ot.text) ?? widget.initial.overtimeMultiplier,
      leaveTypeIds: _leaves,
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
              Icon(_employmentIcon(widget.initial.employmentType),
                  size: 22, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Text(
                '${_employmentLabel(widget.initial.employmentType)} template',
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
                    Text('COMPENSATION TYPE',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (final c in CompensationType.values) ...[
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(YRadius.md),
                            onTap: () => setState(() => _compType = c),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                color: _compType == c
                                    ? YColor.brand.withValues(alpha: 0.08)
                                    : YColor.surface2,
                                borderRadius:
                                    BorderRadius.circular(YRadius.md),
                                border: Border.all(
                                  color: _compType == c
                                      ? YColor.brand
                                      : YColor.hairline,
                                  width: _compType == c ? 1.4 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(c.label,
                                    style: YFont.bodyStrong()
                                        .copyWith(fontSize: 13)),
                              ),
                            ),
                          ),
                        ),
                        if (c != CompensationType.values.last)
                          const SizedBox(width: 8),
                      ],
                    ]),
                    const SizedBox(height: 18),
                    Text('DEFAULT RATE',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    // Show the rate field that matches the picked comp type.
                    _rateField(),
                    const SizedBox(height: 18),
                    Text('OVERTIME MULTIPLIER',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: 200,
                      child: KeyboardAccessoryField(
                        controller: _ot,
                        accessoryLabel: 'OT',
                        hint: '1.25',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        fillColor: YColor.surface2,
                        borderColor: YColor.hairline,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        suffix: _UnitBadge.mult(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text('AVAILABLE LEAVE TYPES',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      'Employees of this type can avail any leave you check below.',
                      style: YFont.caption(),
                    ),
                    const SizedBox(height: 10),
                    if (widget.leaveTypes.isEmpty)
                      Text(
                        'No leave types defined yet. Add some in the Leave types section first.',
                        style: YFont.caption()
                            .copyWith(color: YColor.inkMuted),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final l in widget.leaveTypes)
                            _leaveChip(l),
                        ],
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
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: const Text('Save'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _rateField() {
    final ctrl = switch (_compType) {
      CompensationType.hourly => _hourly,
      CompensationType.daily => _daily,
      CompensationType.salaried => _monthly,
    };
    final hint = switch (_compType) {
      CompensationType.hourly => 'e.g., 140',
      CompensationType.daily => 'e.g., 800',
      CompensationType.salaried => 'e.g., 28000',
    };
    final unitLabel = switch (_compType) {
      CompensationType.hourly => 'PER HOUR',
      CompensationType.daily => 'PER DAY',
      CompensationType.salaried => 'PER MONTH',
    };
    return SizedBox(
      width: 320,
      child: KeyboardAccessoryField(
        controller: ctrl,
        accessoryLabel: 'RATE',
        hint: hint,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        fillColor: YColor.surface2,
        borderColor: YColor.hairline,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffix: _UnitBadge(label: unitLabel),
      ),
    );
  }

  Widget _leaveChip(LeaveType l) {
    final on = _leaves.contains(l.id);
    return InkWell(
      borderRadius: BorderRadius.circular(YRadius.md),
      onTap: () => setState(() {
        if (on) {
          _leaves.remove(l.id);
        } else {
          _leaves.add(l.id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? YColor.brand.withValues(alpha: 0.08) : YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(
            color: on ? YColor.brand : YColor.hairline,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            on ? Icons.check_box_outlined : Icons.check_box_outline_blank,
            size: 16,
            color: on ? YColor.brand : YColor.inkMuted,
          ),
          const SizedBox(width: 8),
          Icon(leaveIconFor(l),
              size: 16,
              color: on ? YColor.brand : YColor.brandDeep),
          const SizedBox(width: 6),
          Text(l.name, style: YFont.bodyStrong().copyWith(fontSize: 13)),
        ]),
      ),
    );
  }
}

// ───── helpers ─────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    this.action,
    required this.child,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
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
              if (action != null) action!,
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
  factory _UnitBadge.mult() => const _UnitBadge(label: '× MULT');

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
