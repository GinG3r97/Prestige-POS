import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/stores/hr_store.dart';
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
  late final TextEditingController _sss;
  late final TextEditingController _philHealth;
  late final TextEditingController _pagIbig;
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

  /// Wizard step (0 = Profile, 1 = Access & pay, 2 = Schedule & docs).
  int _step = 0;
  static const _stepTitles = ['Profile', 'Salary', 'Schedule & docs'];
  final ScrollController _scrollC = ScrollController();

  /// Name of the account already using the typed PIN (null = free).
  String? _pinDupName;
  bool _pinChecking = false;
  late EmploymentType _employmentType;
  late CompensationType _compensationType;
  late DateTime _hireDate;
  late List<WorkShift> _schedule;
  late List<EmployeeDocument> _documents;
  bool _showPin = true;
  bool _portalEnabled = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _name = TextEditingController(text: e?.name ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    // Pre-fill with the existing PIN so the owner can see / tweak it.
    _pin = TextEditingController(text: e?.cashierPin ?? '');
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
    // Statutory deductions auto-fill from the monthly salary in real time.
    _monthlySalary.addListener(_syncStatutoryFromSalary);
    _sss = TextEditingController(
        text: e == null || e.sssContribution == 0
            ? ''
            : e.sssContribution.toStringAsFixed(0));
    _philHealth = TextEditingController(
        text: e == null || e.philHealthContribution == 0
            ? ''
            : e.philHealthContribution.toStringAsFixed(0));
    _pagIbig = TextEditingController(
        text: e == null || e.pagIbigContribution == 0
            ? ''
            : e.pagIbigContribution.toStringAsFixed(0));
    _notes = TextEditingController(text: e?.notes ?? '');
    _portalEnabled = e?.portalEnabled ?? false;

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
        // Don't overwrite a rate the owner may have typed before this frame.
        if (mounted) _applyTemplateForType(_employmentType, overwrite: false);
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
    _monthlySalary.removeListener(_syncStatutoryFromSalary);
    _monthlySalary.dispose();
    _sss.dispose();
    _philHealth.dispose();
    _pagIbig.dispose();
    _notes.dispose();
    for (final c in _shiftCtrls.values) {
      c.dispose();
    }
    for (final c in _docCtrls.values) {
      c.dispose();
    }
    _scrollC.dispose();
    super.dispose();
  }

  /// Change wizard step and snap the content back to the top.
  void _setStep(int i) {
    setState(() => _step = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) _scrollC.jumpTo(0);
    });
  }

  void _onPinChanged(String v) {
    setState(() {});
    final p = v.trim();
    if (_needsPin && p.length == 4) {
      _checkPinDup(p);
    } else if (_pinDupName != null || _pinChecking) {
      setState(() {
        _pinDupName = null;
        _pinChecking = false;
      });
    }
  }

  Future<void> _checkPinDup(String pin) async {
    setState(() => _pinChecking = true);
    final name = await context
        .read<AppState>()
        .pinConflictName(pin, excludeId: widget.initial?.id);
    if (!mounted || _pin.text.trim() != pin) return;
    setState(() {
      _pinDupName = name;
      _pinChecking = false;
    });
  }

  /// Apply the matching employment template for [t] — pre-fills compensation
  /// type + rate from Maintenance → Payroll. Only fires for new employees:
  /// editing an existing employee keeps their saved overrides intact, since
  /// pulling the template would silently overwrite the owner's manual edits.
  void _applyTemplateForType(EmploymentType t, {bool overwrite = true}) {
    if (widget.initial != null) return;
    final tpl = context.read<HrStore>().templateFor(t);
    if (tpl == null) return;
    setState(() {
      _compensationType = tpl.compensationType;
      // When [overwrite] is false (initial pre-fill), keep anything the owner
      // already typed; only fill empty rate fields.
      if (overwrite || _hourlyRate.text.isEmpty) {
        _hourlyRate.text = tpl.defaultHourlyRate == 0
            ? ''
            : tpl.defaultHourlyRate.toStringAsFixed(0);
      }
      if (overwrite || _dailyRate.text.isEmpty) {
        _dailyRate.text = tpl.defaultDailyRate == 0
            ? ''
            : tpl.defaultDailyRate.toStringAsFixed(0);
      }
      if (overwrite || _monthlySalary.text.isEmpty) {
        _monthlySalary.text = tpl.defaultMonthlySalary == 0
            ? ''
            : tpl.defaultMonthlySalary.toStringAsFixed(0);
      }
    });
  }

  EmployeeRole? get _selectedRole {
    if (_roleId == null) return null;
    final roles = context.read<HrStore>().employeeRoles;
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
    // Exactly 4 digits, and not already used by another account.
    return v.length == 4 && int.tryParse(v) != null && _pinDupName == null;
  }

  bool get _profileValid =>
      _name.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _phone.text.trim().isNotEmpty;

  bool get _canSave => _profileValid && _roleId != null && _pinValid;

  /// Per-step gates for the Next button.
  bool get _step1Valid => _profileValid;
  bool get _step2Valid => _roleId != null && _pinValid;
  bool _stepValid(int i) => switch (i) {
        0 => _step1Valid,
        1 => _step2Valid,
        _ => true,
      };

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
      sssContribution: double.tryParse(_sss.text) ?? 0,
      philHealthContribution: double.tryParse(_philHealth.text) ?? 0,
      pagIbigContribution: double.tryParse(_pagIbig.text) ?? 0,
      schedule: _schedule,
      documents: _documents,
      // Employee Portal: owner enables + sets the login email.
      portalEnabled: _portalEnabled,
      // The employee's own email is their portal login (no separate field).
      portalGmail: _email.text.trim(),
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
          _stepBar(),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollC,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step == 0) ...[
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
                            required: true,
                            keyboardType: TextInputType.emailAddress,
                            hint: 'name@example.com'),
                        _field(
                            label: 'Phone',
                            controller: _phone,
                            required: true,
                            keyboardType: TextInputType.phone,
                            hint: '+63 9XX XXX XXXX'),
                      ),
                      const SizedBox(height: 12),
                      _genderPicker(),
                      const SizedBox(height: 12),
                      // Hire date | Employee Portal toggle side by side.
                      _row(_hireDatePicker(), _portalToggle()),
                    ]),
                    const SizedBox(height: 18),
                    _section('Access & role', [
                      _needsPin
                          ? _row(_roleDropdown(), _pinField())
                          : _roleDropdown(),
                    ]),
                  ],
                  if (_step == 1) ...[
                    // Salary | Statutory side by side, 3 rows each column.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _salarySection()),
                        const SizedBox(width: 18),
                        Expanded(child: _statutorySection()),
                      ],
                    ),
                  ],
                  if (_step == 2) ...[
                    // Weekly schedule + Requirements side by side.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child:
                              _section('Weekly schedule', [_scheduleEditor()]),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child:
                              _section('Requirements', [_documentsEditor()]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _section('Notes', [_notesField()]),
                  ],
                ],
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [
              if (_step > 0)
                TextButton.icon(
                  onPressed: () => _setStep(_step - 1),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Back'),
                ),
              const Spacer(),
              if (_step < _stepTitles.length - 1)
                ElevatedButton(
                  onPressed: _stepValid(_step)
                      ? () => _setStep(_step + 1)
                      : null,
                  style: _primaryBtnStyle(),
                  child: const Text('Next'),
                )
              else
                ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  style: _primaryBtnStyle(),
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

  ButtonStyle _primaryBtnStyle() => ElevatedButton.styleFrom(
        backgroundColor: YColor.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.md)),
      );

  /// Step indicator — number above label, connector line between steps.
  Widget _stepBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.only(top: 11, left: 10, right: 10),
                  color: i <= _step ? YColor.brand : YColor.hairline,
                ),
              ),
            GestureDetector(
              onTap: () {
                if (i <= _step || _stepValid(_step)) _setStep(i);
              },
              behavior: HitTestBehavior.opaque,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i <= _step ? YColor.brand : YColor.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: i <= _step ? YColor.brand : YColor.hairline),
                  ),
                  child: i < _step
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}',
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 12,
                            color:
                                i <= _step ? Colors.white : YColor.inkMuted,
                          )),
                ),
                const SizedBox(height: 3),
                Text(_stepTitles[i],
                    style: YFont.caption().copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: i == _step ? YColor.brandDeep : YColor.inkMuted,
                    )),
              ]),
            ),
          ],
            ],
          ),
        ),
      ),
    );
  }

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
        onTap: _pickHireDate,
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

  /// Wheel date picker in a bottom sheet — no text field, so the keyboard never
  /// shows. We also unfocus before AND after so a focused field (e.g. phone)
  /// can't re-open its keyboard accessory when the sheet restores focus.
  Future<void> _pickHireDate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    DateTime temp = _hireDate;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: YColor.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Text('Hire date',
                  style: YFont.titleMD().copyWith(fontSize: 17)),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx, temp),
                style: TextButton.styleFrom(foregroundColor: YColor.brand),
                child: const Text('Done',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          SizedBox(
            height: 230,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                textTheme: CupertinoTextThemeData(
                  dateTimePickerTextStyle:
                      YFont.bodyStrong().copyWith(fontSize: 19),
                ),
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _hireDate,
                minimumDate: DateTime(2015),
                maximumDate: DateTime.now().add(const Duration(days: 30)),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (picked != null) setState(() => _hireDate = picked);
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
    final roles = context.watch<HrStore>().employeeRoles;
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
          label: isEdit ? 'PIN' : 'PIN *',
          accessoryLabel: 'PIN',
          hint: '4 digits',
          obscure: !_showPin,
          keyboardType: TextInputType.number,
          maxLength: 4,
          fillColor: YColor.surface1,
          borderColor: YColor.hairline,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          onChanged: _onPinChanged,
          suffix: _pinChecking
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
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
        if (_pinDupName != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'This PIN is already used by $_pinDupName. Pick another.',
              style: YFont.caption().copyWith(color: YColor.danger),
            ),
          )
        else if (_needsPin &&
            _pin.text.isNotEmpty &&
            (_pin.text.trim().length != 4 ||
                int.tryParse(_pin.text.trim()) == null))
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'PIN must be exactly 4 digits.',
              style: YFont.caption().copyWith(color: YColor.danger),
            ),
          ),
      ],
    );
  }

  /// Compact portal toggle beside the hire date. No login email — the
  /// employee's own Email is their portal login. The label + switch sit on the
  /// label line (lining up with the other field labels); a single input-height
  /// badge shows the compact login detail with the status anchored right.
  Widget _portalToggle() {
    final loggedIn = widget.initial?.portalLastLoginAt != null;
    final email = _email.text.trim();
    final (statusLabel, statusColor) = !_portalEnabled
        ? ('Off', YColor.inkMuted)
        : loggedIn
            ? ('Active', YColor.success)
            : ('Pending', YColor.brandDeep);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label line — matches the other field labels; switch anchored right.
        SizedBox(
          height: 17,
          child: Row(children: [
            Text('EMPLOYEE PORTAL',
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: YColor.brandDeep,
                )),
            const Spacer(),
            Transform.scale(
              scale: 0.72,
              alignment: Alignment.centerRight,
              child: Switch(
                value: _portalEnabled,
                activeColor: YColor.brand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => _portalEnabled = v),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _portalEnabled
                ? YColor.brandTint.withValues(alpha: 0.45)
                : YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(children: [
            Icon(Icons.login,
                size: 15,
                color: _portalEnabled ? YColor.brandDeep : YColor.inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: _portalEnabled
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email.isEmpty ? 'Set the Email above' : email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.bodyStrong().copyWith(fontSize: 12)),
                        Text('pos…/portal · one-time code',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.caption().copyWith(
                                fontSize: 10, color: YColor.inkSubtle)),
                      ],
                    )
                  : Text('Web access off',
                      style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(statusLabel,
                  style: YFont.caption().copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: statusColor)),
            ),
          ]),
        ),
      ],
    );
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

  /// Statutory deductions — three editable monthly peso fields plus a
  /// "Compute from salary" shortcut that fills them from [phStatutory].
  /// Mirrors the [_section] container styling but adds a subtitle and a
  /// trailing action beside the title.
  /// Salary column — 3 stacked rows: employment type, compensation, rate.
  Widget _salarySection() {
    return _section('Salary', [
      _employmentTypeDropdown(),
      const SizedBox(height: 12),
      _compensationDropdown(),
      const SizedBox(height: 12),
      _rateFieldForCompType(),
      if (_templateForType != null) ...[
        const SizedBox(height: 6),
        _templateHint(),
      ],
    ]);
  }

  /// Statutory column — 3 stacked rows: SSS, PhilHealth, Pag-IBIG.
  Widget _statutorySection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('STATUTORY DEDUCTIONS',
                  style: YFont.caption().copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: YColor.brandDeep,
                  )),
            ),
            TextButton.icon(
              onPressed: _computeStatutory,
              icon: const Icon(Icons.auto_awesome_outlined, size: 14),
              label: const Text('Compute'),
              style: TextButton.styleFrom(
                foregroundColor: YColor.brand,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: YFont.caption()
                    .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _field(
            label: 'SSS (₱)',
            controller: _sss,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: 'e.g., 900',
          ),
          const SizedBox(height: 12),
          _field(
            label: 'PhilHealth (₱)',
            controller: _philHealth,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: 'e.g., 700',
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Pag-IBIG (₱)',
            controller: _pagIbig,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hint: 'e.g., 200',
          ),
        ],
      ),
    );
  }

  /// Live recompute when the monthly salary changes (real-time auto-fill).
  void _syncStatutoryFromSalary() {
    if (mounted) _computeStatutory();
  }

  /// Reads the monthly-salary field, runs [phStatutory], and fills the three
  /// contribution fields. Hourly/daily employees have no monthly-salary field
  /// shown, so we just use whatever is in that controller (0 if blank).
  void _computeStatutory() {
    final salary = double.tryParse(_monthlySalary.text) ?? 0;
    final s = phStatutory(salary);
    setState(() {
      _sss.text = s.sss == 0 ? '' : s.sss.toStringAsFixed(0);
      _philHealth.text =
          s.philHealth == 0 ? '' : s.philHealth.toStringAsFixed(0);
      _pagIbig.text = s.pagIbig == 0 ? '' : s.pagIbig.toStringAsFixed(0);
    });
  }

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
      context.read<HrStore>().templateFor(_employmentType);

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
    final day = dayNames[weekday - 1];
    if (shift == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(
            width: 100,
            child: Text(day,
                style: YFont.bodyStrong().copyWith(fontSize: 13)),
          ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day name + Remove anchored top-right.
          Row(children: [
            Expanded(
              child: Text(day,
                  style: YFont.bodyStrong().copyWith(fontSize: 13)),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _schedule.removeWhere((s) => s.weekday == weekday);
                  _shiftCtrls.remove('${weekday}_start')?.dispose();
                  _shiftCtrls.remove('${weekday}_end')?.dispose();
                });
              },
              child: Text('Remove',
                  style: YFont.caption().copyWith(
                      color: YColor.danger, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _timeChip(weekday, 'start', shift.start)),
            const SizedBox(width: 8),
            Text('to', style: YFont.caption()),
            const SizedBox(width: 8),
            Expanded(child: _timeChip(weekday, 'end', shift.end)),
          ]),
        ],
      ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Remove anchored top-right.
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _documents.removeAt(i);
                  _docCtrls.remove(d.id)?.dispose();
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Text('Remove',
                    style: YFont.caption().copyWith(
                        color: YColor.danger, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: KeyboardAccessoryField(
                controller: ctrl,
                label: 'Document',
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
              width: 150,
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
          ]),
        ],
      ),
    );
  }
}
