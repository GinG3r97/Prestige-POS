import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/responsive.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../widgets/push_toast.dart';
import 'employee_form_dialog.dart';

class EmployeesView extends StatefulWidget {
  const EmployeesView({super.key});

  @override
  State<EmployeesView> createState() => _EmployeesViewState();
}

class _EmployeesViewState extends State<EmployeesView> {
  String? _selectedId;
  String _query = '';
  String? _roleFilter;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final employees = state.employees;
    final filtered = _filtered(employees);

    // Filter chips show every role defined for this tenant (in maintenance
    // sort order), plus any leftover role name still attached to an
    // employee whose role was deleted.
    final tenantRoles = state.employeeRoles.map((r) => r.name).toList();
    final usedRoles = employees.map((e) => e.role).where((r) => r.isNotEmpty).toSet();
    final availableRoles = [
      ...tenantRoles,
      ...usedRoles.where((r) => !tenantRoles.contains(r)),
    ];

    // If the active role filter no longer exists, drop it.
    if (_roleFilter != null && !availableRoles.contains(_roleFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _roleFilter = null);
      });
    }

    final selected = _selectedId == null
        ? null
        : employees.where((e) => e.id == _selectedId).firstOrNull;

    return Container(
      color: YColor.surface2,
      child: Row(
        children: [
          // List pane
          SizedBox(
            width: panelWidth(context, fraction: 0.30, min: 300, max: 360),
            child: _ListPane(
              employees: filtered,
              total: employees.length,
              activeCount: employees
                  .where((e) => e.status == EmployeeStatus.active)
                  .length,
              selectedId: _selectedId,
              query: _query,
              roleFilter: _roleFilter,
              availableRoles: availableRoles,
              onSearch: (q) => setState(() => _query = q),
              onRoleFilter: (r) => setState(() => _roleFilter = r),
              onSelect: (id) => setState(() => _selectedId = id),
              onAdd: () => _openForm(context, state, null),
            ),
          ),
          Container(width: 0.5, color: YColor.hairline),
          Expanded(
            child: selected == null
                ? const _EmptyDetail()
                : _DetailPane(
                    employee: selected,
                    onEdit: () => _openForm(context, state, selected),
                    onRemove: () => _confirmRemove(context, state, selected),
                  ),
          ),
        ],
      ),
    );
  }

  List<Employee> _filtered(List<Employee> all) {
    var result = all;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((e) {
        return e.name.toLowerCase().contains(q) ||
            e.role.toLowerCase().contains(q) ||
            e.email.toLowerCase().contains(q);
      }).toList();
    }
    if (_roleFilter != null) {
      result = result.where((e) => e.role == _roleFilter).toList();
    }
    return result;
  }

  Future<void> _openForm(
      BuildContext context, AppState state, Employee? existing) async {
    final result = await showDialog<EmployeeFormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EmployeeFormDialog(initial: existing),
    );
    if (result == null || !mounted) return;
    final err = existing == null
        ? await state.addEmployee(result.employee,
            cashierPin: result.cashierPin)
        : await state.updateEmployee(result.employee,
            cashierPin: result.cashierPin);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    if (existing == null) setState(() => _selectedId = result.employee.id);
    PushToast.show(
      context,
      title: existing == null ? 'Employee added' : 'Employee updated',
      subtitle: result.employee.name,
      leadingIcon: result.employee.gender.icon,
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState state, Employee e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove ${e.name}?'),
        content: const Text(
          'This removes the employee from this store. Sales history is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await state.removeEmployee(e.id);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    setState(() => _selectedId = null);
    PushToast.show(
      context,
      title: 'Employee removed',
      subtitle: e.name,
      leadingIcon: Icons.person_remove,
    );
  }
}

// ───── List pane ─────

