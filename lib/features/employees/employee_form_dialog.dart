import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/payroll_rules.dart';
import '../widgets/keyboard_accessory_field.dart';

/// What the dialog returns to its caller. Carries the saved employee plus,
/// when the chosen role requires a PIN, the plaintext cashier PIN the
/// caller should pass to [AppState.addEmployee] / [updateEmployee] (which
/// hashes it via the bcrypt `set_cashier_pin` RPC).
class EmployeeFormResult {
  final Employee employee;
  final String? cashierPin;
  const EmployeeFormResult({required this.employee, this.cashierPin});
}

class EmployeeFormDialog extends StatefulWidget {
  const EmployeeFormDialog({super.key, this.initial});
  final Employee? initial;

  @override
  State<EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<EmployeeFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _pin;
  late final TextEditingController _hourlyRate;
  late final TextEditingController _dailyRate;
  late final TextEditingController _monthlySalary;
  late final TextEditingController _notes;

  /// Lazy controllers for shift fields, keyed by "${weekday}_${start|end}".
  final Map<String, TextEditingController> _shiftCtrls = {};

  /// Lazy controllers for document name fields, keyed by document id.
  final Map<String, TextEditingController> _docCtrls = {};

  TextEditingController _shiftCtrl(int weekday, String which, String value) {
    final key = '${weekday}_$which';
    final existing = _shiftCtrls[key];
    if (existing != null) return existing;
    return _shiftCtrls[key] = TextEditingController(text: value);
  }

  TextEditingController _docNameCtrl(String docId, String value) {
    final existing = _docCtrls[docId];
    if (existing != null) return existing;
    return _docCtrls[docId] = TextEditingController(text: value);
  }

