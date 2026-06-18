import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../data/supabase_client.dart';
// `Member` (legacy gold-tier loyalty mock) is hidden so it doesn't collide
// with the real Members-feature model in member.dart.
import '../../models/employee.dart' hide Member;
import '../../models/payroll.dart';
import '../../models/payroll_rules.dart';

/// Owns the HR domain (employees, employee roles, leave types, employment
/// templates, payroll rules, time entries, payroll runs), extracted from the
/// monolithic [AppState] so that the rest of the app watching AppState no
/// longer rebuilds when an employee or payroll row changes.
///
/// AppState owns a single instance ([AppState.hr]) and drives its lifecycle:
///  - [hydrateCore]  — roles/employees/payrollRules/leaveTypes/templates on
///    tenant restore (the data the LOGIN/PIN flow reads).
///  - [hydratePayrollCache] — time-entries + payroll-runs into the per-tenant
///    maps.
///  - [ensureTenant] — initialises the per-tenant cache maps for a tenant.
///  - [reset] — on sign-out / tenant switch.
///
/// The Supabase calls, sorting, and notify timing are identical to what
/// AppState used to do inline. The auth/PIN/permission code stays on AppState
/// and READS [employees] / [employeeRoles] / [roleById] from this store.
class HrStore extends ChangeNotifier {
  /// The active tenant DB id, set by [hydrateCore]. All mutations are scoped
  /// to this tenant. `null` means no store is selected (signed out / no
  /// tenant). Mirrors what AppState called `_currentTenantDbId`.
  String? _tenantId;

  /// In-memory cache key (the local `Tenant.id`, NOT the DB id) used to index
  /// the per-tenant time-entry / payroll-run maps. AppState keeps this in
  /// sync with its active store via [setCacheKey] so the [timeEntries] /
  /// [payrollRuns] getters resolve the right tenant's cache — exactly the
  /// `tenant.id` the old AppState getters used.
  String? _cacheKey;

  /// Sets the active in-memory cache key (the current store's local id) so
  /// [timeEntries] / [payrollRuns] return that tenant's slice of the maps.
  void setCacheKey(String? cacheKey) {
    _cacheKey = cacheKey;
  }

  // ───── employee roles (Supabase-backed; Maintenance → Roles) ─────

  /// Cached list of roles for the active tenant. Populated by [hydrateCore];
  /// mutated by the role CRUD methods.
  List<EmployeeRole> _employeeRoles = [];
  List<EmployeeRole> get employeeRoles => List.unmodifiable(_employeeRoles);

  EmployeeRole? roleById(String? id) {
    if (id == null) return null;
    for (final r in _employeeRoles) {
      if (r.id == id) return r;
    }
    return null;
  }

  // ───── employees (Supabase-backed) ─────

  List<Employee> _employees = [];
  List<Employee> get employees => List.unmodifiable(_employees);

  // ───── payroll rules + leave types + employment templates ─────────

  PayrollRules _payrollRules = PayrollRules();
  PayrollRules get payrollRules => _payrollRules;

  List<LeaveType> _leaveTypes = [];
  List<LeaveType> get leaveTypes => List.unmodifiable(_leaveTypes);

  List<EmploymentTemplate> _employmentTemplates = [];
  List<EmploymentTemplate> get employmentTemplates =>
      List.unmodifiable(_employmentTemplates);

  // Per-tenant payroll state. Keyed by the in-memory Tenant.id so switching
  // stores keeps each store's books separate.
  final Map<String, List<TimeEntry>> _timeEntriesByTenant = {};
  final Map<String, List<PayrollRun>> _payrollRunsByTenant = {};

  List<TimeEntry> get timeEntries {
    final key = _cacheKey;
    if (key == null) return const [];
    return _timeEntriesByTenant.putIfAbsent(key, () => <TimeEntry>[]);
  }

  List<PayrollRun> get payrollRuns {
    final key = _cacheKey;
    if (key == null) return const [];
    return _payrollRunsByTenant.putIfAbsent(key, () => <PayrollRun>[]);
  }

  /// Convenience for the Add Employee modal: returns the template that
  /// matches an employment type, or null if the owner deleted/never had one.
  EmploymentTemplate? templateFor(EmploymentType t) {
    for (final tpl in _employmentTemplates) {
      if (tpl.employmentType == t) return tpl;
    }
    return null;
  }

  // ───── lifecycle ─────