class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.employees,
    required this.total,
    required this.activeCount,
    required this.selectedId,
    required this.query,
    required this.roleFilter,
    required this.availableRoles,
    required this.onSearch,
    required this.onRoleFilter,
    required this.onSelect,
    required this.onAdd,
  });

  final List<Employee> employees;
  final int total;
  final int activeCount;
  final String? selectedId;
  final String query;
  final String? roleFilter;
  final List<String> availableRoles;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onRoleFilter;
  final ValueChanged<String> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColor.surface1,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Employees',
                      style: YFont.titleLG().copyWith(fontSize: 22)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  '$activeCount active · ${total - activeCount} inactive',
                  style: YFont.caption(),
                ),
              ],
            ),
          ),
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search by name, role, PIN…',
                hintStyle:
                    YFont.body().copyWith(color: YColor.inkSubtle),
                filled: true,
                fillColor: YColor.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(YRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Role chips — only roles in use
          if (availableRoles.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _roleChip(null, 'All'),
                  ...availableRoles.map((r) => _roleChip(r, r)),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Container(height: 0.5, color: YColor.hairline),
          // List
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        query.isEmpty && roleFilter == null
                            ? 'No employees yet.\nTap Add to invite your team.'
                            : 'No matches for your filters.',
                        textAlign: TextAlign.center,
                        style: YFont.caption(),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: employees.length,
                    separatorBuilder: (_, __) =>
                        Container(height: 0.5, color: YColor.hairline),
                    itemBuilder: (_, i) {
                      final e = employees[i];
                      final selected = e.id == selectedId;
                      return _ListRow(
                        employee: e,
                        selected: selected,
                        onTap: () => onSelect(e.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String? role, String label) {
    final selected = roleFilter == role;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onRoleFilter(role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: YFont.bodyStrong().copyWith(
                color: selected ? Colors.white : YColor.ink,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.employee,
    required this.selected,
    required this.onTap,
  });

  final Employee employee;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? YColor.brandTint.withValues(alpha: 0.4) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(employee.gender.icon,
                  size: 24, color: YColor.brandDeep),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        employee.name,
                        style: YFont.bodyStrong(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (employee.status != EmployeeStatus.active)
                      _StatusDot(status: employee.status),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    employee.role,
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final EmployeeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      EmployeeStatus.onLeave => ('LEAVE', YColor.brandDeep),
      EmployeeStatus.terminated => ('OFF', YColor.danger),
      EmployeeStatus.active => ('', YColor.success),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

// ───── Empty detail ─────

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: YColor.surface3,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.badge_outlined,
                size: 38, color: YColor.inkMuted),
          ),
          const SizedBox(height: 14),
          Text('Select an employee',
              style: YFont.titleMD().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 4),
          Text('Choose someone on the left to see their details',
              style: YFont.caption()),
        ],
      ),
    );
  }
}

// ───── Detail pane ─────

class _DetailPane extends StatefulWidget {
  const _DetailPane({
    required this.employee,
    required this.onEdit,
    required this.onRemove,
  });
  final Employee employee;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  State<_DetailPane> createState() => _DetailPaneState();
}