  String? _roleId;
  Gender _gender = Gender.male;
  late EmployeeStatus _status;
  late EmploymentType _employmentType;
  late CompensationType _compensationType;
  late DateTime _hireDate;
  late List<WorkShift> _schedule;
  late List<EmployeeDocument> _documents;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _name = TextEditingController(text: e?.name ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _pin = TextEditingController();
    _hourlyRate = TextEditingController(
        text: e == null || e.hourlyRate == 0
            ? ''
            : e.hourlyRate.toStringAsFixed(0));
    _dailyRate = TextEditingController(
        text: e == null || e.dailyRate == 0
            ? ''
            : e.dailyRate.toStringAsFixed(0));
    _monthlySalary = TextEditingController(
        text: e == null || e.monthlySalary == 0
            ? ''
            : e.monthlySalary.toStringAsFixed(0));
    _notes = TextEditingController(text: e?.notes ?? '');

    _roleId = e?.roleId;
    _gender = e?.gender ?? Gender.male;
    _status = e?.status ?? EmployeeStatus.active;
    _employmentType = e?.employmentType ?? EmploymentType.fullTime;
    _compensationType = e?.compensationType ?? CompensationType.hourly;
    _hireDate = e?.hireDate ?? DateTime.now();
    _schedule = e == null
        ? _defaultSchedule()
        : e.schedule
            .map((s) =>
                WorkShift(weekday: s.weekday, start: s.start, end: s.end))
            .toList();
    _documents = e == null
        ? <EmployeeDocument>[]
        : e.documents
            .map((d) => EmployeeDocument(
                  id: d.id,
                  name: d.name,
                  status: d.status,
                  expiresOn: d.expiresOn,
                ))
            .toList();

    // For brand-new employees, pre-fill from the default employment type's
    // template once the first frame is up (we can't read Provider in
    // initState directly). The post-frame call also avoids racing the
    // owner — if they switch employment type immediately, [_employmentTypeDropdown]
    // will reapply with the new template.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyTemplateForType(_employmentType);
      });
    }
  }

  /// Owner-confirmed default schedule for new employees: Mon–Fri 9 AM – 5 PM,
  /// weekends empty. Owners can edit row-by-row inside the dialog.
  List<WorkShift> _defaultSchedule() => [
        for (var w = 1; w <= 5; w++)
          WorkShift(weekday: w, start: '09:00', end: '17:00'),
      ];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _pin.dispose();
    _hourlyRate.dispose();
    _dailyRate.dispose();
    _monthlySalary.dispose();
    _notes.dispose();
    for (final c in _shiftCtrls.values) {
      c.dispose();
    }
    for (final c in _docCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Apply the matching employment template for [t] — pre-fills compensation
  /// type + rate from Maintenance → Payroll. Only fires for new employees:
  /// editing an existing employee keeps their saved overrides intact, since
  /// pulling the template would silently overwrite the owner's manual edits.
  void _applyTemplateForType(EmploymentType t) {
    if (widget.initial != null) return;
    final tpl = context.read<AppState>().templateFor(t);
    if (tpl == null) return;
    setState(() {
      _compensationType = tpl.compensationType;
      _hourlyRate.text = tpl.defaultHourlyRate == 0
          ? ''
          : tpl.defaultHourlyRate.toStringAsFixed(0);
      _dailyRate.text = tpl.defaultDailyRate == 0
          ? ''
          : tpl.defaultDailyRate.toStringAsFixed(0);
      _monthlySalary.text = tpl.defaultMonthlySalary == 0
          ? ''
          : tpl.defaultMonthlySalary.toStringAsFixed(0);
    });
  }

  EmployeeRole? get _selectedRole {
    if (_roleId == null) return null;
    final roles = context.read<AppState>().employeeRoles;
    for (final r in roles) {
      if (r.id == _roleId) return r;
    }
    return null;
  }

  bool get _needsPin => _selectedRole?.requiresPin == true;

  bool get _pinValid {
    if (!_needsPin) return true;
    // For new employees the field must be filled; for edits a blank value
    // means "keep current PIN", which is also valid.
    final v = _pin.text.trim();
    if (widget.initial != null && v.isEmpty) return true;
    return v.length >= 4 && v.length <= 8 && int.tryParse(v) != null;
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _roleId != null && _pinValid;

  void _save() {
    final role = _selectedRole;
    final saved = Employee(
      id: widget.initial?.id,
      name: _name.text.trim(),
      gender: _gender,
      roleId: _roleId,
      role: role?.name ?? '',
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      hireDate: _hireDate,
      status: _status,
      employmentType: _employmentType,
      compensationType: _compensationType,
      hourlyRate: double.tryParse(_hourlyRate.text) ?? 0,
      dailyRate: double.tryParse(_dailyRate.text) ?? 0,
      monthlySalary: double.tryParse(_monthlySalary.text) ?? 0,
      schedule: _schedule,
      documents: _documents,
      // Portal stays locked for this turn — keep whatever was there.
      portalEnabled: widget.initial?.portalEnabled ?? false,
      portalGmail: widget.initial?.portalGmail ?? '',
      portalUsername: widget.initial?.portalUsername ?? '',
      portalInvitedAt: widget.initial?.portalInvitedAt,
      portalLastLoginAt: widget.initial?.portalLastLoginAt,
      notes: _notes.text.trim(),
    );
    final pin = _needsPin && _pin.text.trim().isNotEmpty
        ? _pin.text.trim()
        : null;
    Navigator.of(context).pop(EmployeeFormResult(employee: saved, cashierPin: pin));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 160,
        height: size.height - 120,
        child: Column(children: [
          // Title bar
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(
                widget.initial == null ? 'Add employee' : 'Edit employee',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Profile', [
                    _row(
                      _field(
                          label: 'Full name',
                          controller: _name,
                          required: true,
                          hint: 'e.g., Maria Santos'),
                      _statusDropdown(),
                    ),
                    const SizedBox(height: 12),
                    _row(
                      _field(
                          label: 'Email',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          hint: 'name@example.com'),
                      _field(
                          label: 'Phone',
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          hint: '+63 9XX XXX XXXX'),
                    ),
                    const SizedBox(height: 12),
                    _genderPicker(),
                    const SizedBox(height: 12),
                    _hireDatePicker(),
                  ]),
                  const SizedBox(height: 18),
                  _section('Access & role', [
                    _needsPin
                        ? _row(_roleDropdown(), _pinField())
                        : _roleDropdown(),
                  ]),
                  const SizedBox(height: 18),
                  _lockedPortalSection(),
                  const SizedBox(height: 18),
                  _section('Pay & employment', [
                    _row(_employmentTypeDropdown(), _compensationDropdown()),
                    const SizedBox(height: 12),
                    _rateFieldForCompType(),
                    if (_templateForType != null) ...[
                      const SizedBox(height: 6),
                      _templateHint(),
                    ],
                  ]),
                  const SizedBox(height: 18),
                  _section('Weekly schedule', [_scheduleEditor()]),
                  const SizedBox(height: 18),
                  _section('Requirements', [_documentsEditor()]),
                  const SizedBox(height: 18),
                  _section('Notes', [_notesField()]),
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
                child: Text(widget.initial == null
                    ? 'Add employee'
                    : 'Save changes'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── pieces ─────────────────────────────────────────────────────────

  Widget _section(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: YFont.caption().copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: YColor.brandDeep,
              )),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b),
        ],
      );

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool required = false,
    TextInputType? keyboardType,
    int? maxLines = 1,
  }) {
    return KeyboardAccessoryField(
      controller: controller,
      label: required ? '$label *' : label,
      accessoryLabel: label.toUpperCase(),
      hint: hint,
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      fillColor: YColor.surface1,
      borderColor: YColor.hairline,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _genderPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GENDER',
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            )),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final g in Gender.values) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(YRadius.md),
                  onTap: () => setState(() => _gender = g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _gender == g
                          ? YColor.brand.withValues(alpha: 0.08)
                          : YColor.surface1,
                      borderRadius: BorderRadius.circular(YRadius.md),
                      border: Border.all(
                        color: _gender == g ? YColor.brand : YColor.hairline,
                        width: _gender == g ? 1.4 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Icon(g.icon,
                          size: 22,
                          color: _gender == g
                              ? YColor.brand
                              : YColor.brandDeep),
                      const SizedBox(width: 8),
                      Text(g.label,
                          style: YFont.bodyStrong().copyWith(fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              if (g != Gender.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
      ],
    );
  }

  Widget _hireDatePicker() {
    final months = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final label =
        '${months[_hireDate.month - 1]} ${_hireDate.day}, ${_hireDate.year}';
    return _dropdownWrap(
      label: 'Hire date',
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _hireDate,
            firstDate: DateTime(2015),
            lastDate: DateTime.now().add(const Duration(days: 30)),
          );
          if (picked != null) setState(() => _hireDate = picked);
        },
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 16, color: YColor.inkMuted),
          const SizedBox(width: 8),
          Text(label,
              style: YFont.bodyStrong().copyWith(fontSize: 13)),
          const Spacer(),
          const Icon(Icons.expand_more,
              size: 18, color: YColor.inkMuted),
        ]),
      ),
    );
  }

  Widget _statusDropdown() {
    return _themedDropdown<EmployeeStatus>(
      label: 'Status',
      value: _status,
      items: EmployeeStatus.values,
      labelOf: (v) => v.label,
      onChanged: (v) => setState(() => _status = v!),
    );
  }

  Widget _roleDropdown() {
    final roles = context.watch<AppState>().employeeRoles;
    return _themedDropdown<String?>(
      label: 'Role',
      value: _roleId,
      items: roles.map((r) => r.id).toList(),
      labelOf: (id) {
        if (id == null) return 'Pick a role';
        for (final r in roles) {
          if (r.id == id) return r.name;
        }
        return 'Pick a role';
      },
      hint: roles.isEmpty
          ? 'Add a role in Maintenance → Roles first'
          : null,
      onChanged: (id) {
        setState(() {
          _roleId = id;
          if (!_needsPin) _pin.text = '';
        });
      },
    );
  }

  Widget _pinField() {
    final isEdit = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyboardAccessoryField(
          controller: _pin,
          label: isEdit ? 'PIN (leave blank to keep)' : 'PIN *',
          accessoryLabel: 'PIN',
          hint: '4 to 8 digits',
          obscure: !_showPin,
          keyboardType: TextInputType.number,
          fillColor: YColor.surface1,
          borderColor: YColor.hairline,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          onChanged: (_) => setState(() {}),
          suffix: IconButton(
            icon: Icon(
              _showPin
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: YColor.inkMuted,
            ),
            onPressed: () => setState(() => _showPin = !_showPin),
          ),
        ),
        if (!_pinValid && _pin.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'PIN must be 4 to 8 digits.',
              style: YFont.caption().copyWith(color: YColor.danger),
            ),
          ),
      ],
    );
  }

  Widget _lockedPortalSection() {
    return Stack(children: [
      Opacity(
        opacity: 0.55,
        child: AbsorbPointer(
          absorbing: true,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Text('EMPLOYEE PORTAL ACCOUNT',
                      style: YFont.caption().copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: YColor.brandDeep,
                      )),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: YColor.inkMuted.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('COMING SOON',
                        style: YFont.caption().copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: YColor.inkMuted,
                        )),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  'Lets the employee log in to a self-serve portal — schedule, payslips, document uploads. Disabled until the portal is built.',
                  style: YFont.caption(),
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Icon(Icons.lock_outline,
                size: 28, color: YColor.inkMuted.withValues(alpha: 0.5)),
          ),
        ),
      ),
    ]);
  }

  Widget _employmentTypeDropdown() {
    return _themedDropdown<EmploymentType>(
      label: 'Employment type',
      value: _employmentType,
      items: EmploymentType.values,
      labelOf: (v) => v.label,
      onChanged: (v) {
        if (v == null) return;
        setState(() => _employmentType = v);
        // Apply the template's defaults — only for new employees so we
        // don't clobber a manager's manual rate edit on an existing record.
        _applyTemplateForType(v);
      },
    );
  }

  Widget _compensationDropdown() {
    return _themedDropdown<CompensationType>(
      label: 'Compensation',
      value: _compensationType,
      items: CompensationType.values,
      labelOf: (v) => v.label,
      onChanged: (v) => setState(() => _compensationType = v!),
    );
  }

  Widget _hourlyRateField() => _field(
        label: 'Hourly rate (₱)',
        controller: _hourlyRate,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        hint: 'e.g., 140',
      );

  Widget _dailyRateField() => _field(
        label: 'Daily rate (₱)',
        controller: _dailyRate,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        hint: 'e.g., 800',
      );

  Widget _monthlySalaryField() => _field(
        label: 'Monthly salary (₱)',
        controller: _monthlySalary,
        keyboardType: TextInputType.number,
        hint: 'e.g., 28000',
      );

  /// Picks the right rate field based on the chosen compensation type so
  /// only one is visible at a time (no half-empty form noise).
  Widget _rateFieldForCompType() => switch (_compensationType) {
        CompensationType.hourly => _hourlyRateField(),
        CompensationType.daily => _dailyRateField(),
        CompensationType.salaried => _monthlySalaryField(),
      };

  /// The template (if any) tied to the currently selected employment type —
  /// used to surface a "from {type} template" hint under the rate field.
  EmploymentTemplate? get _templateForType =>
      context.read<AppState>().templateFor(_employmentType);

  Widget _templateHint() {
    final tpl = _templateForType!;
    final label = switch (tpl.employmentType) {
      EmploymentType.fullTime => 'Full-time',
      EmploymentType.partTime => 'Part-time',
      EmploymentType.contract => 'Contract',
      EmploymentType.seasonal => 'Seasonal',
    };
    return Row(children: [
      Icon(Icons.auto_awesome_outlined,
          size: 14, color: YColor.brandDeep.withValues(alpha: 0.7)),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          'Pre-filled from the $label template — edit anytime. Defaults: '
          '${tpl.compensationType.label}, OT ×${tpl.overtimeMultiplier.toStringAsFixed(2)}.',
          style: YFont.caption(),
        ),
      ),
    ]);
  }

  Widget _notesField() => _field(
        label: 'Notes',
        controller: _notes,
        maxLines: 3,
        hint: 'Anything HR should know.',
      );

  // ── Themed dropdown widget (rounded surface, brand chevron) ────────

  Widget _dropdownWrap({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            )),
        const SizedBox(height: 6),
        Container(
          // Match KeyboardAccessoryField sizing — DropdownButton already
          // enforces a 48px min interactive height internally, so adding
          // vertical padding here was double-counting and made the tile
          // visibly taller than the adjacent text fields.
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _themedDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
    String? hint,
  }) {
    return _dropdownWrap(
      label: label,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : null,
          hint: Text(
            hint ?? 'Pick',
            style: YFont.bodyStrong()
                .copyWith(fontSize: 13, color: YColor.inkMuted),
          ),
          isExpanded: true,
          icon: const Icon(Icons.expand_more,
              size: 18, color: YColor.inkMuted),
          dropdownColor: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          style: YFont.bodyStrong().copyWith(fontSize: 13),
          items: items
              .map((it) => DropdownMenuItem<T>(
                    value: it,
                    child: Text(
                      labelOf(it),
                      style: YFont.bodyStrong().copyWith(fontSize: 13),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ── Weekly schedule editor ─────────────────────────────────────────

  Widget _scheduleEditor() {
    final byDay = <int, WorkShift>{
      for (final s in _schedule) s.weekday: s,
    };
    return Column(
      children: [
        for (var w = 1; w <= 7; w++) _scheduleRow(w, byDay[w]),
      ],
    );
  }

  Widget _scheduleRow(int weekday, WorkShift? shift) {
    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final has = shift != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 100,
          child: Text(dayNames[weekday - 1],
              style: YFont.bodyStrong().copyWith(fontSize: 13)),
        ),
        if (!has) ...[
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _schedule.add(WorkShift(
                    weekday: weekday, start: '09:00', end: '17:00'));
              });
            },
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add shift'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.brand,
              side: const BorderSide(color: YColor.hairline),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ] else ...[
          Expanded(child: _timeChip(weekday, 'start', shift.start)),
          const SizedBox(width: 8),
          Text('to', style: YFont.caption()),
          const SizedBox(width: 8),
          Expanded(child: _timeChip(weekday, 'end', shift.end)),
          IconButton(
            iconSize: 16,
            color: YColor.inkMuted,
            onPressed: () {
              setState(() {
                _schedule.removeWhere((s) => s.weekday == weekday);
                _shiftCtrls.remove('${weekday}_start')?.dispose();
                _shiftCtrls.remove('${weekday}_end')?.dispose();
              });
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ]),
    );
  }

  Widget _timeChip(int weekday, String which, String current) {
    return InkWell(
      borderRadius: BorderRadius.circular(YRadius.md),
      onTap: () async {
        final parts = current.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
        );
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (ctx, child) {
            // Force 12-hour clock with AM/PM regardless of device locale.
            return MediaQuery(
              data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
        if (picked == null) return;
        final hh = picked.hour.toString().padLeft(2, '0');
        final mm = picked.minute.toString().padLeft(2, '0');
        setState(() {
          final i = _schedule.indexWhere((s) => s.weekday == weekday);
          if (i >= 0) {
            if (which == 'start') {
              _schedule[i].start = '$hh:$mm';
            } else {
              _schedule[i].end = '$hh:$mm';
            }
          }
          _shiftCtrl(weekday, which, '$hh:$mm').text = '$hh:$mm';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(children: [
          const Icon(Icons.schedule_outlined,
              size: 14, color: YColor.inkMuted),
          const SizedBox(width: 6),
          Text(_formatAmPm(current),
              style: YFont.bodyStrong().copyWith(fontSize: 13)),
        ]),
      ),
    );
  }

  String _formatAmPm(String hhmm) {
    final parts = hhmm.split(':');
    final h24 = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final isPm = h24 >= 12;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final mm = m.toString().padLeft(2, '0');
    return '$h12:$mm ${isPm ? 'PM' : 'AM'}';
  }

  // ── Documents editor ───────────────────────────────────────────────

  Widget _documentsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_documents.isEmpty)
          Text('No documents yet. Add one to track ID, contract, etc.',
              style: YFont.caption()),
        for (var i = 0; i < _documents.length; i++) _docRow(i),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _documents.add(EmployeeDocument(name: ''));
            }),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add document'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.brand,
              side: const BorderSide(color: YColor.hairline),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _docRow(int i) {
    final d = _documents[i];
    final ctrl = _docNameCtrl(d.id, d.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: KeyboardAccessoryField(
            controller: ctrl,
            accessoryLabel: 'DOCUMENT NAME',
            hint: 'e.g., Government ID',
            fillColor: YColor.surface1,
            borderColor: YColor.hairline,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onChanged: (v) {
              d.name = v;
              setState(() {});
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 180,
          child: _themedDropdown<DocumentStatus>(
            label: 'Status',
            value: d.status,
            items: DocumentStatus.values,
            labelOf: (v) => v.label,
            onChanged: (v) {
              setState(() => d.status = v!);
            },
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _documents.removeAt(i);
              _docCtrls.remove(d.id)?.dispose();
            });
          },
          icon: const Icon(Icons.delete_outline,
              size: 18, color: YColor.inkMuted),
        ),
      ]),
    );
  }
}