  /// Loads roles/employees/payrollRules/leaveTypes/templates for [tenantId]
  /// from Supabase, then notifies. Called by AppState during tenant
  /// hydration (the same five concurrent fetches it used to run inline). This
  /// is the HR data the LOGIN/PIN flow reads, so it lands before login.
  Future<void> hydrateCore(String tenantId) async {
    _tenantId = tenantId;
    final tid = tenantId as Object;
    await Future.wait<void>([
      () async {
        final roleRows = await supabase
            .from('employee_roles')
            .select(
                'id, name, icon_name, permissions, requires_pin, is_system, sort_order')
            .eq('tenant_id', tid)
            .order('sort_order');
        _employeeRoles = (roleRows as List)
            .map((r) => EmployeeRole.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
      () async {
        final empRows = await supabase
            .from('employees')
            .select('*, role:employee_roles(id, name)')
            .eq('tenant_id', tid)
            .order('created_at');
        _employees = (empRows as List).map((r) {
          final row = r as Map<String, dynamic>;
          final joined = row['role'] as Map<String, dynamic>?;
          return Employee.fromRow(row, roleRow: joined);
        }).toList();
      }(),
      () async {
        final rulesRow = await supabase
            .from('payroll_rules')
            .select('*')
            .eq('tenant_id', tid)
            .maybeSingle();
        _payrollRules = rulesRow == null
            ? PayrollRules()
            : PayrollRules.fromRow(rulesRow);
      }(),
      () async {
        final ltRows = await supabase
            .from('leave_types')
            .select('*')
            .eq('tenant_id', tid)
            .order('sort_order');
        _leaveTypes = (ltRows as List)
            .map((r) => LeaveType.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
      () async {
        final tplRows = await supabase
            .from('employment_templates')
            .select('*')
            .eq('tenant_id', tid)
            .order('employment_type');
        _employmentTemplates = (tplRows as List)
            .map((r) => EmploymentTemplate.fromRow(r as Map<String, dynamic>))
            .toList();
      }(),
    ]);
    notifyListeners();
  }

  /// Loads time entries + payroll runs for the active tenant into the
  /// per-tenant maps and notifies. [tenantDbId] scopes the Supabase queries;
  /// [cacheKey] is the in-memory Tenant.id the maps are indexed by (matches
  /// what AppState used to use). Called after [hydrateCore].
  Future<void> hydratePayrollCache(String tenantDbId, String cacheKey) async {
    _cacheKey = cacheKey;
    final teRows = await supabase
        .from('time_entries')
        .select('*')
        .eq('tenant_id', tenantDbId)
        .order('entry_date', ascending: false)
        .limit(2000);
    _timeEntriesByTenant[cacheKey] = (teRows as List)
        .map((r) => TimeEntry.fromRow(r as Map<String, dynamic>))
        .toList();

    final runRows = await supabase
        .from('payroll_runs')
        .select(
            'id, tenant_id, period_start, period_end, kind, status, '
            'paid_at, created_at, '
            'payslips(id, employee_id, employee_name, employee_role, '
            'compensation_type, hours_worked, hourly_rate, daily_rate, '
            'monthly_salary, bonus, deductions, sss, philhealth, pagibig, '
            'ot_hours, undertime_hours, late_minutes, ot_multiplier, '
            'deduct_undertime)')
        .eq('tenant_id', tenantDbId)
        .order('period_start', ascending: false)
        .limit(60);
    _payrollRunsByTenant[cacheKey] = (runRows as List).map((r) {
      final row = r as Map<String, dynamic>;
      final slipsRaw = (row['payslips'] as List? ?? const []);
      final slips = slipsRaw
          .map((s) => Payslip.fromRow(s as Map<String, dynamic>)
            ..regularHoursPerDay = _payrollRules.regularHoursPerDay)
          .toList();
      return PayrollRun.fromRow(row, slips: slips);
    }).toList();
    notifyListeners();
  }

  /// Ensures the per-tenant maps have an entry for [cacheKey] (the in-memory
  /// Tenant.id). Called when a tenant is added/initialised so its books start
  /// empty rather than absent.
  void ensureTenant(String cacheKey) {
    _timeEntriesByTenant[cacheKey] ??= [];
    _payrollRunsByTenant[cacheKey] ??= [];
  }

  /// Clears the active-tenant HR view (sign-out / tenant switch). Mirrors the
  /// old AppState reset: clears the current-tenant lists and resets payroll
  /// rules to defaults. The per-tenant maps are keyed by tenant so they're
  /// left intact (a tenant switch re-points the cache key), matching the
  /// original behaviour which never wiped those maps on sign-out.
  void reset() {
    _tenantId = null;
    _cacheKey = null;
    _employees = [];
    _employeeRoles = [];
    _payrollRules = PayrollRules();
    _leaveTypes = [];
    _employmentTemplates = [];
    notifyListeners();
  }

  // ───── employee roles CRUD ─────

  /// Seeds Owner / Cashier / Inventory Manager for a freshly created tenant.
  /// Idempotent — relies on the unique(tenant_id, name) constraint to no-op
  /// if defaults already exist (e.g. from the SQL backfill).
  Future<void> seedDefaultEmployeeRoles(String tenantId) async {
    Future<void> insertRole({
      required String name,
      required String iconName,
      required List<String> permissions,
      required bool requiresPin,
      required int sortOrder,
    }) async {
      await supabase.from('employee_roles').insert({
        'tenant_id': tenantId,
        'name': name,
        'icon_name': iconName,
        'permissions': permissions,
        'requires_pin': requiresPin,
        'is_system': true,
        'sort_order': sortOrder,
      });
    }

    try {
      await insertRole(
        name: 'Owner',
        iconName: 'admin_panel_settings_outlined',
        permissions: const [
          'dashboard', 'sell', 'bookings', 'sessions', 'members',
          'orders', 'reports', 'employees', 'payroll', 'products',
          'inventory', 'maintenance', 'settings', 'authorize_refunds',
          'switch_branch',
        ],
        requiresPin: true,
        sortOrder: 10,
      );
      // Manager — can run the floor and authorize voids/refunds, but can't
      // touch payroll/employees/settings. 'authorize_refunds' is the
      // permission that lets a PIN approve a void/refund at the till.
      await insertRole(
        name: 'Manager',
        iconName: 'badge_outlined',
        permissions: const [
          'dashboard', 'sell', 'orders', 'reports', 'inventory',
          'products', 'authorize_refunds',
        ],
        requiresPin: true,
        sortOrder: 15,
      );
      await insertRole(
        name: 'Cashier',
        iconName: 'point_of_sale_outlined',
        permissions: const ['sell', 'orders'],
        requiresPin: true,
        sortOrder: 20,
      );
      await insertRole(
        name: 'Inventory Manager',
        iconName: 'inventory_2_outlined',
        permissions: const ['inventory', 'products'],
        requiresPin: false,
        sortOrder: 30,
      );
    } on sb.PostgrestException catch (e) {
      // 23505 = unique violation — defaults already seeded (e.g. SQL
      // backfill ran). Silently skip.
      if (e.code != '23505' && kDebugMode) {
        debugPrint('Seed default employee roles failed: ${e.message}');
      }
    }
  }

  /// Seeds payroll_rules + default leave types + employment_templates for
  /// a freshly created tenant. Same defaults the SQL backfill uses. Each
  /// insert is wrapped in its own try/catch so a 23505 (already-present)
  /// for one block doesn't skip the others.
  Future<void> seedDefaultPayrollSurface(String tenantId) async {
    try {
      await supabase.from('payroll_rules').insert({'tenant_id': tenantId});
    } on sb.PostgrestException catch (e) {
      if (e.code != '23505' && kDebugMode) {
        debugPrint('Seed payroll_rules failed: ${e.message}');
      }
    }

    String? silId, vlId, slId;
    try {
      final rows = await supabase.from('leave_types').insert([
        {
          'tenant_id': tenantId,
          'name': 'Service Incentive Leave',
          'emoji': '🌴',
          'icon_name': 'park_outlined',
          'annual_days': 5,
          'paid': true,
          'notes': 'Mandatory PH SIL — convertible to cash if unused.',
          'sort_order': 10,
          'is_system': true,
        },
        {
          'tenant_id': tenantId,
          'name': 'Vacation Leave',
          'emoji': '🏖',
          'icon_name': 'beach_access_outlined',
          'annual_days': 10,
          'paid': true,
          'notes': '',
          'sort_order': 20,
          'is_system': true,
        },
        {
          'tenant_id': tenantId,
          'name': 'Sick Leave',
          'emoji': '🤒',
          'icon_name': 'sick_outlined',
          'annual_days': 7,
          'paid': true,
          'notes': '',
          'sort_order': 30,
          'is_system': true,
        },
      ]).select('id, name');
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        switch (m['name']) {
          case 'Service Incentive Leave':
            silId = m['id'] as String;
          case 'Vacation Leave':
            vlId = m['id'] as String;
          case 'Sick Leave':
            slId = m['id'] as String;
        }
      }
    } on sb.PostgrestException catch (e) {
      if (e.code != '23505' && kDebugMode) {
        debugPrint('Seed leave_types failed: ${e.message}');
      }
    }

    try {
      await supabase.from('employment_templates').insert([
        {
          'tenant_id': tenantId,
          'employment_type': 'full_time',
          'compensation_type': 'salaried',
          'default_monthly_salary_cents': 2800000,
          'overtime_multiplier': 1.25,
          'leave_type_ids': [silId, vlId, slId].whereType<String>().toList(),
        },
        {
          'tenant_id': tenantId,
          'employment_type': 'part_time',
          'compensation_type': 'hourly',
          'default_hourly_rate_cents': 12000,
          'overtime_multiplier': 1.25,
          'leave_type_ids': [silId].whereType<String>().toList(),
        },
        {
          'tenant_id': tenantId,
          'employment_type': 'contract',
          'compensation_type': 'daily',
          'default_daily_rate_cents': 80000,
          'overtime_multiplier': 1.25,
          'leave_type_ids': [silId].whereType<String>().toList(),
        },
        {
          'tenant_id': tenantId,
          'employment_type': 'seasonal',
          'compensation_type': 'hourly',
          'default_hourly_rate_cents': 11000,
          'overtime_multiplier': 1.25,
          'leave_type_ids': const <String>[],
        },
      ]);
    } on sb.PostgrestException catch (e) {
      if (e.code != '23505' && kDebugMode) {
        debugPrint('Seed employment_templates failed: ${e.message}');
      }
    }
  }

  Future<String?> addEmployeeRole(EmployeeRole r) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (r.name.trim().isEmpty) return 'Role name is required.';
    try {
      final row = await supabase
          .from('employee_roles')
          .insert({
            'tenant_id': tenantId,
            'name': r.name.trim(),
            'icon_name': r.iconName,
            'permissions': r.permissions.toList(),
            'requires_pin': r.requiresPin,
            'is_system': false,
            'sort_order': r.sortOrder,
          })
          .select(
              'id, name, icon_name, permissions, requires_pin, is_system, sort_order')
          .single();
      _employeeRoles.add(EmployeeRole.fromRow(row));
      _employeeRoles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A role named "${r.name}" already exists.';
      }
      return 'Could not add role: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateEmployeeRole(EmployeeRole updated) async {
    if (_tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Role name is required.';
    try {
      await supabase.from('employee_roles').update({
        'name': updated.name.trim(),
        'icon_name': updated.iconName,
        'permissions': updated.permissions.toList(),
        'requires_pin': updated.requiresPin,
        'sort_order': updated.sortOrder,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);
      final i = _employeeRoles.indexWhere((r) => r.id == updated.id);
      if (i >= 0) {
        _employeeRoles[i] = updated;
        _employeeRoles.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      // Refresh denormalized role names on any employees holding this role.
      for (final emp in _employees) {
        if (emp.roleId == updated.id) emp.role = updated.name.trim();
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A role named "${updated.name}" already exists.';
      }
      return 'Could not update role: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeEmployeeRole(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('employee_roles').delete().eq('id', id);
      _employeeRoles.removeWhere((x) => x.id == id);
      // Employees that held this role now have role_id = null (FK ON
      // DELETE SET NULL). Clear the denormalized name too.
      for (final emp in _employees) {
        if (emp.roleId == id) {
          emp.roleId = null;
          emp.role = '';
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete role: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── employees CRUD ─────

  /// Builds the row payload for insert/update. PIN is intentionally NOT
  /// included here — cashier PINs are set via the [setCashierPin] RPC, never
  /// stored as plaintext on the employees row.
  Map<String, dynamic> _employeeRowPayload(Employee e, String tenantId) => {
        'tenant_id': tenantId,
        'role_id': e.roleId,
        'name': e.name.trim(),
        'gender': e.gender.dbValue,
        'email': e.email.trim(),
        'phone': e.phone.trim(),
        'hire_date': e.hireDate.toIso8601String().substring(0, 10),
        'status': e.status.dbValue,
        'employment_type': e.employmentType.dbValue,
        'compensation_type': e.compensationType.dbValue,
        'hourly_rate_cents': (e.hourlyRate * 100).round(),
        'daily_rate_cents': (e.dailyRate * 100).round(),
        'monthly_salary_cents': (e.monthlySalary * 100).round(),
        'sss_cents': (e.sssContribution * 100).round(),
        'philhealth_cents': (e.philHealthContribution * 100).round(),
        'pagibig_cents': (e.pagIbigContribution * 100).round(),
        'branch_ids': e.branchIds.toList(),
        'schedule': e.schedule.map((s) => s.toJson()).toList(),
        'documents': e.documents.map((d) => d.toJson()).toList(),
        'portal_enabled': e.portalEnabled,
        'portal_gmail': e.portalGmail.trim(),
        'portal_username': e.portalUsername.trim(),
        'notes': e.notes,
      };

  /// Inserts the employee and, if [cashierPin] is supplied (only for roles
  /// where [EmployeeRole.requiresPin] is true), sets it via the bcrypt RPC.
  /// Returns null on success, or a user-safe error message.
  Future<String?> addEmployee(Employee e, {String? cashierPin}) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (e.name.trim().isEmpty) return 'Employee name is required.';
    try {
      final row = await supabase
          .from('employees')
          .insert(_employeeRowPayload(e, tenantId))
          .select('*, role:employee_roles(id, name)')
          .single();
      final saved = Employee.fromRow(row,
          roleRow: row['role'] as Map<String, dynamic>?);
      _employees.add(saved);
      notifyListeners();

      if (cashierPin != null && cashierPin.isNotEmpty) {
        final pinErr = await setCashierPin(saved.id, cashierPin);
        if (pinErr != null) return pinErr;
      }
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not add employee: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateEmployee(Employee updated, {String? cashierPin}) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Employee name is required.';
    try {
      final row = await supabase
          .from('employees')
          .update(_employeeRowPayload(updated, tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id)
          .select('*, role:employee_roles(id, name)')
          .single();
      final saved = Employee.fromRow(row,
          roleRow: row['role'] as Map<String, dynamic>?);
      final i = _employees.indexWhere((x) => x.id == saved.id);
      if (i >= 0) _employees[i] = saved;
      notifyListeners();

      if (cashierPin != null && cashierPin.isNotEmpty) {
        final pinErr = await setCashierPin(saved.id, cashierPin);
        if (pinErr != null) return pinErr;
      }
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update employee: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeEmployee(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('employees').delete().eq('id', id);
      _employees.removeWhere((e) => e.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete employee: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Stores a bcrypt-hashed PIN for a cashier-role employee. Returns null on
  /// success. Mirrors `setOwnerPin` — 4–8 digits, atomic upsert.
  Future<String?> setCashierPin(String employeeId, String pin) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    final p = pin.trim();
    if (p.length < 4 || p.length > 8 ||
        !RegExp(r'^[0-9]+$').hasMatch(p)) {
      return 'Cashier PIN must be 4–8 digits.';
    }
    try {
      await supabase.rpc('set_cashier_pin', params: {
        'p_tenant_id': tenantId,
        'p_employee_id': employeeId,
        'p_pin': p,
      });
      // Keep an owner-visible plaintext copy in sync with the hash.
      await supabase
          .from('employees')
          .update({'cashier_pin': p}).eq('id', employeeId);
      final i = _employees.indexWhere((x) => x.id == employeeId);
      if (i >= 0) _employees[i].cashierPin = p;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // The server raises a `PIN_TAKEN:` prefixed error when the PIN
      // collides with another user (owner or another cashier) inside the
      // tenant. Strip the marker for a clean toast.
      if (e.message.contains('PIN_TAKEN')) {
        return e.message.replaceFirst('PIN_TAKEN: ', '');
      }
      return 'Could not save PIN: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── payroll rules + leave types + employment templates CRUD ─────

  Future<String?> updatePayrollRules(PayrollRules updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('payroll_rules')
          .update(updated.toRow()
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('tenant_id', tenantId);
      _payrollRules = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update rules: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> addLeaveType(LeaveType lt) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (lt.name.trim().isEmpty) return 'Leave type name is required.';
    try {
      final row = await supabase
          .from('leave_types')
          .insert({
            'tenant_id': tenantId,
            'name': lt.name.trim(),
            'emoji': lt.emoji,
            'icon_name': lt.iconName,
            'annual_days': lt.annualDays,
            'paid': lt.paid,
            'notes': lt.notes,
            'sort_order': lt.sortOrder,
          })
          .select('*')
          .single();
      _leaveTypes.add(LeaveType.fromRow(row));
      _leaveTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A leave type named "${lt.name}" already exists.';
      }
      return 'Could not add leave type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateLeaveType(LeaveType updated) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('leave_types').update({
        'name': updated.name.trim(),
        'emoji': updated.emoji,
        'icon_name': updated.iconName,
        'annual_days': updated.annualDays,
        'paid': updated.paid,
        'notes': updated.notes,
        'sort_order': updated.sortOrder,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);
      final i = _leaveTypes.indexWhere((l) => l.id == updated.id);
      if (i >= 0) _leaveTypes[i] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update leave type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeLeaveType(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('leave_types').delete().eq('id', id);
      _leaveTypes.removeWhere((l) => l.id == id);
      // Drop from any templates referencing it.
      for (final tpl in _employmentTemplates) {
        tpl.leaveTypeIds.remove(id);
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete leave type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateEmploymentTemplate(EmploymentTemplate t) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('employment_templates')
          .update(t.toRow(tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', t.id);
      final i = _employmentTemplates.indexWhere((x) => x.id == t.id);
      if (i >= 0) _employmentTemplates[i] = t;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update template: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── payroll (Supabase-backed) ────────────────────────────────
  //
  // Three tables: `time_entries`, `payroll_runs`, `payslips`. Tenant-
  // scoped via RLS, so every query just filters by tenant_id and
  // trusts the policy. The in-memory maps remain as the local cache the
  // UI binds to — server writes update both DB and cache so the UI
  // repaints immediately while persistence happens in the background.

  /// Hours logged for [employeeId] between [from] (inclusive) and [to]
  /// (inclusive).
  double hoursIn(String employeeId, DateTime from, DateTime to) {
    final fromD = DateTime(from.year, from.month, from.day);
    final toD = DateTime(to.year, to.month, to.day);
    return timeEntries
        .where((e) =>
            e.employeeId == employeeId &&
            !e.date.isBefore(fromD) &&
            !e.date.isAfter(toD))
        .fold(0.0, (acc, e) => acc + e.hours);
  }

  /// Insert / update / delete a single day's hours for an employee.
  /// Returns null on success, a user-safe error message otherwise.
  /// Persistence happens BEFORE the local cache is touched so a
  /// failed write doesn't silently corrupt the UI.
  Future<String?> upsertTimeEntry({
    required String employeeId,
    required DateTime date,
    required double hours,
    String? notes,
  }) async {
    final key = _cacheKey;
    final tenantId = _tenantId;
    if (key == null || tenantId == null) return 'No store selected.';
    final day = DateTime(date.year, date.month, date.day);
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final list =
        _timeEntriesByTenant.putIfAbsent(key, () => <TimeEntry>[]);
    final idx = list.indexWhere((e) =>
        e.employeeId == employeeId &&
        e.date.year == day.year &&
        e.date.month == day.month &&
        e.date.day == day.day);

    try {
      if (hours <= 0) {
        // Zero hours = delete the row. Lets the cashier "clear" a
        // shift without having to type 0.0 in two places.
        if (idx >= 0) {
          await supabase
              .from('time_entries')
              .delete()
              .eq('id', list[idx].id);
          list.removeAt(idx);
        }
      } else {
        // Upsert keyed on (employee_id, entry_date) — relies on the
        // unique index added in the migration.
        final row = await supabase
            .from('time_entries')
            .upsert(
              {
                'tenant_id': tenantId,
                'employee_id': employeeId,
                'entry_date': dateStr,
                'hours': hours,
                'notes':
                    (notes ?? '').isEmpty ? null : notes,
              },
              onConflict: 'employee_id,entry_date',
            )
            .select('*')
            .single();
        final fresh = TimeEntry.fromRow(row);
        if (idx >= 0) {
          list[idx] = fresh;
        } else {
          list.add(fresh);
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not save hours: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Pulls actual hours from attendance into the timesheet for [start]..[end]
  /// (inclusive). Calls the server bridge (sync_attendance_to_timesheet) which
  /// applies the schedule-aware engine + premiums, then re-hydrates the local
  /// time-entries cache so the grid + pay run reflect it immediately.
  Future<({int count, String? error})> syncTimesheetFromAttendance(
      DateTime start, DateTime end) async {
    final key = _cacheKey;
    final tenantId = _tenantId;
    if (key == null || tenantId == null) {
      return (count: 0, error: 'No store selected.');
    }
    String d(DateTime x) => '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    try {
      final res = await supabase.rpc('sync_attendance_to_timesheet',
          params: {'p_start': d(start), 'p_end': d(end)});
      final count = (res as int?) ?? 0;
      final teRows = await supabase
          .from('time_entries')
          .select('*')
          .eq('tenant_id', tenantId)
          .order('entry_date', ascending: false)
          .limit(2000);
      _timeEntriesByTenant[key] = (teRows as List)
          .map((r) => TimeEntry.fromRow(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
      return (count: count, error: null);
    } on sb.PostgrestException catch (e) {
      return (count: 0, error: e.message);
    } catch (_) {
      return (count: 0, error: 'Could not reach the server. Please try again.');
    }
  }

  /// Fetch one employee's itemized daily time record for a period — the
  /// per-day rows + totals (regular/OT/undertime/late) from the server's
  /// schedule-aware engine. Powers the payslip DTR drill-down.
  Future<Map<String, dynamic>?> fetchEmployeeDtr(
      String employeeId, DateTime start, DateTime end) async {
    String ymd(DateTime x) => '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    try {
      final res = await supabase.rpc('payroll_dtr_period', params: {
        'p_employee': employeeId,
        'p_start': ymd(start),
        'p_end': ymd(end),
      });
      if (res is Map) return Map<String, dynamic>.from(res);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Build a fresh payroll run snapshot for the given period. Pulls
  /// each active employee's hours from [timeEntries] and freezes
  /// their rate / salary at the time of generation. The run + each
  /// slip persist to the DB so the period closes cleanly.
  Future<({PayrollRun? run, String? error})> generatePayrollRun({
    required DateTime start,
    required DateTime end,
    required PayPeriodKind kind,
  }) async {
    final key = _cacheKey;
    final tenantId = _tenantId;
    if (key == null || tenantId == null) {
      return (run: null, error: 'No store selected.');
    }
    // Guard against spamming duplicate runs: if an unpaid run already covers
    // this exact period, send the owner to it instead of stacking copies.
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final existing = _payrollRunsByTenant[key]?.where((r) =>
        r.kind == kind &&
        r.status != PayrollStatus.paid &&
        sameDay(r.periodStart, start) &&
        sameDay(r.periodEnd, end));
    if (existing != null && existing.isNotEmpty) {
      return (
        run: existing.first,
        error: 'A run for this period already exists — opening it instead. '
            'Delete it first if you want to regenerate.'
      );
    }
    final slips = <Payslip>[];
    for (final emp in _employees) {
      if (emp.status == EmployeeStatus.terminated) continue;
      slips.add(await _buildSlip(emp, start, end));
    }
    final draft = PayrollRun(
      periodStart: start,
      periodEnd: end,
      kind: kind,
      slips: slips,
    );
    try {
      // Insert the run header first to get its server-side id.
      // We don't trust the model's local id since the DB DEFAULT is
      // authoritative — wins on conflicts across devices.
      final runRow = await supabase
          .from('payroll_runs')
          .insert(draft.toRowPayload(tenantId))
          .select('*')
          .single();
      final runId = runRow['id'] as String;
      // Bulk-insert all slips against the new run id.
      final slipPayloads = slips
          .map((s) => s.toRowPayload(
              tenantId: tenantId, payrollRunId: runId))
          .toList();
      final slipRows = slipPayloads.isEmpty
          ? <Map<String, dynamic>>[]
          : (await supabase
                  .from('payslips')
                  .insert(slipPayloads)
                  .select('*'))
              .cast<Map<String, dynamic>>();
      final hydrated = PayrollRun.fromRow(
        runRow,
        slips: slipRows
            .map((s) => Payslip.fromRow(s)
              ..regularHoursPerDay = _payrollRules.regularHoursPerDay)
            .toList(),
      );
      _payrollRunsByTenant
          .putIfAbsent(key, () => <PayrollRun>[])
          .insert(0, hydrated);
      notifyListeners();
      return (run: hydrated, error: null);
    } on sb.PostgrestException catch (e) {
      return (run: null, error: 'Could not generate run: ${e.message}');
    } catch (_) {
      return (run: null, error: 'Could not reach the server. Please try again.');
    }
  }

  /// Build one fresh payslip snapshot for [emp] over the period — pulls
  /// itemized hours/OT/undertime from attendance (falling back to the manual
  /// timesheet grid when there are no punches) and freezes the CURRENT rates +
  /// statutory + rules. [bonus]/[deductions]/[id] let a re-generate preserve
  /// the owner's manual edits and the existing payslip row id.
  Future<Payslip> _buildSlip(
    Employee emp,
    DateTime start,
    DateTime end, {
    double bonus = 0,
    double deductions = 0,
    String? id,
  }) async {
    String ymd(DateTime x) => '${x.year.toString().padLeft(4, '0')}-'
        '${x.month.toString().padLeft(2, '0')}-'
        '${x.day.toString().padLeft(2, '0')}';
    double baseHrs = hoursIn(emp.id, start, end);
    double otHrs = 0, utHrs = 0;
    int lateMin = 0;
    try {
      final dtr = await supabase.rpc('payroll_dtr_period', params: {
        'p_employee': emp.id,
        'p_start': ymd(start),
        'p_end': ymd(end),
      });
      if (dtr is Map && ((dtr['days_present'] as int?) ?? 0) > 0) {
        baseHrs = ((dtr['regular_hours'] as num?) ?? 0).toDouble();
        otHrs = ((dtr['ot_hours'] as num?) ?? 0).toDouble();
        utHrs = ((dtr['undertime_hours'] as num?) ?? 0).toDouble();
        lateMin = (dtr['late_minutes'] as int?) ?? 0;
      }
    } catch (_) {
      // Network/RPC hiccup — keep the grid hours as the base.
    }
    return Payslip(
      id: id,
      employeeId: emp.id,
      employeeName: emp.name,
      employeeRole: emp.role,
      compensationType: emp.compensationType,
      hoursWorked: baseHrs,
      hourlyRate: emp.hourlyRate,
      dailyRate: emp.dailyRate,
      monthlySalary: emp.monthlySalary,
      bonus: bonus,
      deductions: deductions,
      // Itemized statutory — snapshot the employee's monthly amounts, but only
      // the ones the tenant has switched on. Pro-rated by pay frequency at net.
      sss: _payrollRules.deductSSS ? emp.sssContribution : 0,
      philHealth:
          _payrollRules.deductPhilHealth ? emp.philHealthContribution : 0,
      pagIbig: _payrollRules.deductPagIBIG ? emp.pagIbigContribution : 0,
      regularHoursPerDay: _payrollRules.regularHoursPerDay,
      otHours: otHrs,
      undertimeHours: utHrs,
      lateMinutes: lateMin,
      otMultiplier:
          templateFor(emp.employmentType)?.overtimeMultiplier ?? 1.25,
      deductUndertime: _payrollRules.deductUndertime,
    );
  }

  /// Re-snapshot an existing (unpaid) run from CURRENT data — refreshes hours,
  /// OT/undertime, rates and statutory while KEEPING each employee's manually
  /// entered bonus + deductions. Replaces the run's payslips in place so any
  /// edits to employee statutory / rates / time entries flow through.
  Future<String?> regeneratePayrollRun(String runId) async {
    final key = _cacheKey;
    final tenantId = _tenantId;
    if (key == null || tenantId == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[key];
    if (runs == null) return 'No payroll runs yet.';
    final ri = runs.indexWhere((r) => r.id == runId);
    if (ri < 0) return 'That payroll run no longer exists.';
    final run = runs[ri];
    if (run.status != PayrollStatus.draft) {
      return 'This run is ${run.status.label.toLowerCase()} — re-generate '
          'only works on a draft. Set it back to Draft first.';
    }
    // Keep the owner's manual bonus / deductions, matched per employee.
    final prevByEmp = {for (final s in run.slips) s.employeeId: s};
    final fresh = <Payslip>[];
    for (final emp in _employees) {
      if (emp.status == EmployeeStatus.terminated) continue;
      final prev = prevByEmp[emp.id];
      fresh.add(await _buildSlip(
        emp,
        run.periodStart,
        run.periodEnd,
        bonus: prev?.bonus ?? 0,
        deductions: prev?.deductions ?? 0,
      ));
    }
    try {
      // Swap the slips: drop the old rows, insert the refreshed set.
      await supabase.from('payslips').delete().eq('payroll_run_id', runId);
      final payloads = fresh
          .map((s) =>
              s.toRowPayload(tenantId: tenantId, payrollRunId: runId))
          .toList();
      final rows = payloads.isEmpty
          ? <Map<String, dynamic>>[]
          : (await supabase.from('payslips').insert(payloads).select('*'))
              .cast<Map<String, dynamic>>();
      run.slips = rows
          .map((s) => Payslip.fromRow(s)
            ..regularHoursPerDay = _payrollRules.regularHoursPerDay)
          .toList();
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not re-generate: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Persist edits to a single payslip (bonus / deductions / hours
  /// override). The DB row is the source of truth; the cache mirrors
  /// it. Refuses to write once the parent run is marked paid.
  Future<String?> updatePayslip(String runId, Payslip updated) async {
    final key = _cacheKey;
    if (key == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[key];
    if (runs == null) return 'No payroll runs yet.';
    final ri = runs.indexWhere((r) => r.id == runId);
    if (ri < 0) return 'That payroll run no longer exists.';
    if (runs[ri].status == PayrollStatus.paid) {
      return 'This run is already paid — payslips can\'t be edited.';
    }
    try {
      await supabase
          .from('payslips')
          .update({
            'hours_worked': updated.hoursWorked,
            'hourly_rate': updated.hourlyRate,
            'daily_rate': updated.dailyRate,
            'monthly_salary': updated.monthlySalary,
            'bonus': updated.bonus,
            'deductions': updated.deductions,
            'sss': updated.sss,
            'philhealth': updated.philHealth,
            'pagibig': updated.pagIbig,
            'ot_hours': updated.otHours,
            'undertime_hours': updated.undertimeHours,
            'late_minutes': updated.lateMinutes,
            'ot_multiplier': updated.otMultiplier,
            'deduct_undertime': updated.deductUndertime,
          })
          .eq('id', updated.id);
      final si = runs[ri].slips.indexWhere((s) => s.id == updated.id);
      if (si >= 0) runs[ri].slips[si] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not save payslip: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> setPayrollStatus(
      String runId, PayrollStatus status) async {
    final key = _cacheKey;
    if (key == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[key];
    if (runs == null) return 'No payroll runs yet.';
    final i = runs.indexWhere((r) => r.id == runId);
    if (i < 0) return 'That payroll run no longer exists.';
    final paidAt =
        status == PayrollStatus.paid ? DateTime.now() : null;
    try {
      await supabase
          .from('payroll_runs')
          .update({
            'status': status.dbValue,
            'paid_at': paidAt?.toUtc().toIso8601String(),
          })
          .eq('id', runId);
      runs[i].status = status;
      if (paidAt != null) runs[i].paidAt = paidAt;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update status: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removePayrollRun(String runId) async {
    final key = _cacheKey;
    if (key == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[key];
    if (runs == null) return 'No payroll runs yet.';
    try {
      // Cascading FK deletes the slips automatically.
      await supabase.from('payroll_runs').delete().eq('id', runId);
      runs.removeWhere((r) => r.id == runId);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not remove run: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }
}