class _DetailPaneState extends State<_DetailPane> {

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(e),
              const SizedBox(height: 24),
              _profileCard(e),
              const SizedBox(height: 18),
              _accessCard(e),
              const SizedBox(height: 18),
              _portalCard(e),
              const SizedBox(height: 18),
              _payCard(e),
              const SizedBox(height: 18),
              _scheduleCard(e),
              const SizedBox(height: 18),
              _requirementsCard(e),
              if (e.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                _notesCard(e),
              ],
              const SizedBox(height: 18),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Employee e) {
    final tenure = _tenure(e.hireDate);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [YColor.brandTint, YColor.surface1],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(e.gender.icon,
                  size: 44, color: YColor.brandDeep),
            ),
            if (e.status == EmployeeStatus.active)
              Positioned(
                right: 0,
                bottom: 4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: YColor.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: YColor.surface1, width: 2.5),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    style: YFont.titleLG().copyWith(
                      fontSize: 26,
                      letterSpacing: -0.4,
                    )),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    '${e.role} · ${e.employmentType.label}',
                    style: YFont.body().copyWith(color: YColor.inkMuted),
                  ),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statusPill(e.status),
                    if (tenure.isNotEmpty)
                      _smallPill(
                        icon: Icons.workspace_premium_outlined,
                        label: tenure,
                        color: YColor.brandDeep,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(EmployeeStatus status) {
    final (color, label, icon) = switch (status) {
      EmployeeStatus.active => (YColor.success, 'Active', Icons.circle),
      EmployeeStatus.onLeave => (YColor.brandDeep, 'On Leave', Icons.pause_circle_outline),
      EmployeeStatus.terminated => (YColor.danger, 'Terminated', Icons.do_not_disturb_alt),
    };
    return _smallPill(icon: icon, label: label, color: color);
  }

  Widget _smallPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: color,
          ),
        ),
      ]),
    );
  }

  Widget _profileCard(Employee e) => _SectionCard(
        title: 'Profile',
        icon: Icons.person_outline,
        children: [
          _DetailRow(
            icon: Icons.mail_outline,
            label: 'Email',
            value: e.email.isEmpty ? '—' : e.email,
          ),
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: e.phone.isEmpty ? '—' : e.phone,
          ),
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Hire date',
            value: _formatDate(e.hireDate),
            trailing: _tenure(e.hireDate).isEmpty
                ? null
                : _smallPill(
                    icon: Icons.timer_outlined,
                    label: _tenure(e.hireDate),
                    color: YColor.brandDeep,
                  ),
          ),
        ],
      );

  Widget _accessCard(Employee e) {
    final state = context.watch<AppState>();
    final role = state.roleById(e.roleId);
    final hasPin = role?.requiresPin == true;
    return _SectionCard(
      title: 'Access',
      icon: Icons.lock_outline,
      children: [
        _DetailRow(
          icon: Icons.work_outline,
          label: 'Role',
          value: e.role.isEmpty ? '—' : e.role,
        ),
        if (hasPin)
          _DetailRow(
            icon: Icons.pin_outlined,
            label: 'Cashier PIN',
            value: 'Encrypted — set in the Edit form',
          ),
      ],
    );
  }

  Widget _portalCard(Employee e) {
    if (!e.portalEnabled) {
      return _SectionCard(
        title: 'Portal account',
        icon: Icons.account_circle_outlined,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: YColor.surface3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'NOT SET UP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: YColor.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No portal access. Edit to create an account.',
                  style: YFont.caption(),
                ),
              ),
            ]),
          ),
        ],
      );
    }
    return _SectionCard(
      title: 'Portal account',
      icon: Icons.account_circle_outlined,
      children: [
        _DetailRow(
          icon: Icons.alternate_email,
          label: 'Gmail',
          value: e.portalGmail.isEmpty ? '—' : e.portalGmail,
          trailing: _smallPill(
            icon: Icons.check_circle,
            label: 'Active',
            color: YColor.success,
          ),
        ),
        _DetailRow(
          icon: Icons.person_outline,
          label: 'Username',
          value: e.portalUsername.isEmpty ? '—' : e.portalUsername,
        ),
        _DetailRow(
          icon: Icons.lock_outline,
          label: 'Password',
          value: 'Encrypted',
        ),
        _DetailRow(
          icon: Icons.login_outlined,
          label: 'Last sign-in',
          value: e.portalLastLoginAt == null
              ? 'Never signed in'
              : _formatDate(e.portalLastLoginAt!),
        ),
      ],
    );
  }

  Widget _payCard(Employee e) {
    final amount = switch (e.compensationType) {
      CompensationType.hourly => e.hourlyRate,
      CompensationType.daily => e.dailyRate,
      CompensationType.salaried => e.monthlySalary,
    };
    final headline = '₱${amount.toStringAsFixed(2)}';
    final subtitle = switch (e.compensationType) {
      CompensationType.hourly =>
        'per hour · est. ₱${(e.hourlyRate * 8 * 22).toStringAsFixed(0)} / mo',
      CompensationType.daily =>
        'per day · est. ₱${(e.dailyRate * 22).toStringAsFixed(0)} / mo',
      CompensationType.salaried =>
        'per month · ${e.compensationType.label}',
    };
    final hasPay = amount > 0;
    return _SectionCard(
      title: 'Pay & employment',
      icon: Icons.payments_outlined,
      children: [
        if (hasPay)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: YColor.brandTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.attach_money,
                    color: YColor.brandDeep, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: YFont.titleLG().copyWith(
                        fontSize: 26,
                        color: YColor.brand,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(subtitle, style: YFont.caption()),
                  ],
                ),
              ),
            ]),
          ),
        if (hasPay)
          Container(
              height: 0.5,
              color: YColor.hairline,
              margin: const EdgeInsets.symmetric(horizontal: 16)),
        _DetailRow(
          icon: Icons.payments_outlined,
          label: 'Compensation',
          value: e.compensationType.label,
        ),
        Container(
            height: 0.5,
            color: YColor.hairline,
            margin: const EdgeInsets.symmetric(horizontal: 16)),
        _DetailRow(
          icon: Icons.work_history_outlined,
          label: 'Employment type',
          value: e.employmentType.label,
        ),
      ],
    );
  }

  String _tenure(DateTime hire) {
    final now = DateTime.now();
    int years = now.year - hire.year;
    int months = now.month - hire.month;
    if (now.day < hire.day) months -= 1;
    if (months < 0) {
      years -= 1;
      months += 12;
    }
    if (years <= 0 && months <= 0) return 'New hire';
    final parts = <String>[];
    if (years > 0) parts.add('${years}y');
    if (months > 0) parts.add('${months}mo');
    return parts.join(' ');
  }

  Widget _scheduleCard(Employee e) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return _SectionCard(
      title: 'Weekly schedule',
      icon: Icons.calendar_view_week_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            children: List.generate(7, (i) {
              final day = i + 1;
              final shift =
                  e.schedule.where((s) => s.weekday == day).firstOrNull;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: shift == null
                          ? YColor.surface2
                          : YColor.brandTint.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(YRadius.md),
                    ),
                    child: Column(
                      children: [
                        Text(
                          labels[i],
                          style: YFont.caption().copyWith(
                            color: YColor.brandDeep,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shift == null
                              ? '—'
                              : '${shift.start}\n${shift.end}',
                          textAlign: TextAlign.center,
                          style: YFont.caption().copyWith(
                            fontSize: 10,
                            height: 1.3,
                            color: shift == null
                                ? YColor.inkMuted
                                : YColor.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _requirementsCard(Employee e) => _SectionCard(
        title: 'Requirements',
        icon: Icons.task_alt_outlined,
        children: e.documents.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No documents on file.',
                      style: YFont.caption()),
                ),
              ]
            : e.documents.map(_docRow).toList(),
      );

  Widget _docRow(EmployeeDocument doc) {
    final (color, icon) = switch (doc.status) {
      DocumentStatus.approved => (YColor.success, Icons.check_circle),
      DocumentStatus.pending =>
        (YColor.brandDeep, Icons.hourglass_bottom),
      DocumentStatus.expiringSoon => (Colors.orange, Icons.warning_amber),
      DocumentStatus.missing => (YColor.danger, Icons.cancel),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(doc.name, style: YFont.bodyStrong()),
              if (doc.expiresOn != null)
                Text(
                  'Expires ${_formatDate(doc.expiresOn!)}',
                  style: YFont.caption(),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            doc.status.label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: color,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _notesCard(Employee e) => _SectionCard(
        title: 'Notes',
        icon: Icons.sticky_note_2_outlined,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(
              e.notes,
              style: YFont.body().copyWith(
                fontStyle: FontStyle.italic,
                color: YColor.inkMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      );

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Remove'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.danger,
              side: const BorderSide(color: YColor.hairline),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: widget.onEdit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit employee'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ───── Reusable card pieces ─────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Insert hairline dividers between rows (but not for non-_DetailRow content).
    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i != children.length - 1) {
        separated.add(Container(
          height: 0.5,
          color: YColor.hairline,
          margin: const EdgeInsets.symmetric(horizontal: 16),
        ));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: [
              Icon(icon, size: 14, color: YColor.brandDeep),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: YColor.brandDeep,
                ),
              ),
            ]),
          ),
          Container(
            height: 0.5,
            color: YColor.hairline,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          ...separated,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Widget? valueWidget;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: YFont.caption().copyWith(
                    color: YColor.inkMuted,
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                if (valueWidget != null)
                  valueWidget!
                else
                  Text(
                    value ?? '—',
                    style: YFont.bodyStrong().copyWith(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
