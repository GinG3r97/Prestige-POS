import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../data/supabase_client.dart';
import '../models/cart.dart';
import '../models/catalog.dart';
import '../models/held_order.dart';
import '../models/category.dart' as cat;
// `Member` (legacy gold-tier loyalty mock) is hidden so it doesn't
// collide with our real Members-feature model in member.dart.
import '../models/employee.dart' hide Member;
import '../models/inventory.dart';
import '../models/mock_data.dart';
import '../features/printing/bt_printer.dart';
import '../models/money.dart';
import '../models/order.dart' as o;
import '../models/printer_config.dart';
import '../models/shift.dart';
import '../models/payroll.dart';
import '../models/payroll_rules.dart';
import '../models/tenant.dart';
import 'stores/bookings_store.dart';
import 'stores/members_store.dart';

const _uuid = Uuid();

enum AppRoute {
  dashboard,
  sell,
  bookings,
  sessions,
  members,
  orders,
  reports,
  employees,
  payroll,
  products,
  inventory,
  /// The "More" hub — a single primary-nav tile that opens a grouped grid
  /// of secondary destinations (Reports, Staff, Payroll, Maintenance, …).
  /// Doesn't gate permissions itself; the tiles inside do.
  more,
  maintenance,
  settings,
}

class AppState extends ChangeNotifier {
  AppState() {
    // NOTE: the cart is exposed via its own CartStore provider (see main.dart)
    // so cart edits repaint only cart-watching widgets, not every
    // context.watch<AppState>() consumer. Do NOT re-add a cart->AppState
    // listener here or you reintroduce the app-wide rebuild storm.
    _bindAuth();
  }

  /// Members domain (roster + plan templates) lives in its own
  /// ChangeNotifier so member changes don't rebuild every AppState watcher.
  /// AppState owns the instance and drives its lifecycle (hydrate/reset);
  /// consumers watch this store directly via its own provider (see main.dart).
  final MembersStore members = MembersStore();

  /// Bookings domain (bookable resources + bookings/sessions) lives in its
  /// own ChangeNotifier so booking changes don't rebuild every AppState
  /// watcher. AppState owns the instance and drives its lifecycle
  /// (hydrate/reset); consumers watch this store directly via its own
  /// provider (see main.dart).
  final BookingsStore bookings = BookingsStore();

  StreamSubscription<sb.AuthState>? _authSub;

  /// Mirror Supabase auth state into our local owner model. If the user is
  /// already signed in from a prior launch (session restored from secure
  /// storage), this fires immediately with `AuthChangeEvent.initialSession`.
  void _bindAuth() {
    _syncOwnerFromSession(supabase.auth.currentSession);
    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      _syncOwnerFromSession(data.session);
    });
    // Validate the cached session against the server. If the auth user was
    // deleted (e.g. dashboard cleanup) but the device still holds a token,
    // every DB write would silently RLS-fail. Calling getUser forces a
    // server check — failure triggers signOut, which clears the token.
    _validateCachedSession();
  }

  Future<void> _validateCachedSession() async {
    if (supabase.auth.currentSession == null) return;
    try {
      await supabase.auth.getUser();
    } catch (_) {
      // Token invalid or user deleted. Clear local session so the app
      // routes the owner back to Welcome → Sign-up.
      try {
        await supabase.auth.signOut();
      } catch (_) {/* swallowed — listener fires on token clear anyway */}
    }
  }

  void _syncOwnerFromSession(sb.Session? session) {
    final user = session?.user;
    if (user == null) {
      if (currentOwner != null) {
        currentOwner = null;
        _stores.clear();
        _currentStoreIndex = 0;
        _addingStore = false;
        currentStaff = null;
        _currentTenantDbId = null;
        _ownerPinSet = false;
        _categories = [];
        _features = cat.TenantFeatures();
        _modifierGroups = [];
        _employeeRoles = [];
        _employees = [];
        _payrollRules = PayrollRules();
        _leaveTypes = [];
        _employmentTemplates = [];
        _productTypes = [];
        _products = [];
        _inventory = [];
        _inventoryCategories = [];
        _addOns = [];
        bookings.reset();
        members.reset();
        cart.clear();
        notifyListeners();
      }
      return;
    }
    final meta = user.userMetadata ?? const <String, dynamic>{};
    final displayName = (meta['display_name'] as String?)?.trim();
    final newOwner = OwnerAccount(
      id: user.id,
      email: user.email ?? '',
      password: '', // OTP-only — no password stored anywhere.
      displayName: (displayName == null || displayName.isEmpty)
          ? (user.email ?? 'Owner')
          : displayName,
      tenantId: '',
    );
    final changed = currentOwner?.id != newOwner.id ||
        currentOwner?.email != newOwner.email ||
        currentOwner?.displayName != newOwner.displayName;
    if (changed) {
      currentOwner = newOwner;
      notifyListeners();
    }
    // Re-hydrate the tenant + PIN state from Supabase on every auth change so
    // returning sessions skip onboarding and route straight to the PIN screen.
    _restoreTenantFromDb();
  }

  /// Pulls the owner's tenant + branches from Supabase and rebuilds the local
  /// [Tenant] from them. Non-DB-backed lists (products, inventory, employees,
  /// etc.) are re-seeded from [MockData] for now — they'll migrate in later
  /// turns. Also resolves [_ownerPinSet] by checking the `owner_pins` table.
  Future<void> _restoreTenantFromDb() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    // Block the auth-gated UI ("Tell us about your business" /
    // Set PIN / Login) from rendering while we figure out which screen
    // is actually correct. Without this the user briefly sees Onboarding
    // because `_stores` is empty for one notifyListeners() pulse before
    // the DB query returns.
    _isHydrating = true;
    notifyListeners();
    try {
      final tenantRows = await supabase
          .from('tenants')
          .select('id, business_name, address, currency, timezone, logo_url, '
              'receipt_header, receipt_footer, receipt_align, '
              'receipt_template, ticket_template, print_tail_lines, print_font, '
              'inventory_tracking_enabled, '
              'vat_registered, tin, branch_code, bir_min, bir_serial, '
              'ptu_number, ptu_valid_until, bir_accreditation_no')
          .eq('owner_id', user.id)
          .order('created_at', ascending: true);

      if (tenantRows.isEmpty) {
        _stores.clear();
        _currentTenantDbId = null;
        _ownerPinSet = false;
        _isHydrating = false;
        notifyListeners();
        return;
      }

      _stores.clear();
      // Fetch every store's branches in ONE query, then group — avoids an
      // N+1 query per tenant during hydration.
      final tenantIds = [for (final t in tenantRows) t['id'] as String];
      final allBranchRows = await supabase
          .from('branches')
          .select('id, name, tenant_id')
          .inFilter('tenant_id', tenantIds)
          .order('created_at');
      final branchesByTenant = <String, List<dynamic>>{};
      for (final b in allBranchRows as List) {
        (branchesByTenant[(b as Map)['tenant_id'] as String] ??= <dynamic>[])
            .add(b);
      }
      for (final t in tenantRows) {
        final branchRows = branchesByTenant[t['id'] as String] ?? const [];

        final tenantObj = Tenant(
          businessName: t['business_name'] as String,
          address: (t['address'] as String?) ?? '',
          currency: (t['currency'] as String?) ?? 'PHP',
          timezone: (t['timezone'] as String?) ?? 'Asia/Manila',
          logoUrl: t['logo_url'] as String?,
          receiptHeader: t['receipt_header'] as String?,
          receiptFooter: t['receipt_footer'] as String?,
          receiptAlign: (t['receipt_align'] as String?) ?? 'center',
          receiptTemplate: (t['receipt_template'] as int?) ?? 1,
          ticketTemplate: (t['ticket_template'] as int?) ?? 1,
          printTailLines: (t['print_tail_lines'] as int?) ?? 2,
          printFont: (t['print_font'] as String?) ?? 'a',
          inventoryTrackingEnabled:
              (t['inventory_tracking_enabled'] as bool?) ?? true,
          vatRegistered: (t['vat_registered'] as bool?) ?? false,
          tin: t['tin'] as String?,
          branchCode: (t['branch_code'] as String?) ?? '000',
          birMin: t['bir_min'] as String?,
          birSerial: t['bir_serial'] as String?,
          ptuNumber: t['ptu_number'] as String?,
          ptuValidUntil: t['ptu_valid_until'] as String?,
          birAccreditationNo: t['bir_accreditation_no'] as String?,
          branches: branchRows
              .map((b) => Branch(
                    id: b['id'] as String,
                    name: b['name'] as String,
                  ))
              .toList(),
        );
        _stores.add(tenantObj);
        // Time-tracking still pending its own DB migration; start empty
        // instead of fabricating entries against employees we no longer
        // mock-seed.
        _timeEntriesByTenant[tenantObj.id] = [];
        _payrollRunsByTenant[tenantObj.id] = [];
      }
      _currentStoreIndex = 0;
      _currentTenantDbId = tenantRows.first['id'] as String;

      // These per-tenant reads are independent of each other, so run them
      // CONCURRENTLY (was ~12 serial round-trips on every cold start). Each
      // closure does its own fetch + assignment exactly as before. Products
      // are fetched AFTER this batch because their post-processing joins
      // against _modifierGroups + _categories loaded here.
      final tid = _currentTenantDbId as Object;
      await Future.wait<void>([
        () async {
          final categoriesRes = await supabase
              .from('categories')
              .select(
                  'id, name, emoji, icon_name, sort_order, type_id, is_system, separate_sales')
              .eq('tenant_id', tid)
              .order('sort_order');
          _categories = (categoriesRes as List)
              .map((r) => cat.Category.fromRow(r as Map<String, dynamic>))
              .toList();
        }(),
        () async {
          final featRow = await supabase
              .from('tenant_features')
              .select(
                  'reserve_enabled, timer_enabled, subscribe_enabled, service_enabled')
              .eq('tenant_id', tid)
              .maybeSingle();
          _features = featRow == null
              ? cat.TenantFeatures()
              : cat.TenantFeatures.fromRow(featRow);
        }(),
        () async {
          final pinRow = await supabase
              .from('owner_pins')
              .select('tenant_id')
              .eq('tenant_id', tid)
              .maybeSingle();
          _ownerPinSet = pinRow != null;
        }(),
        () async {
          final mgRows = await supabase
              .from('modifier_groups')
              .select(
                  'id, name, emoji, icon_name, required, default_index, sort_order, is_system, '
                  'modifier_options(id, name, price_delta_cents, sort_order)')
              .eq('tenant_id', tid)
              .order('sort_order');
          _modifierGroups = (mgRows as List).map((r) {
            final row = r as Map<String, dynamic>;
            // Sort the raw rows by sort_order first (O(n log n)), then map.
            final optsRaw = [...(row['modifier_options'] as List? ?? const [])]
              ..sort((a, b) => (((a as Map)['sort_order'] as int?) ?? 0)
                  .compareTo(((b as Map)['sort_order'] as int?) ?? 0));
            final opts = optsRaw
                .map((o) => MasterOption.fromRow(o as Map<String, dynamic>))
                .toList();
            return MasterModifierGroup.fromRow(row, options: opts);
          }).toList();
        }(),
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
        () async {
          final typeRows = await supabase
              .from('product_types')
              .select('*')
              .eq('tenant_id', tid)
              .order('sort_order');
          _productTypes = (typeRows as List)
              .map((r) => ProductType.fromRow(r as Map<String, dynamic>))
              .toList();
        }(),
        () async {
          final invCatRows = await supabase
              .from('inventory_categories')
              .select('*')
              .eq('tenant_id', tid)
              .order('sort_order');
          _inventoryCategories = (invCatRows as List)
              .map((r) => InventoryCategory.fromRow(r as Map<String, dynamic>))
              .toList();
        }(),
        () async {
          final invRows = await supabase
              .from('inventory_items')
              .select('*')
              .eq('tenant_id', tid)
              .order('name');
          _inventory = (invRows as List)
              .map((r) => InventoryItem.fromRow(r as Map<String, dynamic>))
              .toList();
        }(),
      ]);

      // Products — joined with type + category for denormalized names.
      final prodRows = await supabase
          .from('products')
          .select('*, type:product_types(id, name), '
              'category:categories(id, name)')
          .eq('tenant_id', _currentTenantDbId as Object)
          .order('sort_order');
      _products = (prodRows as List).map((r) {
        final row = r as Map<String, dynamic>;
        return CafeItem.fromRow(
          row,
          typeRow: row['type'] as Map<String, dynamic>?,
          categoryRow: row['category'] as Map<String, dynamic>?,
        );
      }).toList();

      // Hydrate runtime `modifierGroups` on each product from the master
      // list so the Sell view + product detail sheet can render Size /
      // Temperature / Strength pickers without rewriting their data
      // sources. DB stores only the ids; this is the in-memory join.
      final categoriesById = {for (final c in _categories) c.id: c};
      for (final p in _products) {
        p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
        // Fall back to the category's picked icon (from the "Pick an icon"
        // modal) when the product has none — so every product shows a
        // themed outlined icon instead of a colourful emoji, consistently
        // across Sell / Orders / Products / cart.
        if ((p.iconName == null || p.iconName!.isEmpty) &&
            p.categoryId != null) {
          final c = categoriesById[p.categoryId];
          if (c != null && c.iconName != null && c.iconName!.isNotEmpty) {
            p.iconName = c.iconName;
          }
        }
      }

      // Add-ons — tenant-owned extras with per-category applicability.
      final addOnRows = await supabase
          .from('add_ons')
          .select('*')
          .eq('tenant_id', _currentTenantDbId as Object)
          .order('sort_order');
      _addOns = (addOnRows as List)
          .map((r) => AddOn.fromRow(r as Map<String, dynamic>))
          .toList();

      // Configured receipt printer (single default).
      await _loadPrinter();
      // Open cashier shift (Z-reading), if any.
      await _loadShift();
      // Parked / held orders for this store (device-local).
      await _loadHeldOrders();

      // Bookable resources (rooms, hot desks, event spaces) live in
      // BookingsStore. The actual [Booking] rows are loaded per-day on
      // demand from BookingsView.
      await bookings.hydrate(_currentTenantDbId!);

      // Member plan templates + member roster live in MembersStore.
      await members.hydrate(_currentTenantDbId!);

      // Payroll — time entries first (small, all rows), then runs
      // with their payslips nested via PostgREST so we get the
      // whole hierarchy in a single round-trip. The per-tenant
      // cache key is the in-memory Tenant id (matches what we
      // initialised at the top of this method).
      final tenantCacheId = tenant!.id;
      final teRows = await supabase
          .from('time_entries')
          .select('*')
          .eq('tenant_id', _currentTenantDbId as Object)
          .order('entry_date', ascending: false)
          .limit(2000);
      _timeEntriesByTenant[tenantCacheId] = (teRows as List)
          .map((r) => TimeEntry.fromRow(r as Map<String, dynamic>))
          .toList();

      final runRows = await supabase
          .from('payroll_runs')
          .select(
              'id, tenant_id, period_start, period_end, kind, status, '
              'paid_at, created_at, '
              'payslips(id, employee_id, employee_name, employee_role, '
              'compensation_type, hours_worked, hourly_rate, daily_rate, '
              'monthly_salary, bonus, deductions)')
          .eq('tenant_id', _currentTenantDbId as Object)
          .order('period_start', ascending: false)
          .limit(60);
      _payrollRunsByTenant[tenantCacheId] = (runRows as List).map((r) {
        final row = r as Map<String, dynamic>;
        final slipsRaw = (row['payslips'] as List? ?? const []);
        final slips = slipsRaw
            .map((s) => Payslip.fromRow(s as Map<String, dynamic>))
            .toList();
        return PayrollRun.fromRow(row, slips: slips);
      }).toList();

      _isHydrating = false;
      notifyListeners();
    } catch (e) {
      _isHydrating = false;
      notifyListeners();
      if (kDebugMode) {
        debugPrint('AppState._restoreTenantFromDb failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // Account-level (owner) auth
  OwnerAccount? currentOwner;
  final List<Tenant> _stores = [];
  int _currentStoreIndex = 0;

  /// True only while the user is going through onboarding for a NEW store
  /// (after the first one has been created). Routes them to OnboardingView.
  bool _addingStore = false;

  // Staff-level (PIN) session
  Employee? currentStaff;

  AppRoute _selectedRoute = AppRoute.dashboard;
  AppRoute get selectedRoute => _selectedRoute;
  set selectedRoute(AppRoute v) {
    if (_selectedRoute == v) return;
    _selectedRoute = v;
    notifyListeners();
  }

  bool showTender = false;

  final cart = CartStore();

  /// Email currently waiting for OTP verification. Surfaces the email on the
  /// OTP entry screen and gates which view we route to.
  String? _pendingOtpEmail;
  String? get pendingOtpEmail => _pendingOtpEmail;
  bool get isVerifyingOtp => _pendingOtpEmail != null;

  bool get hasAccount => currentOwner != null;
  bool get isAuthenticated => currentStaff != null;

  /// True while we're fetching tenant + PIN state from Supabase right after
  /// an auth change (sign-in, session restore). `main.dart` shows a
  /// "Preparing your store…" loader while this is true so the user
  /// doesn't see Onboarding flash before the PIN screen settles.
  bool _isHydrating = false;
  bool get isHydrating => _isHydrating;

  /// True for a brief window right after a successful PIN sign-in so the
  /// shell can settle (permissions filter the nav, selectedRoute snaps to
  /// the first accessible route) without the user seeing the items shuffle.
  /// main.dart shows the same "Preparing your shift…" loader during this
  /// window. Cleared by [_endPinSettling] after a short delay.
  bool _isPinSettling = false;
  bool get isPinSettling => _isPinSettling;

  void _beginPinSettling() {
    _isPinSettling = true;
    notifyListeners();
    // 2s gives the user time to register the "Welcome back…" greeting
    // and lets the cross-fade into the shell feel intentional rather
    // than a flash. Tune here if it ever feels slow.
    Future.delayed(const Duration(seconds: 2), _endPinSettling);
  }

  void _endPinSettling() {
    if (!_isPinSettling) return;
    _isPinSettling = false;
    notifyListeners();
  }

  /// True while [lockSession] is in its grace period. main.dart shows a
  /// "Locking, please wait…" loader during this window so the user sees
  /// an intentional transition rather than the shell snapping straight
  /// to the PIN keypad.
  bool _isLocking = false;
  bool get isLocking => _isLocking;

  /// True when the **PIN-pinned user** is the tenant owner (not just that
  /// there's a Supabase Auth session for the owner). When a cashier
  /// PIN-signs in, currentOwner stays set (the Supabase session belongs
  /// to the owner of the tablet) but the actively-using person is the
  /// cashier — so role gates must look at *who's pinned in*, not the
  /// auth session.
  bool get isOwnerSession =>
      currentOwner != null && currentStaff?.id == currentOwner?.id;

  /// Route keys the currently signed-in user is allowed to see. The tenant
  /// owner always gets every route — even if they (accidentally or
  /// deliberately) trim the Owner role's permissions in Maintenance, they
  /// shouldn't be able to lock themselves out of their own store. Staff
  /// holding any other role get exactly what's on that role.
  Set<String> get currentPermissions {
    if (isOwnerSession) {
      return AppRoute.values.map((r) => r.name).toSet();
    }
    final role = roleById(currentStaff?.roleId);
    return role?.permissions ?? <String>{};
  }

  /// Whether the signed-in user may switch the active branch from the header.
  /// Driven entirely by the role's 'switch_branch' capability — the Owner role
  /// ships with it ticked by default, but the owner can untick it in
  /// Maintenance → Roles and the header selector then disappears for them too.
  /// (Falls back to the owner session only if no role can be resolved.)
  bool get canSwitchBranch {
    final role = roleById(currentStaff?.roleId);
    if (role == null) return isOwnerSession;
    return role.permissions.contains('switch_branch');
  }

  /// True if the signed-in user can reach [route]. The "More" hub is treated
  /// as accessible whenever at least one of its child destinations is — so
  /// users with even one back-office permission see a way in, and users
  /// with none don't get a dead tab.
  bool canAccess(AppRoute route) {
    if (route == AppRoute.more) {
      const childKeys = <String>{
        'reports', 'employees', 'payroll', 'products',
        'maintenance', 'settings',
      };
      return currentPermissions.any(childKeys.contains);
    }
    return currentPermissions.contains(route.name);
  }

  Tenant? get tenant =>
      _stores.isEmpty ? null : _stores[_currentStoreIndex];

  List<Tenant> get stores => List.unmodifiable(_stores);
  int get currentStoreIndex => _currentStoreIndex;

  bool get needsOnboarding =>
      hasAccount && (_stores.isEmpty || _addingStore);

  /// Supabase UUID of the currently active tenant. Different from
  /// [tenant.id] (which is a local UUID used by in-memory state).
  String? _currentTenantDbId;
  String? get currentTenantDbId => _currentTenantDbId;

  /// Tenant-owned categories from `public.categories`, populated on session
  /// restore and kept in sync with DB writes.
  List<cat.Category> _categories = [];
  List<cat.Category> get categories => List.unmodifiable(_categories);

  /// Find a category (sub-type) by id. Null-safe — returns null for a missing
  /// or null id (e.g. a product whose category was deleted).
  cat.Category? categoryById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Sub-types (categories) under a given product type, sorted by sort order.
  /// Pass null to get unassigned sub-types (the "Other" bucket).
  List<cat.Category> categoriesForType(String? typeId) =>
      (_categories.where((c) => c.typeId == typeId).toList())
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The product type a product effectively belongs to for the two-level Sell
  /// browser. Prefers the product's own `typeId`; falls back to its category's
  /// `typeId`; null means "Other" (no resolvable type). One shared rule so the
  /// Sell bucketing is deterministic.
  String? effectiveTypeId(CafeItem p) =>
      p.typeId ?? categoryById(p.categoryId)?.typeId;

  /// Sell "arrange mode" — shared so the cart/order panel can swap to a mini
  /// tutorial + "Done editing" button while the owner rearranges the menu.
  bool _arrangeMode = false;
  bool get arrangeMode => _arrangeMode;
  void setArrangeMode(bool v) {
    if (_arrangeMode == v) return;
    _arrangeMode = v;
    notifyListeners();
  }

  /// Per-tenant feature flags from `public.tenant_features`. Drives which
  /// nav tabs (Bookings, Sessions, Members) are visible.
  cat.TenantFeatures _features = cat.TenantFeatures();
  cat.TenantFeatures get features => _features;

  /// True once the owner has registered a 4-digit PIN for the current tenant
  /// (via the `owner_pins` table).
  bool _ownerPinSet = false;
  bool get hasOwnerPin => _ownerPinSet;

  /// Routing helper: after the user signs up + onboards but BEFORE they've
  /// set their owner PIN. main.dart shows [SetPinView] when true.
  bool get needsToSetPin =>
      hasAccount &&
      !needsOnboarding &&
      _currentTenantDbId != null &&
      !_ownerPinSet;

  int _selectedBranchIndex = 0;

  // Per-tenant payroll state. Keyed by tenant.id so switching stores keeps
  // each store's books separate.
  final Map<String, List<TimeEntry>> _timeEntriesByTenant = {};
  final Map<String, List<PayrollRun>> _payrollRunsByTenant = {};

  Branch get selectedBranch {
    final t = tenant;
    if (t == null || t.branches.isEmpty) return MockData.branches[0];
    final i = _selectedBranchIndex.clamp(0, t.branches.length - 1);
    return t.branches[i];
  }

  void selectBranch(Branch branch) {
    if (tenant == null) return;
    final i = tenant!.branches.indexWhere((b) => b.id == branch.id);
    if (i < 0) return;
    _selectedBranchIndex = i;
    notifyListeners();
  }

  // ───── account-level auth (Supabase email OTP, passwordless) ─────

  /// Sends a 6-digit OTP to [email]. Used for both signup and login — Supabase
  /// will create the user if they don't exist (`shouldCreateUser: true`), which
  /// prevents email enumeration: an attacker can't tell whether an address is
  /// registered. [displayName] is attached to user metadata on first signup so
  /// it survives session restore.
  ///
  /// Returns `null` on success, or a user-safe error message on failure.
  Future<String?> sendSignupOtp({
    required String email,
    required String displayName,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return 'Please enter your email.';
    try {
      // Shield: block sign-up for an address that already has an account.
      // Otherwise OTP would silently sign them into their existing store,
      // which reads as "my new account is gone". Guide them to sign in.
      // Fail OPEN — a transient RPC error must never block a real sign-up;
      // auth.users.email is unique anyway, so the worst case is the old flow.
      try {
        final exists = await supabase
            .rpc('email_is_registered', params: {'p_email': cleanEmail});
        if (exists == true) {
          return 'This email is already registered. Please sign in instead.';
        }
      } catch (_) {
        // ignore — proceed to send the OTP as before
      }
      await supabase.auth.signInWithOtp(
        email: cleanEmail,
        shouldCreateUser: true,
        data: {
          if (displayName.trim().isNotEmpty)
            'display_name': displayName.trim(),
        },
      );
      _pendingOtpEmail = cleanEmail;
      notifyListeners();
      return null;
    } on sb.AuthException catch (e) {
      return _humanizeAuthError(e);
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// Sends a 6-digit OTP for a returning user. Same `shouldCreateUser: true`
  /// guard against enumeration — a new email that lands here gets a fresh
  /// account without leaking the distinction.
  Future<String?> sendLoginOtp({required String email}) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) return 'Please enter your email.';
    try {
      await supabase.auth.signInWithOtp(
        email: cleanEmail,
        shouldCreateUser: true,
      );
      _pendingOtpEmail = cleanEmail;
      notifyListeners();
      return null;
    } on sb.AuthException catch (e) {
      return _humanizeAuthError(e);
    } catch (_) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }

  /// Verifies the 6-digit [token] against [_pendingOtpEmail]. On success the
  /// auth-state listener fires and updates [currentOwner].
  Future<String?> verifyOtp(String token) async {
    final email = _pendingOtpEmail;
    if (email == null) return 'No verification in progress. Please request a new code.';
    final cleanToken = token.trim();
    final expectedLen = SupabaseBootstrap.otpLength;
    if (cleanToken.length != expectedLen ||
        int.tryParse(cleanToken) == null) {
      return 'Enter the $expectedLen-digit code from your email.';
    }
    try {
      await supabase.auth.verifyOTP(
        email: email,
        token: cleanToken,
        type: sb.OtpType.email,
      );
      _pendingOtpEmail = null;
      notifyListeners();
      return null;
    } on sb.AuthException catch (e) {
      return _humanizeAuthError(e);
    } catch (_) {
      return 'Could not verify the code. Try again in a moment.';
    }
  }

  /// Cancels an in-progress OTP verification — used when the user taps Back.
  void cancelOtpVerification() {
    if (_pendingOtpEmail == null) return;
    _pendingOtpEmail = null;
    notifyListeners();
  }

  /// Re-sends the OTP to the email currently being verified.
  Future<String?> resendOtp() async {
    final email = _pendingOtpEmail;
    if (email == null) return 'No verification in progress.';
    try {
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
      return null;
    } on sb.AuthException catch (e) {
      return _humanizeAuthError(e);
    } catch (_) {
      return 'Could not resend the code. Try again in a moment.';
    }
  }

  /// Map Supabase auth errors to user-friendly text. We deliberately don't
  /// leak whether an email exists or not.
  String _humanizeAuthError(sb.AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('rate limit') || msg.contains('over_email_send_rate')) {
      return 'Too many attempts. Please wait a minute before trying again.';
    }
    if (msg.contains('invalid') && msg.contains('token')) {
      return 'That code is invalid or expired. Request a new one.';
    }
    if (msg.contains('expired')) {
      return 'That code has expired. Tap Resend to get a new one.';
    }
    if (msg.contains('email') && msg.contains('invalid')) {
      return 'That email address looks invalid.';
    }
    return 'Sign-in failed. Please try again.';
  }

  Future<void> signOutAccount() async {
    // Tear down local state first so the UI doesn't flash a logged-in state
    // while the network call is in flight.
    _pendingOtpEmail = null;
    cart.clear();
    try {
      await supabase.auth.signOut();
    } catch (_) {
      // Even if the network call fails, the auth listener will clear local
      // state when it observes a null session on next launch.
    }
    // currentOwner is cleared by the auth listener.
  }

  // ───── stores ─────
  void startAddingStore() {
    _addingStore = true;
    notifyListeners();
  }

  void cancelAddingStore() {
    _addingStore = false;
    notifyListeners();
  }

  void switchStore(int index) {
    if (index < 0 || index >= _stores.length) return;
    _currentStoreIndex = index;
    selectedRoute = AppRoute.sell;
    cart.clear();
    notifyListeners();
  }

  /// Persists the new store to Supabase (tenants + branches tables) AND
  /// builds the local in-memory [Tenant] alongside it. [sellPacks] are the
  /// "What do you sell?" chips picked at onboarding — they seed starter
  /// categories and flip the matching feature flags. Returns null on
  /// success, or a user-safe error message on failure.
  Future<String?> completeOnboarding({
    required String businessName,
    required String businessAddress,
    required String firstBranchName,
    Set<cat.SellPack> sellPacks = const {cat.SellPack.coffee},
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return 'You must be signed in to create a store.';

    String? tenantDbId;
    String? branchDbId;
    final fetchedCategories = <cat.Category>[];
    try {
      final tenantRow = await supabase
          .from('tenants')
          .insert({
            'owner_id': user.id,
            'business_name': businessName,
            'address': businessAddress,
          })
          .select('id')
          .single();
      tenantDbId = tenantRow['id'] as String;

      final branchRow = await supabase
          .from('branches')
          .insert({
            'tenant_id': tenantDbId,
            'name': firstBranchName,
          })
          .select('id')
          .single();
      branchDbId = branchRow['id'] as String;

      // Seed the default product types FIRST so each seeded category (sub-type)
      // can be linked to its parent type as we build the payload below.
      // Idempotent — unique(tenant_id, name) keeps re-runs safe.
      final typeIds = await _seedDefaultProductTypes(tenantDbId);

      // Default cafe sub-types under each product type. Owners can rename,
      // reorder, or remove them in Maintenance. icon_name is left null so each
      // sub-type gets a themed icon resolved from its name.
      const defaultSubTypes =
          <({String name, String type, String emoji, int sortOrder})>[
        // Drinks
        (name: 'Coffee', type: 'drinks', emoji: '☕', sortOrder: 10),
        (name: 'Tea', type: 'drinks', emoji: '🍵', sortOrder: 20),
        (name: 'Soda', type: 'drinks', emoji: '🥤', sortOrder: 30),
        (name: 'Milk Tea', type: 'drinks', emoji: '🧋', sortOrder: 40),
        (name: 'Smoothie', type: 'drinks', emoji: '🥤', sortOrder: 50),
        // Foods
        (name: 'Rice Meals', type: 'foods', emoji: '🍚', sortOrder: 60),
        (name: 'Breakfast', type: 'foods', emoji: '🍳', sortOrder: 70),
        (name: 'Dinner', type: 'foods', emoji: '🍽', sortOrder: 80),
        (name: 'Sharing', type: 'foods', emoji: '🍢', sortOrder: 90),
        // Pastries
        (name: 'Bread', type: 'pastries', emoji: '🍞', sortOrder: 100),
        (name: 'Cake', type: 'pastries', emoji: '🍰', sortOrder: 110),
        (name: 'Cookies', type: 'pastries', emoji: '🍪', sortOrder: 120),
        (name: 'Croissant', type: 'pastries', emoji: '🥐', sortOrder: 130),
        (name: 'Donut', type: 'pastries', emoji: '🍩', sortOrder: 140),
      ];
      final categoryPayload = <Map<String, dynamic>>[
        for (final c in defaultSubTypes)
          {
            'tenant_id': tenantDbId,
            'name': c.name,
            'emoji': c.emoji,
            'icon_name': null,
            'sort_order': c.sortOrder,
            'type_id': typeIds[c.type],
            'is_system': true,
          },
      ];
      if (categoryPayload.isNotEmpty) {
        final inserted = await supabase
            .from('categories')
            .insert(categoryPayload)
            .select(
                'id, name, emoji, icon_name, sort_order, type_id, is_system, separate_sales');
        fetchedCategories.addAll((inserted as List)
            .map((r) => cat.Category.fromRow(r as Map<String, dynamic>)));
      }

      // Flip feature flags from packs that need them. tenant_features row
      // was auto-created by the trigger when the tenant was inserted.
      final featurePatch = <String, dynamic>{};
      if (sellPacks.contains(cat.SellPack.coworking)) {
        featurePatch['reserve_enabled'] = true;
        featurePatch['timer_enabled'] = true;
      }
      if (sellPacks.contains(cat.SellPack.memberships)) {
        featurePatch['subscribe_enabled'] = true;
      }
      if (featurePatch.isNotEmpty) {
        await supabase
            .from('tenant_features')
            .update(featurePatch)
            .eq('tenant_id', tenantDbId);
      }

      _features = cat.TenantFeatures(
        reserveEnabled: featurePatch['reserve_enabled'] == true,
        timerEnabled: featurePatch['timer_enabled'] == true,
        subscribeEnabled: featurePatch['subscribe_enabled'] == true,
      );

      // Seed default modifier groups (Size, Temperature, Strength) so the
      // owner sees a usable Maintenance screen immediately. Same defaults
      // the SQL backfill uses for existing tenants.
      await _seedDefaultModifierGroups(tenantDbId);

      // Starter inventory categories (Drinks / Foods / Items) so the Stock
      // page has buckets from day one. Owners rename/remove freely.
      await _seedDefaultInventoryCategories(tenantDbId);

      // Seed payroll rules + default leaves + employment templates. Same
      // shape the SQL backfill uses for existing tenants. Idempotent —
      // relies on unique constraints to no-op if already present.
      await _seedDefaultPayrollSurface(tenantDbId);

      // (Product types were seeded earlier so categories could link to them.)
    } on sb.PostgrestException catch (e) {
      return 'Could not save your business: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
    _categories = fetchedCategories
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Local in-memory tenant — mirrors the DB record. Products, inventory,
    // employees and add-ons are now DB-backed and hydrated separately on
    // the next _restoreTenantFromDb cycle (or via dedicated CRUD calls).
    final newStore = Tenant(
      businessName: businessName,
      address: businessAddress,
      branches: [Branch(id: branchDbId, name: firstBranchName)],
    );
    _stores.add(newStore);
    _currentStoreIndex = _stores.length - 1;
    _addingStore = false;
    _currentTenantDbId = tenantDbId;
    _ownerPinSet = false; // fresh tenant — owner still needs to set the PIN
    _timeEntriesByTenant[newStore.id] = [];
    _payrollRunsByTenant[newStore.id] = [];

    // Seed default employee roles for this fresh tenant. Idempotent against
    // the SQL backfill via unique(tenant_id, name).
    await _seedDefaultEmployeeRoles(tenantDbId);
    selectedRoute = AppRoute.sell;
    notifyListeners();
    return null;
  }

  // ───── Owner PIN (Supabase-backed, bcrypt-hashed via RPC) ─────

  /// Registers a 4-digit owner PIN for the current tenant. Calls the
  /// `set_owner_pin` RPC which hashes via bcrypt before storing.
  Future<String?> setOwnerPin(String pin) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    final cleanPin = pin.trim();
    if (cleanPin.length != 4 || int.tryParse(cleanPin) == null) {
      return 'PIN must be exactly 4 digits.';
    }
    try {
      await supabase.rpc('set_owner_pin', params: {
        'p_tenant_id': tenantId,
        'p_pin': cleanPin,
      });
      _ownerPinSet = true;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // PIN_TAKEN: the RPC prefixes its message with this marker when
      // another user in the tenant already uses the same 4-digit PIN.
      // Strip the marker so the toast reads as a clean sentence.
      if (e.message.contains('PIN_TAKEN')) {
        return e.message.replaceFirst('PIN_TAKEN: ', '');
      }
      return 'Could not save your PIN: ${e.message}';
    } catch (_) {
      return 'Could not save your PIN. Please try again.';
    }
  }

  /// Flag the owner PIN as "needs re-registration" without touching the DB.
  /// Called when the user starts a Forgot-PIN flow so the routing layer will
  /// route them to [SetPinView] right after the OTP verification succeeds.
  /// The stored bcrypt hash is overwritten when they actually submit a new
  /// PIN via [setOwnerPin].
  void markOwnerPinReset() {
    if (!_ownerPinSet) return;
    _ownerPinSet = false;
    currentStaff = null;
    cart.clear();
    notifyListeners();
  }

  /// Verifies a 4-digit owner PIN against the stored bcrypt hash. The RPC
  /// throttles brute force: 5 wrong attempts in a row → 5-minute lockout.
  /// Returns null on success, or a user-safe error message.
  Future<String?> verifyOwnerPin(String pin) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    final cleanPin = pin.trim();
    if (cleanPin.length != 4 || int.tryParse(cleanPin) == null) {
      return 'Enter a 4-digit PIN.';
    }
    try {
      final ok = await supabase.rpc('verify_owner_pin', params: {
        'p_tenant_id': tenantId,
        'p_pin': cleanPin,
      });
      if (ok == true) {
        // Sign in as the owner. We synthesize an "Owner" Employee so the
        // rest of the app (which expects currentStaff) keeps working.
        // Attach the synthesized owner-staff to the seeded Owner role so
        // role-aware UI (badges, etc.) reads consistently. Permission gates
        // bypass this anyway via the `currentOwner != null` short-circuit.
        final ownerRole = _employeeRoles
            .where((r) => r.isSystem && r.name == 'Owner')
            .firstOrNull;
        currentStaff = Employee(
          id: currentOwner?.id ?? 'owner',
          name: currentOwner?.displayName ?? 'Owner',
          roleId: ownerRole?.id,
          role: ownerRole?.name ?? 'Owner',
        );
        _beginPinSettling();
        return null;
      }
      return 'Incorrect PIN. Try again.';
    } on sb.PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('locked')) {
        return 'PIN locked. Please wait a few minutes before trying again.';
      }
      return 'Could not verify PIN: ${e.message}';
    } catch (_) {
      return 'Could not verify PIN. Please try again.';
    }
  }

  /// Single PIN sign-in. Tries the owner PIN first; if it doesn't match,
  /// fans out to every employee whose role requires a PIN and verifies
  /// against their bcrypt hash via `verify_cashier_pin`. The first matching
  /// employee signs in as [currentStaff]. Returns null on success or a
  /// user-safe error message otherwise.
  Future<String?> verifyPin(String pin) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    final p = pin.trim();
    if (p.length < 4 || p.length > 8 || int.tryParse(p) == null) {
      return 'Enter a 4–8 digit PIN.';
    }

    // 1) Owner PIN — PROBE without counting a failure. The unified login
    //    tries the owner PIN first for every 4-digit code, so a cashier
    //    signing in with their own (non-owner) PIN must NOT bump the owner's
    //    brute-force counter — that bug locked owners who never mistyped.
    //    A genuine failed login charges one attempt at the very end instead.
    bool ownerLocked = false;
    if (p.length == 4) {
      try {
        final ok = await supabase.rpc('verify_owner_pin', params: {
          'p_tenant_id': tenantId,
          'p_pin': p,
          'p_count_failure': false,
        });
        if (ok == true) {
          final ownerRole = _employeeRoles
              .where((r) => r.isSystem && r.name == 'Owner')
              .firstOrNull;
          currentStaff = Employee(
            id: currentOwner?.id ?? 'owner',
            name: currentOwner?.displayName ?? 'Owner',
            roleId: ownerRole?.id,
            role: ownerRole?.name ?? 'Owner',
          );
          _beginPinSettling();
          return null;
        }
      } on sb.PostgrestException catch (e) {
        // Owner PIN is in its lockout window. Don't block cashiers — they
        // have their own per-employee throttle — so remember it and fall
        // through to cashier matching; only report it if nothing matches.
        if (e.message.toLowerCase().contains('lock')) {
          ownerLocked = true;
        }
        // Other errors: fall through to cashier-PIN matching.
      } catch (_) {
        return 'Could not reach the server. Please try again.';
      }
    }

    // 2) Cashier PINs — only employees whose role requires a PIN.
    final candidates = <Employee>[];
    for (final e in _employees) {
      final role = roleById(e.roleId);
      if (role?.requiresPin == true) candidates.add(e);
    }
    for (final emp in candidates) {
      try {
        final ok = await supabase.rpc('verify_cashier_pin', params: {
          'p_tenant_id': tenantId,
          'p_employee_id': emp.id,
          'p_pin': p,
        });
        if (ok == true) {
          currentStaff = emp;
          _beginPinSettling();
          return null;
        }
      } on sb.PostgrestException catch (_) {
        // Locked or other per-employee error — skip and try the next.
        continue;
      } catch (_) {
        return 'Could not reach the server. Please try again.';
      }
    }

    // 3) Nothing matched. Charge ONE failed attempt against the owner
    //    throttle so the login screen still resists brute force — but only
    //    on a truly failed login, never on a successful cashier sign-in.
    if (p.length == 4 && !ownerLocked) {
      try {
        await supabase.rpc('verify_owner_pin', params: {
          'p_tenant_id': tenantId,
          'p_pin': p,
          'p_count_failure': true,
        });
      } catch (_) {
        // Best-effort throttle bump; ignore failures here.
      }
    }

    if (ownerLocked) {
      return 'Owner PIN locked. Please wait a few minutes.';
    }
    return 'No PIN matched. Try again.';
  }

  /// Side-effect-free duplicate-PIN probe for the employee form. Returns the
  /// name of the account (Owner or an existing cashier) that already uses
  /// [pin], or null if it's free. Unlike [verifyPin] this never signs anyone
  /// in or charges the brute-force throttle. Only 4-digit PINs are checked.
  Future<String?> pinConflictName(String pin, {String? excludeId}) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return null;
    final p = pin.trim();
    if (p.length != 4 || int.tryParse(p) == null) return null;
    // Owner PIN — probe without counting a failure.
    try {
      final ok = await supabase.rpc('verify_owner_pin', params: {
        'p_tenant_id': tenantId,
        'p_pin': p,
        'p_count_failure': false,
      });
      if (ok == true) return 'the Owner';
    } catch (_) {
      // Locked / unreachable — fall through to cashier matching.
    }
    for (final emp in _employees) {
      if (emp.id == excludeId) continue;
      final role = roleById(emp.roleId);
      if (role?.requiresPin != true) continue;
      try {
        final ok = await supabase.rpc('verify_cashier_pin', params: {
          'p_tenant_id': tenantId,
          'p_employee_id': emp.id,
          'p_pin': p,
        });
        if (ok == true) return emp.name;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  // ───── branches ─────
  void addBranchToCurrentStore(String name) {
    if (tenant == null || name.trim().isEmpty) return;
    tenant!.branches.add(Branch(name: name.trim()));
    notifyListeners();
  }

  void removeBranchFromCurrentStore(String branchId) {
    if (tenant == null) return;
    if (tenant!.branches.length <= 1) return;
    tenant!.branches.removeWhere((b) => b.id == branchId);
    notifyListeners();
  }

  // ───── store mutators (Settings edits) ─────
  /// Updates the store's name and/or address and PERSISTS to the tenants
  /// table (the old version only mutated memory, so edits silently reverted
  /// on reload). Optimistic local update with rollback on failure. Returns
  /// null on success or a user-safe error message.
  Future<String?> updateStoreInfo({
    String? businessName,
    String? address,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenant == null || tenantId == null) return 'No store selected.';

    final prevName = tenant!.businessName;
    final prevAddr = tenant!.address;
    if (businessName != null) tenant!.businessName = businessName;
    if (address != null) tenant!.address = address;
    notifyListeners();

    try {
      final payload = <String, dynamic>{};
      if (businessName != null) payload['business_name'] = businessName;
      if (address != null) payload['address'] = address;
      if (payload.isNotEmpty) {
        // .select() so a row that DIDN'T update (RLS mismatch / wrong id)
        // comes back empty instead of silently "succeeding" — otherwise the
        // change sticks in the UI but never reaches the DB.
        final res = await supabase
            .from('tenants')
            .update(payload)
            .eq('id', tenantId)
            .select('id');
        if ((res as List).isEmpty) {
          tenant!.businessName = prevName;
          tenant!.address = prevAddr;
          notifyListeners();
          return 'Could not save — please sign out and back in, then retry.';
        }
      }
      return null;
    } catch (e) {
      tenant!.businessName = prevName;
      tenant!.address = prevAddr;
      notifyListeners();
      if (kDebugMode) debugPrint('updateStoreInfo failed: $e');
      return 'Could not save. Please try again.';
    }
  }

  /// Flips the store-wide inventory tracking master switch. When off, no
  /// product deducts stock or is blocked by it. Optimistic with rollback.
  Future<String?> setInventoryTrackingEnabled(bool value) async {
    final tenantId = _currentTenantDbId;
    final t = tenant;
    if (t == null || tenantId == null) return 'No store selected.';
    final prev = t.inventoryTrackingEnabled;
    t.inventoryTrackingEnabled = value;
    notifyListeners();
    try {
      final res = await supabase
          .from('tenants')
          .update({'inventory_tracking_enabled': value})
          .eq('id', tenantId)
          .select('id');
      if ((res as List).isEmpty) {
        t.inventoryTrackingEnabled = prev;
        notifyListeners();
        return 'Could not save — please sign out and back in, then retry.';
      }
      return null;
    } catch (_) {
      t.inventoryTrackingEnabled = prev;
      notifyListeners();
      return 'Could not save. Please try again.';
    }
  }

  /// Updates the store's BIR registration details (printed on Sales
  /// Invoices). Only the passed fields change. Optimistic with rollback.
  Future<String?> updateBirInfo({
    bool? vatRegistered,
    String? tin,
    String? branchCode,
    String? birMin,
    String? birSerial,
    String? ptuNumber,
    String? ptuValidUntil,
    String? birAccreditationNo,
  }) async {
    final tenantId = _currentTenantDbId;
    final t = tenant;
    if (t == null || tenantId == null) return 'No store selected.';
    // Snapshot for rollback.
    final pVat = t.vatRegistered, pTin = t.tin, pBranch = t.branchCode;
    final pMin = t.birMin, pSn = t.birSerial, pPtu = t.ptuNumber;
    final pValid = t.ptuValidUntil, pAccr = t.birAccreditationNo;

    final payload = <String, dynamic>{};
    if (vatRegistered != null) {
      t.vatRegistered = vatRegistered;
      payload['vat_registered'] = vatRegistered;
    }
    if (tin != null) {
      t.tin = tin;
      payload['tin'] = tin;
    }
    if (branchCode != null) {
      t.branchCode = branchCode;
      payload['branch_code'] = branchCode;
    }
    if (birMin != null) {
      t.birMin = birMin;
      payload['bir_min'] = birMin;
    }
    if (birSerial != null) {
      t.birSerial = birSerial;
      payload['bir_serial'] = birSerial;
    }
    if (ptuNumber != null) {
      t.ptuNumber = ptuNumber;
      payload['ptu_number'] = ptuNumber;
    }
    if (ptuValidUntil != null) {
      t.ptuValidUntil = ptuValidUntil;
      payload['ptu_valid_until'] = ptuValidUntil;
    }
    if (birAccreditationNo != null) {
      t.birAccreditationNo = birAccreditationNo;
      payload['bir_accreditation_no'] = birAccreditationNo;
    }
    if (payload.isEmpty) return null;
    notifyListeners();

    void rollback() {
      t.vatRegistered = pVat;
      t.tin = pTin;
      t.branchCode = pBranch;
      t.birMin = pMin;
      t.birSerial = pSn;
      t.ptuNumber = pPtu;
      t.ptuValidUntil = pValid;
      t.birAccreditationNo = pAccr;
      notifyListeners();
    }

    try {
      final res = await supabase
          .from('tenants')
          .update(payload)
          .eq('id', tenantId)
          .select('id');
      if ((res as List).isEmpty) {
        rollback();
        return 'Could not save — please sign out and back in, then retry.';
      }
      return null;
    } catch (_) {
      rollback();
      return 'Could not save. Please try again.';
    }
  }

  /// Toggles inventory tracking for a single product. Optimistic with
  /// rollback so the switch feels instant.
  Future<String?> setProductTrackInventory(
      CafeItem product, bool value) async {
    final prev = product.trackInventory;
    product.trackInventory = value;
    notifyListeners();
    try {
      final res = await supabase
          .from('products')
          .update({
            'track_inventory': value,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', product.id)
          .select('id');
      if ((res as List).isEmpty) {
        product.trackInventory = prev;
        notifyListeners();
        return 'Could not save. Please try again.';
      }
      return null;
    } catch (_) {
      product.trackInventory = prev;
      notifyListeners();
      return 'Could not reach the server. Please try again.';
    }
  }

  /// The new address an in-progress email change is verifying against, or
  /// null when no change is underway. Drives the OTP confirm dialog.
  String? _pendingEmailChange;
  String? get pendingEmailChange => _pendingEmailChange;

  /// Step 1 of changing the owner's login email: sends a 6-digit OTP to the
  /// NEW address. The change only applies once [confirmEmailChange] verifies
  /// that code — the OLD email is never involved, so a lost old inbox can't
  /// lock anyone out, and a typo'd new address simply never confirms.
  ///
  /// Requires "Secure email change" to be OFF in Supabase Auth (otherwise the
  /// old address must also confirm). Returns null on success, else a message.
  Future<String?> startEmailChange(String newEmail) async {
    final e = newEmail.trim().toLowerCase();
    if (e.isEmpty || !e.contains('@') || !e.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (e == (currentOwner?.email ?? '').trim().toLowerCase()) {
      return 'That is already your email.';
    }
    try {
      // Shield: don't move to an address that already has its own account.
      // Fail OPEN — a transient RPC error must never block a real change.
      try {
        final exists = await supabase
            .rpc('email_is_registered', params: {'p_email': e});
        if (exists == true) {
          return 'That email is already used by another account.';
        }
      } catch (_) {/* ignore — proceed */}
      await supabase.auth.updateUser(sb.UserAttributes(email: e));
      _pendingEmailChange = e;
      notifyListeners();
      return null;
    } on sb.AuthException catch (ex) {
      return _humanizeAuthError(ex);
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Step 2: verifies the [token] sent to the pending new address and
  /// finalizes the change. The session is updated in place — the owner stays
  /// signed in and the PIN (tenant-scoped) is untouched. The auth listener
  /// refreshes [currentOwner] with the new email. Returns null on success.
  Future<String?> confirmEmailChange(String token) async {
    final e = _pendingEmailChange;
    if (e == null) return 'No email change in progress.';
    final code = token.trim();
    final expectedLen = SupabaseBootstrap.otpLength;
    if (code.length != expectedLen || int.tryParse(code) == null) {
      return 'Enter the $expectedLen-digit code from your email.';
    }
    try {
      await supabase.auth.verifyOTP(
        email: e,
        token: code,
        type: sb.OtpType.emailChange,
      );
      _pendingEmailChange = null;
      notifyListeners();
      return null;
    } on sb.AuthException catch (ex) {
      return _humanizeAuthError(ex);
    } catch (_) {
      return 'Could not verify the code. Try again in a moment.';
    }
  }

  /// Re-sends the OTP for an in-progress email change to the new address.
  Future<String?> resendEmailChangeOtp() async {
    final e = _pendingEmailChange;
    if (e == null) return 'No email change in progress.';
    try {
      await supabase.auth.updateUser(sb.UserAttributes(email: e));
      return null;
    } on sb.AuthException catch (ex) {
      return _humanizeAuthError(ex);
    } catch (_) {
      return 'Could not resend the code. Try again in a moment.';
    }
  }

  /// Abandons an in-progress email change (user closed the OTP dialog).
  void cancelEmailChange() {
    if (_pendingEmailChange == null) return;
    _pendingEmailChange = null;
    notifyListeners();
  }

  /// Renames the owner. Persists to the Supabase auth user metadata
  /// (`display_name`) — the same field receipts/orders read for the owner —
  /// and updates local state so the UI reflects it immediately. Returns null
  /// on success or a user-safe error message.
  Future<String?> updateOwnerName(String newName) async {
    final n = newName.trim();
    if (n.isEmpty) return 'Enter a name.';
    try {
      await supabase.auth.updateUser(
          sb.UserAttributes(data: {'display_name': n}));
      final o = currentOwner;
      if (o != null) {
        currentOwner = OwnerAccount(
          id: o.id,
          email: o.email,
          password: o.password,
          displayName: n,
          tenantId: o.tenantId,
        );
      }
      // Keep the synthesized owner-staff name in sync so orders/receipts
      // rung in this owner session stamp the new name.
      if (isOwnerSession && currentStaff != null) {
        currentStaff = Employee(
          id: currentStaff!.id,
          name: n,
          roleId: currentStaff!.roleId,
          role: currentStaff!.role,
        );
      }
      notifyListeners();
      return null;
    } on sb.AuthException catch (ex) {
      return ex.message;
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Categories (Supabase-backed; Maintenance) ─────────────────────

  /// Creates a new category on the active tenant. Returns the inserted row
  /// (with its DB-assigned id) on success, or a user-safe error string on
  /// failure. Caller should refresh local state from the return value.
  Future<String?> addCategory({
    required String name,
    required String emoji,
    String? iconName,
    int sortOrder = 0,
    String? typeId,
    bool separateSales = false,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (name.trim().isEmpty) return 'Category name is required.';
    try {
      final inserted = await supabase
          .from('categories')
          .insert({
            'tenant_id': tenantId,
            'name': name.trim(),
            'emoji': emoji.trim(),
            'icon_name': iconName,
            'sort_order': sortOrder,
            'type_id': typeId,
            'separate_sales': separateSales,
          })
          .select('id, name, emoji, icon_name, sort_order, type_id, '
              'is_system, separate_sales')
          .single();
      _categories.add(cat.Category.fromRow(inserted));
      _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // 23505 = unique violation (duplicate name for this tenant).
      if (e.code == '23505') {
        return 'You already have a category named "$name".';
      }
      return 'Could not add category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateCategory(cat.Category updated) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Category name is required.';
    try {
      await supabase.from('categories').update({
        'name': updated.name.trim(),
        'emoji': updated.emoji.trim(),
        'icon_name': updated.iconName,
        'sort_order': updated.sortOrder,
        'type_id': updated.typeId,
        'separate_sales': updated.separateSales,
      }).eq('id', updated.id);
      final i = _categories.indexWhere((c) => c.id == updated.id);
      if (i >= 0) {
        _categories[i] = updated;
        _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a category named "${updated.name}".';
      }
      return 'Could not update category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeCategory(String categoryId) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('categories').delete().eq('id', categoryId);
      _categories.removeWhere((c) => c.id == categoryId);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // 23503 = foreign-key violation (a sellable still references this category).
      if (e.code == '23503') {
        return 'Move or delete the items in this category first.';
      }
      return 'Could not delete category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Tenant features (Supabase-backed; Settings) ──────────────────

  Future<String?> updateTenantFeatures(cat.TenantFeatures updated) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase.from('tenant_features').update({
        'reserve_enabled': updated.reserveEnabled,
        'timer_enabled': updated.timerEnabled,
        'subscribe_enabled': updated.subscribeEnabled,
        'service_enabled': updated.serviceEnabled,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('tenant_id', tenantId);
      _features = updated.copy();
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update features: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Master modifier groups (Supabase-backed; Maintenance) ─────

  /// Cached list of master modifier groups for the active tenant. Populated
  /// by [_restoreTenantFromDb] (loads via PostgREST nested-select of
  /// `modifier_groups(*, modifier_options(*))`).
  List<MasterModifierGroup> _modifierGroups = [];
  List<MasterModifierGroup> get modifierGroups =>
      List.unmodifiable(_modifierGroups);

  List<CustomCategory> get customCategories =>
      tenant?.customCategories ?? const <CustomCategory>[];

  /// Inserts the standard Size / Temperature / Strength modifier groups
  /// for a freshly created tenant. Called from [completeOnboarding].
  /// Idempotent — relies on the unique(tenant_id, name) constraint to
  /// no-op if defaults already exist (e.g. from the SQL backfill).
  /// Starter inventory categories for a new tenant — Drinks / Foods / Items.
  Future<void> _seedDefaultInventoryCategories(String tenantId) async {
    const cats = [
      (name: 'Drinks', iconName: 'local_cafe_outlined', sortOrder: 10),
      (name: 'Foods', iconName: 'restaurant_outlined', sortOrder: 20),
      (name: 'Items', iconName: 'inventory_2_outlined', sortOrder: 30),
    ];
    try {
      await supabase.from('inventory_categories').insert([
        for (final c in cats)
          {
            'tenant_id': tenantId,
            'name': c.name,
            'icon_name': c.iconName,
            'sort_order': c.sortOrder,
          },
      ]);
    } on sb.PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint('Seed inventory categories failed: ${e.message}');
      }
    } catch (_) {}
  }

  Future<void> _seedDefaultModifierGroups(String tenantId) async {
    Future<String> insertGroup({
      required String name,
      required String emoji,
      required String iconName,
      required bool required,
      required int defaultIndex,
      required int sortOrder,
    }) async {
      final row = await supabase
          .from('modifier_groups')
          .insert({
            'tenant_id': tenantId,
            'name': name,
            'emoji': emoji,
            'icon_name': iconName,
            'required': required,
            'default_index': defaultIndex,
            'sort_order': sortOrder,
            'is_system': true,
          })
          .select('id')
          .single();
      return row['id'] as String;
    }

    Future<void> insertOptions(
        String groupId, List<String> names) async {
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < names.length; i++) {
        payload.add({
          'group_id': groupId,
          'name': names[i],
          'sort_order': i,
        });
      }
      await supabase.from('modifier_options').insert(payload);
    }

    try {
      final sizeId = await insertGroup(
        name: 'Size',
        emoji: '📏',
        iconName: 'straighten_outlined',
        required: true,
        defaultIndex: 1,
        sortOrder: 10,
      );
      await insertOptions(sizeId, ['Small', 'Medium', 'Large']);

      final tempId = await insertGroup(
        name: 'Temperature',
        emoji: '🌡',
        iconName: 'thermostat_outlined',
        required: true,
        defaultIndex: 0,
        sortOrder: 20,
      );
      await insertOptions(tempId, ['Hot', 'Cold']);

      final strengthId = await insertGroup(
        name: 'Strength',
        emoji: '⚡',
        iconName: 'bolt_outlined',
        required: false,
        defaultIndex: 0,
        sortOrder: 30,
      );
      await insertOptions(strengthId, ['Mild', 'Strong']);
    } on sb.PostgrestException catch (e) {
      // 23505 = unique violation — defaults already seeded (e.g. SQL
      // backfill ran). Silently skip.
      if (e.code != '23505' && kDebugMode) {
        debugPrint('Seed default modifier groups failed: ${e.message}');
      }
    }
  }

  /// Creates a new modifier group + its options on the active tenant.
  /// Returns null on success, or a user-safe error message.
  Future<String?> addModifierGroup(MasterModifierGroup g) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (g.name.trim().isEmpty) return 'Group name is required.';
    try {
      // Insert the group, then its options (the group_id FK is set after
      // the group's row is returned with its DB-assigned uuid).
      final groupRow = await supabase
          .from('modifier_groups')
          .insert({
            'tenant_id': tenantId,
            'name': g.name.trim(),
            'emoji': g.emoji.trim(),
            'icon_name': g.iconName,
            'required': g.required,
            'default_index': g.defaultIndex,
            'sort_order': g.sortOrder,
          })
          .select(
              'id, name, emoji, icon_name, required, default_index, sort_order, is_system')
          .single();
      final groupId = groupRow['id'] as String;

      List<MasterOption> insertedOptions = [];
      if (g.options.isNotEmpty) {
        final payload = <Map<String, dynamic>>[];
        for (var i = 0; i < g.options.length; i++) {
          payload.add({
            'group_id': groupId,
            'name': g.options[i].name.trim(),
            'price_delta_cents': g.options[i].priceDelta.centavos,
            'sort_order': i,
          });
        }
        final optRows = await supabase
            .from('modifier_options')
            .insert(payload)
            .select('id, name, price_delta_cents, sort_order');
        insertedOptions = (optRows as List)
            .map((r) => MasterOption.fromRow(r as Map<String, dynamic>))
            .toList()
          ..sort((a, b) {
            // Maintain original order by matching back to payload index.
            final ai = g.options.indexWhere((o) => o.name.trim() == a.name);
            final bi = g.options.indexWhere((o) => o.name.trim() == b.name);
            return ai.compareTo(bi);
          });
      }

      _modifierGroups.add(MasterModifierGroup.fromRow(groupRow, options: insertedOptions));
      _modifierGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a group named "${g.name}".';
      }
      return 'Could not add group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Updates a modifier group + replaces its options. Simplest correct
  /// strategy: delete-and-reinsert options inside one logical step; the FK
  /// cascade plus the unique(group_id, name) constraint keep us safe.
  Future<String?> updateModifierGroup(MasterModifierGroup updated) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Group name is required.';
    try {
      await supabase.from('modifier_groups').update({
        'name': updated.name.trim(),
        'emoji': updated.emoji.trim(),
        'icon_name': updated.iconName,
        'required': updated.required,
        'default_index': updated.defaultIndex,
        'sort_order': updated.sortOrder,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);

      await supabase.from('modifier_options')
          .delete()
          .eq('group_id', updated.id);

      List<MasterOption> insertedOptions = [];
      if (updated.options.isNotEmpty) {
        final payload = <Map<String, dynamic>>[];
        for (var i = 0; i < updated.options.length; i++) {
          payload.add({
            'group_id': updated.id,
            'name': updated.options[i].name.trim(),
            'price_delta_cents': updated.options[i].priceDelta.centavos,
            'sort_order': i,
          });
        }
        final optRows = await supabase
            .from('modifier_options')
            .insert(payload)
            .select('id, name, price_delta_cents, sort_order');
        insertedOptions = (optRows as List)
            .map((r) => MasterOption.fromRow(r as Map<String, dynamic>))
            .toList();
      }

      final i = _modifierGroups.indexWhere((g) => g.id == updated.id);
      if (i >= 0) {
        _modifierGroups[i] = MasterModifierGroup(
          id: updated.id,
          name: updated.name.trim(),
          emoji: updated.emoji.trim(),
          iconName: updated.iconName,
          required: updated.required,
          defaultIndex: updated.defaultIndex,
          sortOrder: updated.sortOrder,
          options: insertedOptions,
        );
        _modifierGroups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      }
      // Re-hydrate every product that opted in so cart.unitPrice sees the
      // freshly-edited priceDelta + recipe adjustments. Without this the
      // master cache is updated but products keep the stale runtime copy
      // from initial load, so "Medium = +₱20" never reaches the cart.
      for (final p in _products) {
        if (p.modifierGroupIds.contains(updated.id)) {
          p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'You already have a group named "${updated.name}".';
      }
      return 'Could not update group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeModifierGroup(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('modifier_groups').delete().eq('id', id);
      _modifierGroups.removeWhere((g) => g.id == id);
      // Drop the deleted group from any product that opted in and refresh
      // their runtime modifierGroups list. Without this the Sell view
      // would render a zombie picker for a group that no longer exists.
      for (final p in _products) {
        if (p.modifierGroupIds.contains(id)) {
          p.modifierGroupIds = p.modifierGroupIds
              .where((mid) => mid != id)
              .toList();
          p.modifierGroups = _runtimeModifierGroups(p.modifierGroupIds);
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete group: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  void addCustomCategory(CustomCategory c) {
    if (tenant == null) return;
    tenant!.customCategories.add(c);
    notifyListeners();
  }

  void updateCustomCategory(CustomCategory updated) {
    if (tenant == null) return;
    final i =
        tenant!.customCategories.indexWhere((x) => x.id == updated.id);
    if (i < 0) return;
    tenant!.customCategories[i] = updated;
    notifyListeners();
  }

  void removeCustomCategory(String id) {
    if (tenant == null) return;
    tenant!.customCategories.removeWhere((x) => x.id == id);
    notifyListeners();
  }

  // ───── add-ons (Supabase-backed) ─────────────────────────────────

  List<AddOn> _addOns = [];
  List<AddOn> get addOns => List.unmodifiable(_addOns);

  Future<String?> addAddOn(AddOn addOn) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (addOn.name.trim().isEmpty) return 'Add-on name is required.';
    try {
      final row = await supabase
          .from('add_ons')
          .insert(addOn.toRowPayload(tenantId))
          .select('*')
          .single();
      _addOns.add(AddOn.fromRow(row));
      _addOns.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'An add-on named "${addOn.name}" already exists.';
      }
      return 'Could not add: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateAddOn(AddOn updated) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Add-on name is required.';
    try {
      await supabase
          .from('add_ons')
          .update(updated.toRowPayload(tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id);
      final i = _addOns.indexWhere((a) => a.id == updated.id);
      if (i >= 0) _addOns[i] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeAddOn(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('add_ons').delete().eq('id', id);
      _addOns.removeWhere((a) => a.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── products (Supabase-backed) ────────────────────────────────

  List<CafeItem> _products = [];
  List<CafeItem> get products => List.unmodifiable(_products);

  CafeItem? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<String?> addProduct(CafeItem product) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (product.name.trim().isEmpty) return 'Product name is required.';
    try {
      final row = await supabase
          .from('products')
          .insert(productRowPayload(product, tenantId))
          .select('*, type:product_types(id, name), '
              'category:categories(id, name)')
          .single();
      final saved = CafeItem.fromRow(row,
          typeRow: row['type'] as Map<String, dynamic>?,
          categoryRow: row['category'] as Map<String, dynamic>?);
      saved.modifierGroups =
          _runtimeModifierGroups(saved.modifierGroupIds);
      _products.add(saved);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not add product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateProduct(CafeItem updated) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Product name is required.';
    try {
      final row = await supabase
          .from('products')
          .update(productRowPayload(updated, tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id)
          .select('*, type:product_types(id, name), '
              'category:categories(id, name)')
          .single();
      final saved = CafeItem.fromRow(row,
          typeRow: row['type'] as Map<String, dynamic>?,
          categoryRow: row['category'] as Map<String, dynamic>?);
      saved.modifierGroups =
          _runtimeModifierGroups(saved.modifierGroupIds);
      final i = _products.indexWhere((p) => p.id == saved.id);
      if (i >= 0) _products[i] = saved;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeProduct(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('products').delete().eq('id', id);
      _products.removeWhere((p) => p.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete product: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Uploads pre-compressed JPEG bytes to the `product-images` Storage
  /// bucket and returns the public URL. The object path is scoped under
  /// the current tenant id so the RLS policies (see migration
  /// `20260520140000_products_image_url_and_storage_bucket.sql`) accept
  /// the write. Throws via the returned exception on network failure so
  /// the caller can surface a toast and abort the product save.
  Future<String> uploadProductImage(Uint8List jpegBytes) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) {
      throw StateError('No store selected.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$tenantId/$ts-${_uuid.v4()}.jpg';
    await supabase.storage.from('product-images').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const sb.FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: false,
          ),
        );
    return supabase.storage.from('product-images').getPublicUrl(path);
  }

  /// Uploads a store logo (already JPEG-encoded) and returns its public URL.
  /// Reuses the product-images bucket under a `logos/` prefix.
  Future<String> uploadStoreLogo(Uint8List jpegBytes) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) {
      throw StateError('No store selected.');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$tenantId/logo-$ts.jpg';
    await supabase.storage.from('product-images').uploadBinary(
          path,
          jpegBytes,
          fileOptions: const sb.FileOptions(
            contentType: 'image/jpeg',
            cacheControl: '3600',
            upsert: true,
          ),
        );
    return supabase.storage.from('product-images').getPublicUrl(path);
  }

  /// Saves (or clears, when [url] is null) the current store's logo URL on the
  /// tenant row and updates the in-memory tenant so login / top bar / receipts
  /// pick it up immediately. Returns null on success or a user-safe error.
  Future<String?> setTenantLogo(String? url) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('tenants')
          .update({'logo_url': url}).eq('id', tenantId);
      tenant?.logoUrl = url;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (_) {
      return 'Could not save the logo. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Receipt printer (single default, persisted in printer_configs) ──
  PrinterConfig? _printer;
  PrinterConfig? get printerConfig => _printer;
  bool get hasPrinter => _printer != null;

  Future<void> _loadPrinter() async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return;
    try {
      final rows = await supabase
          .from('printer_configs')
          .select('*')
          .eq('tenant_id', tenantId)
          .order('sort_order')
          .limit(1);
      _printer = (rows as List).isNotEmpty
          ? PrinterConfig.fromRow(rows.first)
          : null;
      // Warm up the saved Bluetooth printer in the background so the first
      // print after launch connects instantly — no manual reconnect needed.
      _warmUpPrinter();
    } catch (e) {
      if (kDebugMode) debugPrint('Load printer failed: $e');
    }
  }

  bool _warmingUpPrinter = false;

  /// Best-effort background reconnect to the saved BLE printer. The outer loop
  /// only waits for the Bluetooth *adapter* to power on (often cold right at
  /// launch) — once it's on we make a SINGLE [BtPrinter.connect] call, which
  /// already retries internally. (Looping connect here too would multiply into
  /// dozens of attempts and spam the log when the printer is offline.)
  void _warmUpPrinter() {
    final p = _printer;
    if (p == null ||
        p.transport != PrinterTransport.bluetooth ||
        (p.bluetoothId ?? '').isEmpty) {
      return;
    }
    if (_warmingUpPrinter) return; // don't stack concurrent warm-ups
    _warmingUpPrinter = true;
    unawaited(() async {
      try {
        for (var attempt = 0; attempt < 5; attempt++) {
          if (await BtPrinter.isConnected) return; // already up
          if (await BtPrinter.isEnabled()) {
            // BT is on — one connect attempt (it retries internally), then
            // stop whether it succeeds or the printer is simply offline.
            await BtPrinter.connect(p.bluetoothId!);
            return;
          }
          // BT still powering on — wait and re-check.
          await Future.delayed(Duration(milliseconds: 800 + attempt * 600));
        }
      } finally {
        _warmingUpPrinter = false;
      }
    }());
  }

  /// Saves the chosen Bluetooth printer as the store's single default printer
  /// (replaces any existing). Returns null on success.
  Future<String?> saveBluetoothPrinter({
    required String name,
    required String address,
    required int paperWidth,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase.from('printer_configs').delete().eq('tenant_id', tenantId);
      final cfg = PrinterConfig(
        id: _uuid.v4(),
        name: name,
        role: PrinterRole.receipt,
        transport: PrinterTransport.bluetooth,
        bluetoothId: address,
        paperWidth: paperWidth,
        autoPrint: true,
      );
      final inserted = await supabase
          .from('printer_configs')
          .insert(cfg.toRowPayload(tenantId))
          .select()
          .single();
      _printer = PrinterConfig.fromRow(inserted);
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not save the printer. Please try again.';
    }
  }

  // ───── Cashier shift / Z-reading ──────────────────────────────────────
  CashierShift? _shift;
  CashierShift? get currentShift => _shift;
  bool get hasOpenShift => _shift != null && _shift!.isOpen;

  Future<void> _loadShift() async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return;
    try {
      final rows = await supabase
          .from('cashier_shifts')
          .select('*')
          .eq('tenant_id', tenantId)
          .eq('status', 'open')
          .order('opened_at', ascending: false)
          .limit(1);
      _shift = (rows as List).isNotEmpty
          ? CashierShift.fromRow(rows.first)
          : null;
    } catch (e) {
      if (kDebugMode) debugPrint('Load shift failed: $e');
    }
  }

  /// Live sales totals since the current shift opened (by payment method).
  Future<ShiftTotals> shiftTotals() {
    final shift = _shift;
    if (shift == null) return Future.value(const ShiftTotals());
    return _salesTotals(shift.openedAt.toUtc(), null);
  }

  /// Sales totals for the local calendar day (for a "today's sales" report).
  Future<ShiftTotals> salesTotalsForToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _salesTotals(start.toUtc(), start.add(const Duration(days: 1)).toUtc());
  }

  /// Past + current shifts, newest first.
  Future<List<CashierShift>> fetchShifts({int limit = 30}) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return const [];
    try {
      final rows = await supabase
          .from('cashier_shifts')
          .select('*')
          .eq('tenant_id', tenantId)
          .order('opened_at', ascending: false)
          .limit(limit);
      return [
        for (final r in rows as List)
          CashierShift.fromRow(r as Map<String, dynamic>)
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Aggregates paid-order totals + cash/card/other splits over a UTC window.
  Future<ShiftTotals> _salesTotals(DateTime sinceUtc, DateTime? untilUtc) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return const ShiftTotals();
    try {
      final base = supabase
          .from('orders')
          .select('total_cents, status, '
              'payments(method, amount_cents, refunded)')
          .eq('tenant_id', tenantId)
          .gte('created_at', sinceUtc.toIso8601String());
      final rows = untilUtc != null
          ? await base.lt('created_at', untilUtc.toIso8601String())
          : await base;
      var cash = 0, card = 0, other = 0, total = 0, count = 0;
      for (final r in rows as List) {
        final m = r as Map<String, dynamic>;
        if (m['status'] != 'paid') continue;
        total += (m['total_cents'] as int?) ?? 0;
        count++;
        for (final p in (m['payments'] as List? ?? const [])) {
          final pm = p as Map<String, dynamic>;
          if (pm['refunded'] == true) continue;
          final amt = (pm['amount_cents'] as int?) ?? 0;
          switch (pm['method']) {
            case 'cash':
              cash += amt;
              break;
            case 'card':
              card += amt;
              break;
            default:
              other += amt;
          }
        }
      }
      return ShiftTotals(
        cashSalesCents: cash,
        cardSalesCents: card,
        otherSalesCents: other,
        totalSalesCents: total,
        orderCount: count,
      );
    } catch (_) {
      return const ShiftTotals();
    }
  }

  /// Opens a cashier shift with a starting cash float. Returns null on success.
  /// Reads the tenant's non-resettable counters (accumulated grand total,
  /// Z-counter, last invoice number) for BIR Z-readings + reports.
  Future<({int grandTotal, int zCounter, int lastNumber})>
      _fetchCounters() async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return (grandTotal: 0, zCounter: 0, lastNumber: 0);
    try {
      final rows = await supabase
          .from('tenant_order_counters')
          .select('grand_total_cents, z_counter, last_number')
          .eq('tenant_id', tenantId)
          .limit(1);
      if (rows.isEmpty) {
        return (grandTotal: 0, zCounter: 0, lastNumber: 0);
      }
      final r = rows.first;
      return (
        grandTotal: (r['grand_total_cents'] as num?)?.toInt() ?? 0,
        zCounter: (r['z_counter'] as int?) ?? 0,
        lastNumber: (r['last_number'] as int?) ?? 0,
      );
    } catch (_) {
      return (grandTotal: 0, zCounter: 0, lastNumber: 0);
    }
  }

  Future<String?> openShift(int openingFloatCents) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (_shift != null) return 'A shift is already open.';
    try {
      final counters = await _fetchCounters();
      final inserted = await supabase
          .from('cashier_shifts')
          .insert({
            'tenant_id': tenantId,
            'status': 'open',
            'opened_by': supabase.auth.currentUser?.id,
            'opened_by_name': currentStaff?.name ??
                currentOwner?.displayName ??
                'Cashier',
            'opening_float_cents': openingFloatCents,
            'beginning_gt_cents': counters.grandTotal,
          })
          .select()
          .single();
      _shift = CashierShift.fromRow(inserted);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') return 'A shift is already open.';
      return 'Could not open the shift. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Closes the current shift, reconciling counted cash against expected.
  /// Returns the closed shift (with the Z-reading numbers) or null on failure.
  Future<CashierShift?> closeShift(int countedCashCents) async {
    final shift = _shift;
    if (shift == null) return null;
    final tenantId = _currentTenantDbId;
    final totals = await shiftTotals();
    final expected = shift.openingFloatCents + totals.cashSalesCents;
    final overShort = countedCashCents - expected;
    // Snapshot the ending grand total + advance the non-resettable Z-counter.
    final counters = await _fetchCounters();
    final newZ = counters.zCounter + 1;
    if (tenantId != null) {
      try {
        await supabase
            .from('tenant_order_counters')
            .update({'z_counter': newZ}).eq('tenant_id', tenantId);
      } catch (_) {/* best effort */}
    }
    try {
      final updated = await supabase
          .from('cashier_shifts')
          .update({
            'status': 'closed',
            'closed_by': supabase.auth.currentUser?.id,
            'closed_by_name': currentStaff?.name ??
                currentOwner?.displayName ??
                'Cashier',
            'closed_at': DateTime.now().toUtc().toIso8601String(),
            'counted_cash_cents': countedCashCents,
            'expected_cash_cents': expected,
            'over_short_cents': overShort,
            'cash_sales_cents': totals.cashSalesCents,
            'total_sales_cents': totals.totalSalesCents,
            'order_count': totals.orderCount,
            'ending_gt_cents': counters.grandTotal,
            'z_counter': newZ,
          })
          .eq('id', shift.id)
          .select()
          .single();
      final closed = CashierShift.fromRow(updated);
      _shift = null;
      notifyListeners();
      return closed;
    } catch (_) {
      return null;
    }
  }

  // ───── BIR exports (Phase 2 e-Journal / Phase 4 eSales + EIS) ─────

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Electronic Journal — chronological text of every invoice (with lines +
  /// status) for a date range. Inclusive of both end days (local time).
  Future<String> buildEJournal(DateTime fromLocal, DateTime toLocal) async {
    final tenantId = _currentTenantDbId;
    final t = tenant;
    if (tenantId == null || t == null) return 'No store selected.';
    final fromUtc = DateTime(fromLocal.year, fromLocal.month, fromLocal.day)
        .toUtc();
    final toUtc = DateTime(toLocal.year, toLocal.month, toLocal.day)
        .add(const Duration(days: 1))
        .toUtc();
    final rows = await supabase
        .from('orders')
        .select('order_number, status, total_cents, discount_cents, '
            'created_at, sc_pwd_type, '
            'order_lines(sellable_name, quantity, line_total_cents)')
        .eq('tenant_id', tenantId)
        .gte('created_at', fromUtc.toIso8601String())
        .lt('created_at', toUtc.toIso8601String())
        .order('created_at');
    final b = StringBuffer();
    b.writeln('ELECTRONIC JOURNAL');
    b.writeln(t.businessName);
    if ((t.tin ?? '').isNotEmpty) {
      b.writeln('TIN: ${t.tin}   MIN: ${t.birMin ?? '-'}   SN: ${t.birSerial ?? '-'}');
    }
    b.writeln('Period: ${_stamp(fromLocal)} to ${_stamp(toLocal)}');
    b.writeln('=' * 42);
    final list = rows as List;
    for (final r in list) {
      final m = r as Map<String, dynamic>;
      final dt = DateTime.parse(m['created_at'] as String).toLocal();
      final no = (m['order_number'] as int?) ?? 0;
      final st = ((m['status'] as String?) ?? '').toUpperCase();
      b.writeln(
          '${_stamp(dt)}  INV ${no.toString().padLeft(7, '0')}  $st');
      for (final l in (m['order_lines'] as List? ?? const [])) {
        final lm = l as Map<String, dynamic>;
        b.writeln('   ${lm['quantity']}x ${lm['sellable_name']}'
            '  ${Money((lm['line_total_cents'] as int?) ?? 0).formatted}');
      }
      if ((m['sc_pwd_type'] as String?) != null) {
        b.writeln('   [${(m['sc_pwd_type'] as String).toUpperCase()} 20% + VAT-EXEMPT]');
      }
      b.writeln('   TOTAL ${Money((m['total_cents'] as int?) ?? 0).formatted}');
    }
    b.writeln('=' * 42);
    b.writeln('Invoices: ${list.length}');
    return b.toString();
  }

  /// Monthly sales summary for the BIR eSales portal (one machine).
  Future<String> buildESalesSummary(int year, int month) async {
    final tenantId = _currentTenantDbId;
    final t = tenant;
    if (tenantId == null || t == null) return 'No store selected.';
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 1);
    final rows = await supabase
        .from('orders')
        .select('order_number, status, total_cents, sc_pwd_type')
        .eq('tenant_id', tenantId)
        .gte('created_at', from.toUtc().toIso8601String())
        .lt('created_at', to.toUtc().toIso8601String());
    var gross = 0, exemptGross = 0, lastNo = 0, count = 0;
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      if (m['status'] != 'paid') continue;
      final tot = (m['total_cents'] as int?) ?? 0;
      gross += tot;
      count++;
      final no = (m['order_number'] as int?) ?? 0;
      if (no > lastNo) lastNo = no;
      if ((m['sc_pwd_type'] as String?) != null) exemptGross += tot;
    }
    final vatReg = t.vatRegistered;
    final taxable = gross - exemptGross;
    final vatableNet = vatReg ? (taxable / 1.12).round() : taxable;
    final vat = vatReg ? taxable - vatableNet : 0;
    const months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'];
    final b = StringBuffer();
    b.writeln('eSALES MONTHLY SALES REPORT');
    b.writeln(t.businessName);
    b.writeln('TIN: ${t.tin ?? '-'}   Branch: ${t.branchCode}');
    b.writeln('MIN: ${t.birMin ?? '-'}   SN: ${t.birSerial ?? '-'}');
    b.writeln('Period: ${months[month]} $year');
    b.writeln('=' * 42);
    b.writeln('Last invoice no : ${lastNo.toString().padLeft(7, '0')}');
    b.writeln('Invoices        : $count');
    if (vatReg) {
      b.writeln('VATable sales   : ${Money(vatableNet).formatted}');
      b.writeln('VAT-exempt sales: ${Money(exemptGross).formatted}');
      b.writeln('VAT (12%)       : ${Money(vat).formatted}');
    } else {
      b.writeln('Non-VAT sales   : ${Money(taxable).formatted}');
      b.writeln('VAT-exempt sales: ${Money(exemptGross).formatted}');
    }
    b.writeln('-' * 42);
    b.writeln('GROSS SALES     : ${Money(gross).formatted}');
    return b.toString();
  }

  /// EIS-style JSON export of invoices for a date range (a stepping stone to
  /// the BIR Electronic Invoicing System; this produces the data, not the
  /// live transmission).
  Future<String> buildEisInvoicesJson(
      DateTime fromLocal, DateTime toLocal) async {
    final tenantId = _currentTenantDbId;
    final t = tenant;
    if (tenantId == null || t == null) return '{}';
    final fromUtc = DateTime(fromLocal.year, fromLocal.month, fromLocal.day)
        .toUtc();
    final toUtc = DateTime(toLocal.year, toLocal.month, toLocal.day)
        .add(const Duration(days: 1))
        .toUtc();
    final rows = await supabase
        .from('orders')
        .select('order_number, status, total_cents, discount_cents, '
            'created_at, sc_pwd_type, sc_pwd_name, sc_pwd_id, customer_name, '
            'order_lines(sellable_name, quantity, unit_price_cents, line_total_cents)')
        .eq('tenant_id', tenantId)
        .gte('created_at', fromUtc.toIso8601String())
        .lt('created_at', toUtc.toIso8601String())
        .order('created_at');
    final invoices = [
      for (final r in rows as List)
        if (r is Map<String, dynamic>)
          {
            'invoiceNo': (r['order_number'] as int?) ?? 0,
            'dateTime': r['created_at'],
            'status': r['status'],
            'vatExempt': r['sc_pwd_type'] != null,
            'scPwd': r['sc_pwd_type'] == null
                ? null
                : {
                    'type': r['sc_pwd_type'],
                    'name': r['sc_pwd_name'],
                    'id': r['sc_pwd_id'],
                  },
            'customer': r['customer_name'],
            'discountCents': r['discount_cents'],
            'totalCents': r['total_cents'],
            'lines': [
              for (final l in (r['order_lines'] as List? ?? const []))
                if (l is Map<String, dynamic>)
                  {
                    'name': l['sellable_name'],
                    'qty': l['quantity'],
                    'unitPriceCents': l['unit_price_cents'],
                    'lineTotalCents': l['line_total_cents'],
                  }
            ],
          }
    ];
    final doc = {
      'seller': {
        'name': t.businessName,
        'tin': t.tin,
        'branch': t.branchCode,
        'min': t.birMin,
        'sn': t.birSerial,
        'vatRegistered': t.vatRegistered,
      },
      'from': fromUtc.toIso8601String(),
      'to': toUtc.toIso8601String(),
      'count': invoices.length,
      'invoices': invoices,
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Forgets the configured printer.
  Future<void> clearPrinter() async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return;
    try {
      await supabase.from('printer_configs').delete().eq('tenant_id', tenantId);
    } catch (_) {/* best effort */}
    _printer = null;
    notifyListeners();
  }

  /// Saves the receipt/ticket layout templates + paper tail spacing.
  Future<String?> updatePrintTemplates({
    int? receiptTemplate,
    int? ticketTemplate,
    int? tailLines,
    String? font,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenant == null || tenantId == null) return 'No store selected.';
    final r = (receiptTemplate ?? tenant!.receiptTemplate).clamp(1, 3);
    final k = (ticketTemplate ?? tenant!.ticketTemplate).clamp(1, 3);
    final tail = (tailLines ?? tenant!.printTailLines).clamp(0, 8);
    final f = (font ?? tenant!.printFont) == 'b' ? 'b' : 'a';
    try {
      await supabase.from('tenants').update({
        'receipt_template': r,
        'ticket_template': k,
        'print_tail_lines': tail,
        'print_font': f,
      }).eq('id', tenantId);
      tenant!.receiptTemplate = r;
      tenant!.ticketTemplate = k;
      tenant!.printTailLines = tail;
      tenant!.printFont = f;
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not save. Please try again.';
    }
  }

  /// Saves the custom receipt header / footer text + alignment on the tenant.
  /// Pass an empty string to clear a text field. Returns null on success.
  Future<String?> updateReceiptText(
      {String? header, String? footer, String? align}) async {
    final tenantId = _currentTenantDbId;
    if (tenant == null || tenantId == null) return 'No store selected.';
    final h = header?.trim();
    final f = footer?.trim();
    final a = (align == 'left') ? 'left' : 'center';
    try {
      await supabase.from('tenants').update({
        'receipt_header': (h == null || h.isEmpty) ? null : h,
        'receipt_footer': (f == null || f.isEmpty) ? null : f,
        'receipt_align': a,
      }).eq('id', tenantId);
      tenant!.receiptHeader = (h == null || h.isEmpty) ? null : h;
      tenant!.receiptFooter = (f == null || f.isEmpty) ? null : f;
      tenant!.receiptAlign = a;
      notifyListeners();
      return null;
    } catch (_) {
      return 'Could not save. Please try again.';
    }
  }

  // ───── product types (Maintenance → Product types) ───────────────

  List<ProductType> _productTypes = [];
  List<ProductType> get productTypes => List.unmodifiable(_productTypes);

  ProductType? productTypeById(String? id) {
    if (id == null) return null;
    for (final t in _productTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<String?> addProductType(ProductType t) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (t.name.trim().isEmpty) return 'Type name is required.';
    try {
      final row = await supabase.from('product_types').insert({
        'tenant_id': tenantId,
        'name': t.name.trim(),
        'icon_name': t.iconName,
        'supports_modifiers': t.supportsModifiers,
        'deducts_stock': t.deductsStock,
        'is_system': false,
        'sort_order': t.sortOrder,
        'separate_sales': t.separateSales,
      }).select('*').single();
      _productTypes.add(ProductType.fromRow(row));
      _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A type named "${t.name}" already exists.';
      }
      return 'Could not add type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateProductType(ProductType updated) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('product_types').update({
        'name': updated.name.trim(),
        'icon_name': updated.iconName,
        'supports_modifiers': updated.supportsModifiers,
        'deducts_stock': updated.deductsStock,
        'sort_order': updated.sortOrder,
        'separate_sales': updated.separateSales,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', updated.id);
      final i = _productTypes.indexWhere((t) => t.id == updated.id);
      if (i >= 0) _productTypes[i] = updated;
      // Keep the list ordered by sort_order (matches updateCategory) so a
      // re-icon/rename that changes order reflects immediately.
      _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Refresh denormalized typeName on any products using this type.
      for (final p in _products) {
        if (p.typeId == updated.id) p.typeName = updated.name.trim();
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A type named "${updated.name}" already exists.';
      }
      return 'Could not update type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── Drag-to-reorder (Sell "arrange mode") ──────────────────────────
  // Each reassigns sort_order to (index+1)*10 over the given ordering. Memory
  // updates + notifyListeners happen SYNCHRONOUSLY (so the dropped item doesn't
  // snap back), then the rows are written to Supabase. Spacing stays in tens so
  // single inserts elsewhere don't force a renumber.

  /// Persist a new ordering of the product types. Returns null on success or a
  /// user-safe error string if the DB write failed.
  Future<String?> reorderProductTypes(List<ProductType> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _productTypes.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders(
        'product_types', ordered, (t) => t.id, (t) => t.sortOrder);
  }

  /// Persist a new ordering of the sub-types within a single product type.
  Future<String?> reorderCategories(List<cat.Category> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders(
        'categories', ordered, (c) => c.id, (c) => c.sortOrder);
  }

  /// Persist a new ordering of the products in the currently-shown subset.
  Future<String?> reorderProducts(List<CafeItem> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = (i + 1) * 10;
    }
    _products.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
    return _writeSortOrders('products', ordered, (p) => p.id, (p) => p.sortOrder);
  }

  /// Writes each row's sort_order. Returns null on success, or the first
  /// error encountered (and how many rows it managed to save).
  Future<String?> _writeSortOrders<T>(String table, List<T> ordered,
      String Function(T) idOf, int Function(T) sortOf) async {
    var saved = 0;
    for (final item in ordered) {
      try {
        // `.select()` forces the round-trip AND returns the affected rows, so a
        // silent 0-row update (e.g. an RLS/permission block) surfaces as an
        // error instead of looking like it saved and then reverting on reload.
        final res = await supabase
            .from(table)
            .update({'sort_order': sortOf(item)})
            .eq('id', idOf(item))
            .select('id');
        if ((res as List).isEmpty) {
          return 'Order not saved — the server rejected the update for "$table" '
              '(saved $saved of ${ordered.length}). This is usually a '
              'permissions issue.';
        }
        saved++;
      } catch (e) {
        if (kDebugMode) debugPrint('Reorder ($table) row failed: $e');
        return 'Saved $saved of ${ordered.length}. $e';
      }
    }
    return null;
  }

  Future<String?> removeProductType(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('product_types').delete().eq('id', id);
      _productTypes.removeWhere((x) => x.id == id);
      // Products lose their typeId on cascade SET NULL.
      for (final p in _products) {
        if (p.typeId == id) {
          p.typeId = null;
          p.typeName = '';
        }
      }
      // Sub-types (categories) under this type also lose their link (DB SET
      // NULL) — mirror it in memory so the Sell tree doesn't point at a dead
      // type until the next reload. They fall into the "Other" bucket.
      for (final c in _categories) {
        if (c.typeId == id) c.typeId = null;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete type: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Converts a product's [modifierGroupIds] (DB FKs to master groups)
  /// into the runtime [ModifierGroup] shape the Sell / cart code reads.
  /// Skips ids that don't resolve so a deleted master group doesn't crash
  /// the Sell view.
  List<ModifierGroup> _runtimeModifierGroups(List<String> ids) {
    final out = <ModifierGroup>[];
    for (final id in ids) {
      final master = _modifierGroups.where((m) => m.id == id).firstOrNull;
      if (master == null) continue;
      out.add(ModifierGroup(
        id: master.id,
        name: master.name,
        required: master.required,
        defaultIndex: master.defaultIndex,
        options: master.options
            .map((o) => ModifierOption(
                  id: o.id,
                  name: o.name,
                  priceDelta: o.priceDelta,
                ))
            .toList(),
      ));
    }
    return out;
  }

  // ───── recipe expansion + auto-deduct ─────
  List<RecipeLine> expandRecipe(
    CafeItem product,
    Map<String, String> selections, {
    Map<String, int>? addOnQuantities,
  }) {
    final result = <RecipeLine>[];

    // Adjustments for the selected options. Each one can BOTH scale base
    // ingredients (per-ingredient [lineMultipliers], or its default
    // [multiplier]) AND add extra lines — so an option like "Large" scales
    // and "Iced" adds ice, and an option can do both.
    final activeAdj = product.modifierAdjustments
        .where((adj) => selections[adj.groupId] == adj.optionId)
        .toList();

    for (final line in product.recipe) {
      var m = 1.0;
      for (final adj in activeAdj) {
        m *= adj.lineMultipliers[line.inventoryItemId] ?? adj.multiplier;
      }
      result.add(RecipeLine(
        inventoryItemId: line.inventoryItemId,
        quantity: line.quantity * m,
      ));
    }
    for (final adj in activeAdj) {
      result.addAll(adj.addLines);
    }

    if (addOnQuantities != null) {
      for (final entry in addOnQuantities.entries) {
        if (entry.value <= 0) continue;
        final addOn = addOns.where((a) => a.id == entry.key).firstOrNull;
        if (addOn == null) continue;
        for (final line in addOn.recipe) {
          result.add(RecipeLine(
            inventoryItemId: line.inventoryItemId,
            quantity: line.quantity * entry.value,
          ));
        }
      }
    }
    return result;
  }

  /// True if one unit of [product] can be sold given current stock. Used
  /// by the Sell grid to auto-hide products that have run out (so the
  /// cashier never sees a tile they can't actually fulfil) and by the
  /// tender flow to short-circuit obvious cases before re-running the
  /// full cart aggregation. Products with no recipe (Services) always
  /// return true; products whose type is flagged `deducts_stock = false`
  /// also bypass.
  /// Store-wide master switch (mirrors the tenant flag). When false, NO
  /// product deducts stock or is blocked by it — the store sells freely.
  bool get inventoryTrackingEnabled =>
      tenant?.inventoryTrackingEnabled ?? true;

  /// Whether [product] should draw down / be limited by inventory. Decided
  /// per-product: the store master switch is on AND the product's own
  /// "Track inventory" toggle is on. (The product type no longer gates this —
  /// it's set on each product.)
  bool tracksStock(CafeItem product) {
    if (!inventoryTrackingEnabled) return false;
    return product.trackInventory;
  }

  bool canFulfillOne(CafeItem product) {
    if (!tracksStock(product)) return true;
    if (product.recipe.isEmpty) return true;
    for (final line in product.recipe) {
      final inv = _inventory
          .where((i) => i.id == line.inventoryItemId)
          .firstOrNull;
      if (inv == null) continue; // tolerate orphan refs — block at tender
      if (inv.currentStock < line.quantity) return false;
    }
    return true;
  }

  /// Sentinel for "not limited by recipe stock" — products with no recipe or
  /// a non-stock type (Service) can always be made.
  static const int kUnlimitedBuild = 1 << 30;

  /// How many whole units of [product] can be made from current inventory,
  /// using its base recipe (ignores modifier multipliers). Drives the Sell
  /// "Out of stock" badge and the Products "can make N" readout.
  ///
  /// Returns [kUnlimitedBuild] when the product doesn't draw down stock or
  /// has no recipe. An ingredient that's been deleted (orphan ref) caps the
  /// count at 0 — the dish can't be assembled from a missing ingredient.
  int buildableCount(CafeItem product) {
    if (!tracksStock(product)) return kUnlimitedBuild;
    if (product.recipe.isEmpty) return kUnlimitedBuild;
    var maxBuild = kUnlimitedBuild;
    for (final line in product.recipe) {
      if (line.quantity <= 0) continue; // a 0-qty line never limits
      final inv =
          _inventory.where((i) => i.id == line.inventoryItemId).firstOrNull;
      if (inv == null) return 0; // missing ingredient → can't make any
      final canMake = (inv.currentStock / line.quantity).floor();
      if (canMake < maxBuild) maxBuild = canMake;
      if (maxBuild <= 0) return 0;
    }
    return maxBuild;
  }

  /// True when [product] has a recipe but at least one ingredient is short
  /// (so it shows on Sell as "Not available" rather than being hidden).
  bool isOutOfStock(CafeItem product) => buildableCount(product) <= 0;

  /// Sums the cart's projected inventory deductions per inventory item id
  /// (taking modifier multipliers + add-ons into account). Used by the
  /// tender flow to refuse a sale that would push any item below zero.
  /// Lines whose product type opts out of stock deduction are skipped.
  Map<String, double> projectedCartDeductions() {
    final totals = <String, double>{};
    for (final line in cart.lines) {
      final kind = line.kind;
      if (kind is! CartLineCafe) continue;
      final product = productById(kind.item.id);
      if (product == null) continue;
      if (!tracksStock(product)) continue;
      final expanded = expandRecipe(
        product,
        kind.selections,
        addOnQuantities: kind.addOnQuantities,
      );
      for (final r in expanded) {
        totals[r.inventoryItemId] =
            (totals[r.inventoryItemId] ?? 0) + (r.quantity * line.quantity);
      }
    }
    return totals;
  }

  /// Returns a human-readable error if any cart deduction would oversell
  /// an inventory item, else null. Plain-English so we can surface the
  /// message straight to the cashier in a toast.
  String? validateCartStock() {
    final needed = projectedCartDeductions();
    for (final entry in needed.entries) {
      final inv = _inventory
          .where((i) => i.id == entry.key)
          .firstOrNull;
      if (inv == null) continue;
      if (inv.currentStock < entry.value) {
        final short = (entry.value - inv.currentStock).toStringAsFixed(0);
        return 'Not enough ${inv.name} — need $short more '
            '${inv.displayUnit} than what\'s on hand. '
            'Restock on the Stock page or remove the item from the cart.';
      }
    }
    return null;
  }

  /// Optimistically deducts the cart's expanded recipe from the local
  /// inventory cache. The DB-side `create_paid_order` RPC also deducts
  /// server-side so the canonical state stays correct; this just keeps
  /// the UI in sync between the sale completing and the next inventory
  /// refresh.
  Map<String, double> deductCartFromInventory() {
    final summary = <String, double>{};

    for (final line in cart.lines) {
      final kind = line.kind;
      if (kind is! CartLineCafe) continue;
      final product = productById(kind.item.id);
      if (product == null) continue;
      // Skip stock deduction when this product isn't tracked (master switch
      // off, per-product toggle off, or a non-stock type like Service).
      if (!tracksStock(product)) continue;
      final expanded = expandRecipe(
        product,
        kind.selections,
        addOnQuantities: kind.addOnQuantities,
      );
      for (final r in expanded) {
        final invIdx = _inventory
            .indexWhere((it) => it.id == r.inventoryItemId);
        if (invIdx < 0) continue;
        final totalQty = r.quantity * line.quantity;
        _inventory[invIdx].currentStock =
            (_inventory[invIdx].currentStock - totalQty)
                .clamp(0, double.infinity);
        summary.update(r.inventoryItemId, (v) => v + totalQty,
            ifAbsent: () => totalQty);
      }
    }
    if (summary.isNotEmpty) notifyListeners();
    return summary;
  }

  // ───── inventory categories (Supabase-backed) ─────────────────────

  /// Owners manage these in Maintenance → Inventory categories.
  /// `inventory_items.inventory_category_id` is the canonical FK.
  List<InventoryCategory> _inventoryCategories = [];
  List<InventoryCategory> get inventoryCategories =>
      List.unmodifiable(_inventoryCategories);

  /// Lookup helper — returns null if the id isn't in the cache (e.g. the
  /// category was just deleted while items still reference it; UI falls
  /// back to the denormalized text `inventory_items.category`).
  InventoryCategory? inventoryCategoryById(String? id) {
    if (id == null) return null;
    for (final c in _inventoryCategories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<String?> addInventoryCategory(InventoryCategory c) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (c.name.trim().isEmpty) return 'Category name is required.';
    try {
      final row = await supabase
          .from('inventory_categories')
          .insert({
            'tenant_id': tenantId,
            'name': c.name.trim(),
            'icon_name': c.iconName,
            'sort_order': c.sortOrder,
          })
          .select('*')
          .single();
      _inventoryCategories.add(InventoryCategory.fromRow(row));
      _inventoryCategories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A category named "${c.name}" already exists.';
      }
      return 'Could not add category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateInventoryCategory(InventoryCategory updated) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Category name is required.';
    try {
      final row = await supabase
          .from('inventory_categories')
          .update({
            'name': updated.name.trim(),
            'icon_name': updated.iconName,
            'sort_order': updated.sortOrder,
          })
          .eq('id', updated.id)
          .select('*')
          .single();
      final fresh = InventoryCategory.fromRow(row);
      final i = _inventoryCategories.indexWhere((c) => c.id == fresh.id);
      if (i >= 0) _inventoryCategories[i] = fresh;
      _inventoryCategories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Items already point at the same id — denormalized `category` text
      // on each item is updated lazily next time the item is saved (or
      // on the next tenant reload). Cheap to refresh names here.
      for (final it in _inventory) {
        if (it.categoryId == fresh.id) it.category = fresh.name;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeInventoryCategory(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('inventory_categories').delete().eq('id', id);
      _inventoryCategories.removeWhere((c) => c.id == id);
      // Items keep their text `category` as a display fallback; the FK is
      // already nulled by the ON DELETE SET NULL clause on the column.
      for (final it in _inventory) {
        if (it.categoryId == id) it.categoryId = null;
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete category: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── inventory (Supabase-backed) ───────────────────────────────

  List<InventoryItem> _inventory = [];
  List<InventoryItem> get inventory => List.unmodifiable(_inventory);

  int get lowStockCount =>
      _inventory.where((i) => i.isLowStock).length;

  Future<String?> addInventoryItem(InventoryItem item) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    if (item.name.trim().isEmpty) return 'Item name is required.';
    try {
      final row = await supabase
          .from('inventory_items')
          .insert(item.toRowPayload(tenantId))
          .select('*')
          .single();
      _inventory.add(InventoryItem.fromRow(row));
      _inventory.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'An inventory item named "${item.name}" already exists.';
      }
      return 'Could not add item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateInventoryItem(InventoryItem updated) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('inventory_items')
          .update(updated.toRowPayload(tenantId)
            ..['updated_at'] = DateTime.now().toIso8601String())
          .eq('id', updated.id);
      final i = _inventory.indexWhere((it) => it.id == updated.id);
      if (i >= 0) _inventory[i] = updated;
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeInventoryItem(String id) async {
    if (_currentTenantDbId == null) return 'No store selected.';
    try {
      await supabase.from('inventory_items').delete().eq('id', id);
      _inventory.removeWhere((it) => it.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete item: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> adjustStock(String id, double delta) async {
    final i = _inventory.indexWhere((it) => it.id == id);
    if (i < 0) return 'Item not found.';
    final item = _inventory[i];
    final newQty =
        (item.currentStock + delta).clamp(0.0, double.infinity);
    item.currentStock = newQty;
    final err = await updateInventoryItem(item);
    return err;
  }

  Future<String?> restock(String id, double qty,
      {double? newCostPerUnit}) async {
    if (qty <= 0) return 'Quantity must be positive.';
    final i = _inventory.indexWhere((it) => it.id == id);
    if (i < 0) return 'Item not found.';
    final item = _inventory[i];
    item.currentStock += qty;
    item.lastRestockedAt = DateTime.now();
    if (newCostPerUnit != null && newCostPerUnit > 0) {
      item.costPerUnit = newCostPerUnit;
    }
    return updateInventoryItem(item);
  }

  // ───── employee roles (Supabase-backed; Maintenance → Roles) ─────

  /// Cached list of roles for the active tenant. Populated by
  /// [_restoreTenantFromDb]; mutated by the role CRUD methods.
  List<EmployeeRole> _employeeRoles = [];
  List<EmployeeRole> get employeeRoles => List.unmodifiable(_employeeRoles);

  EmployeeRole? roleById(String? id) {
    if (id == null) return null;
    for (final r in _employeeRoles) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Seeds Owner / Cashier / Inventory Manager for a freshly created tenant.
  /// Idempotent — relies on the unique(tenant_id, name) constraint to no-op
  /// if defaults already exist (e.g. from the SQL backfill).
  Future<void> _seedDefaultEmployeeRoles(String tenantId) async {
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
  Future<void> _seedDefaultPayrollSurface(String tenantId) async {
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

  /// Seeds the default product types for a freshly created tenant and returns
  /// a lowercased name -> id map so onboarding can link the seeded categories
  /// (sub-types) to their parent type. Idempotent via unique(tenant_id, name):
  /// on a duplicate re-run it re-selects the existing rows so the map is always
  /// populated. Returns an empty map on hard failure (callers must tolerate it
  /// — categories simply seed with a null type_id → "Other").
  Future<Map<String, String>> _seedDefaultProductTypes(String tenantId) async {
    // Three behavior buckets is all that's needed — types only control
    // whether an item has size/temp options and whether it deducts stock.
    // Menu grouping (Coffee, Tea, Books, Food…) is handled by sub-types.
    final rows = [
      {
        'tenant_id': tenantId,
        'name': 'Drinks',
        'icon_name': 'local_cafe_outlined',
        // Drinks have Size / Temperature / Strength options + add-ons.
        'supports_modifiers': true,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 10,
      },
      {
        'tenant_id': tenantId,
        'name': 'Foods',
        'icon_name': 'restaurant_outlined',
        // Rung up flat (no size/temp); still deducts recipe ingredients.
        'supports_modifiers': false,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 20,
      },
      {
        'tenant_id': tenantId,
        'name': 'Pastries',
        'icon_name': 'bakery_dining_outlined',
        'supports_modifiers': false,
        'deducts_stock': true,
        'is_system': true,
        'sort_order': 30,
      },
    ];
    try {
      final inserted = await supabase
          .from('product_types')
          .insert(rows)
          .select('id, name');
      return _typeIdMap(inserted);
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        // Already seeded — re-fetch the existing rows so the map is populated.
        try {
          final existing = await supabase
              .from('product_types')
              .select('id, name')
              .eq('tenant_id', tenantId);
          return _typeIdMap(existing);
        } catch (_) {
          return {};
        }
      }
      if (kDebugMode) {
        debugPrint('Seed default product types failed: ${e.message}');
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Builds a lowercased product-type name -> id map from PostgREST rows.
  Map<String, String> _typeIdMap(dynamic rows) {
    final map = <String, String>{};
    for (final r in (rows as List)) {
      final m = r as Map<String, dynamic>;
      final name = (m['name'] as String?)?.toLowerCase();
      final id = m['id'] as String?;
      if (name != null && id != null) map[name] = id;
    }
    return map;
  }


  Future<String?> addEmployeeRole(EmployeeRole r) async {
    final tenantId = _currentTenantDbId;
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
    if (_currentTenantDbId == null) return 'No store selected.';
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
    if (_currentTenantDbId == null) return 'No store selected.';
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

  // ───── employees (Supabase-backed) ─────

  List<Employee> _employees = [];
  List<Employee> get employees => List.unmodifiable(_employees);

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
    final tenantId = _currentTenantDbId;
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
    final tenantId = _currentTenantDbId;
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
    if (_currentTenantDbId == null) return 'No store selected.';
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
  /// success. Mirrors [setOwnerPin] — 4–8 digits, atomic upsert.
  Future<String?> setCashierPin(String employeeId, String pin) async {
    final tenantId = _currentTenantDbId;
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

  // ───── payroll rules + leave types + employment templates ─────────

  PayrollRules _payrollRules = PayrollRules();
  PayrollRules get payrollRules => _payrollRules;

  List<LeaveType> _leaveTypes = [];
  List<LeaveType> get leaveTypes => List.unmodifiable(_leaveTypes);

  List<EmploymentTemplate> _employmentTemplates = [];
  List<EmploymentTemplate> get employmentTemplates =>
      List.unmodifiable(_employmentTemplates);

  /// Convenience for the Add Employee modal: returns the template that
  /// matches an employment type, or null if the owner deleted/never had one.
  EmploymentTemplate? templateFor(EmploymentType t) {
    for (final tpl in _employmentTemplates) {
      if (tpl.employmentType == t) return tpl;
    }
    return null;
  }

  Future<String?> updatePayrollRules(PayrollRules updated) async {
    final tenantId = _currentTenantDbId;
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
    final tenantId = _currentTenantDbId;
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
    if (_currentTenantDbId == null) return 'No store selected.';
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
    if (_currentTenantDbId == null) return 'No store selected.';
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
    final tenantId = _currentTenantDbId;
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
  // trusts the policy. The original in-memory maps remain as the
  // local cache the UI binds to — server writes update both DB and
  // cache so the UI repaints immediately while persistence happens
  // in the background.

  List<TimeEntry> get timeEntries {
    final t = tenant;
    if (t == null) return const [];
    return _timeEntriesByTenant.putIfAbsent(t.id, () => <TimeEntry>[]);
  }

  List<PayrollRun> get payrollRuns {
    final t = tenant;
    if (t == null) return const [];
    return _payrollRunsByTenant.putIfAbsent(t.id, () => <PayrollRun>[]);
  }

  /// Hours logged for [employeeId] between [from] (inclusive) and [to] (inclusive).
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
    final t = tenant;
    final tenantId = _currentTenantDbId;
    if (t == null || tenantId == null) return 'No store selected.';
    final day = DateTime(date.year, date.month, date.day);
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final list =
        _timeEntriesByTenant.putIfAbsent(t.id, () => <TimeEntry>[]);
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

  /// Build a fresh payroll run snapshot for the given period. Pulls
  /// each active employee's hours from [timeEntries] and freezes
  /// their rate / salary at the time of generation. The run + each
  /// slip persist to the DB so the period closes cleanly.
  Future<({PayrollRun? run, String? error})> generatePayrollRun({
    required DateTime start,
    required DateTime end,
    required PayPeriodKind kind,
  }) async {
    final t = tenant;
    final tenantId = _currentTenantDbId;
    if (t == null || tenantId == null) {
      return (run: null, error: 'No store selected.');
    }
    final slips = <Payslip>[];
    for (final emp in _employees) {
      if (emp.status == EmployeeStatus.terminated) continue;
      final hrs = hoursIn(emp.id, start, end);
      slips.add(Payslip(
        employeeId: emp.id,
        employeeName: emp.name,
        employeeRole: emp.role,
        compensationType: emp.compensationType,
        hoursWorked: hrs,
        hourlyRate: emp.hourlyRate,
        dailyRate: emp.dailyRate,
        monthlySalary: emp.monthlySalary,
      ));
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
        slips: slipRows.map(Payslip.fromRow).toList(),
      );
      _payrollRunsByTenant
          .putIfAbsent(t.id, () => <PayrollRun>[])
          .insert(0, hydrated);
      notifyListeners();
      return (run: hydrated, error: null);
    } on sb.PostgrestException catch (e) {
      return (run: null, error: 'Could not generate run: ${e.message}');
    } catch (_) {
      return (run: null, error: 'Could not reach the server. Please try again.');
    }
  }

  /// Persist edits to a single payslip (bonus / deductions / hours
  /// override). The DB row is the source of truth; the cache mirrors
  /// it. Refuses to write once the parent run is marked paid.
  Future<String?> updatePayslip(String runId, Payslip updated) async {
    final t = tenant;
    if (t == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[t.id];
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
    final t = tenant;
    if (t == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[t.id];
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
    final t = tenant;
    if (t == null) return 'No store selected.';
    final runs = _payrollRunsByTenant[t.id];
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

  // ───── staff PIN session ─────
  void signIn(Employee employee) {
    currentStaff = employee;
    notifyListeners();
  }

  void signOut() {
    currentStaff = null;
    cart.clear();
    notifyListeners();
  }

  /// Legacy plaintext-PIN lookup. PINs are now bcrypt-hashed via
  /// [setCashierPin] / `verify_cashier_pin`; this stub keeps existing
  /// callers compiling until the staff-pin login UI is rebuilt to take
  /// (employee, pin) and call the RPC. Always returns null today.
  Employee? findByPin(String pin) => null;

  // ───── Orders (Supabase money layer) ────────────────────────────────

  /// Local cache of recent orders for the active tenant. Populated by
  /// [refreshOrders] (called on Orders screen open + after a sale). Read
  /// by widgets via [recentOrders].
  List<o.Order> _orderCache = [];
  // Stable unmodifiable view — same instance until the cache actually changes,
  // so consumers can `identical()`-check to skip re-deriving (e.g. the Orders
  // screen's DB->MockOrder adaptation). Rebuilt lazily after a refresh.
  List<o.Order>? _recentOrdersView;
  List<o.Order> get recentOrders =>
      _recentOrdersView ??= List.unmodifiable(_orderCache);

  /// Refresh the [recentOrders] cache by re-fetching the last [days] days
  /// of orders for the active tenant. Safe to call repeatedly.
  Future<void> refreshOrders({int days = 7}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final fetched = await fetchOrders(since: since, limit: 200);
    _orderCache = fetched;
    _recentOrdersView = null; // invalidate the stable view
    notifyListeners();
  }


  /// Creates a paid order in Supabase from the current cart. Atomically:
  ///   • Claims next sequential order_number (per tenant, BIR-ready)
  ///   • Inserts the order, all order_lines, all payments
  ///   • Writes an audit_log entry
  /// Returns the new order id on success, or a user-safe error string.
  Future<({String? id, String? error})> createPaidOrder({
    required List<({
      String? sellableId,
      String name,
      String? categoryName,
      String emoji,
      int unitPriceCents,
      int quantity,
      int lineTotalCents,
      Map<String, dynamic>? modifiers,
      List<Map<String, dynamic>>? recipeDeductions,
    })> lines,
    required List<({
      o.OrderPaymentMethod method,
      int amountCents,
      int? tenderedCents,
      int? changeCents,
      String? reference,
    })> payments,
    String? customerName,
    String? customerPhone,
    String? notes,
    int discountCents = 0,
    String? scPwdType,
    String? scPwdName,
    String? scPwdId,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return (id: null, error: 'No store selected.');
    if (lines.isEmpty) return (id: null, error: 'Cart is empty.');
    if (payments.isEmpty) {
      return (id: null, error: 'At least one payment is required.');
    }
    try {
      final linesPayload = lines
          .map((l) => {
                'sellable_id': l.sellableId ?? '',
                'sellable_name': l.name,
                'category_name': l.categoryName,
                'emoji': l.emoji,
                'unit_price_cents': l.unitPriceCents,
                'quantity': l.quantity,
                'line_total_cents': l.lineTotalCents,
                if (l.modifiers != null) 'modifiers_json': l.modifiers,
                'recipe_deductions': l.recipeDeductions ?? const [],
              })
          .toList();
      final paymentsPayload = payments
          .map((p) => {
                'method': p.method.dbValue,
                'amount_cents': p.amountCents,
                'tendered_cents': p.tenderedCents,
                'change_cents': p.changeCents,
                'reference': p.reference,
              })
          .toList();

      // Aggregate the cart's recipe deductions client-side via expandRecipe
      // so the RPC can update inventory_items atomically alongside the
      // order insert.
      final deductionsAgg = <String, double>{};
      for (final line in cart.lines) {
        final kind = line.kind;
        if (kind is! CartLineCafe) continue;
        final product = productById(kind.item.id);
        if (product == null) continue;
        // Skip untracked products (master switch off, per-product toggle off,
        // or a non-stock type) so the server RPC isn't told to deduct them.
        if (!tracksStock(product)) continue;
        final expanded = expandRecipe(
          product,
          kind.selections,
          addOnQuantities: kind.addOnQuantities,
        );
        for (final r in expanded) {
          final total = r.quantity * line.quantity;
          deductionsAgg.update(r.inventoryItemId, (v) => v + total,
              ifAbsent: () => total);
        }
      }
      final recipeDeductionsPayload = [
        for (final e in deductionsAgg.entries)
          {'inventory_item_id': e.key, 'quantity': e.value},
      ];

      final id = await supabase.rpc('create_paid_order', params: {
        'p_tenant_id': tenantId,
        'p_branch_id': selectedBranch.id,
        'p_lines': linesPayload,
        'p_payments': paymentsPayload,
        'p_customer_name': customerName,
        'p_customer_phone': customerPhone,
        'p_notes': notes,
        'p_discount_cents': discountCents,
        // Stamp the real cashier's employee id. In an OWNER session the
        // synthesized owner-staff id isn't an employees row (the RPC would
        // reject it), so pass null there — employee_name still records who
        // operated the till.
        'p_employee_id': isOwnerSession ? null : currentStaff?.id,
        'p_employee_name': currentStaff?.name,
        'p_recipe_deductions': recipeDeductionsPayload,
        'p_sc_pwd_type': scPwdType,
        'p_sc_pwd_name': scPwdName,
        'p_sc_pwd_id': scPwdId,
      });
      return (id: id as String?, error: null);
    } on sb.PostgrestException catch (e) {
      return (id: null, error: 'Could not save order: ${e.message}');
    } catch (_) {
      return (id: null, error: 'Could not reach the server. Please try again.');
    }
  }

  /// Voids a paid order: marks it voided, puts the recipe's ingredients
  /// back into inventory, and writes an audit-log entry. Requires an
  /// authorizer PIN belonging to the Owner OR an employee whose role can
  /// authorize refunds (e.g. Manager). Rows are never deleted — the trail
  /// is preserved. Returns null on success or a user-safe error message.
  Future<String?> voidOrder({
    required String orderId,
    required String reason,
    required String authorizerPin,
  }) =>
      _reverseOrder('void_order', orderId, reason, authorizerPin);

  /// Refunds a paid order: marks it refunded, flags its payments as
  /// refunded, restocks the recipe's ingredients, and writes an audit-log
  /// entry. Same authorizer rule as [voidOrder].
  Future<String?> refundOrder({
    required String orderId,
    required String reason,
    required String authorizerPin,
  }) =>
      _reverseOrder('refund_order', orderId, reason, authorizerPin);

  /// Shared body for [voidOrder] / [refundOrder] — both call a 3-arg RPC
  /// with the same shape, then refresh orders + inventory so the restock
  /// and status change show immediately. Maps server errors to friendly
  /// messages for a non-technical cashier.
  Future<String?> _reverseOrder(
    String rpc,
    String orderId,
    String reason,
    String authorizerPin,
  ) async {
    final verb = rpc == 'refund_order' ? 'refund' : 'void';
    try {
      await supabase.rpc(rpc, params: {
        'p_order_id': orderId,
        'p_reason': reason,
        'p_authorizer_pin': authorizerPin.trim(),
      });
      await refreshOrders();
      await _reloadInventoryFromDb();
      return null;
    } on sb.PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('bad_authorizer_pin')) {
        return 'Incorrect owner or manager PIN.';
      }
      if (msg.contains('already')) {
        return 'This order was already voided or refunded.';
      }
      return 'Could not $verb this order. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Reloads just the inventory cache from the DB (used after a void/refund
  /// restocks ingredients server-side). Mirrors the load in
  /// [_restoreTenantFromDb] without re-hydrating everything else.
  Future<void> _reloadInventoryFromDb() async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return;
    try {
      final invRows = await supabase
          .from('inventory_items')
          .select('*')
          .eq('tenant_id', tenantId)
          .order('name');
      _inventory = (invRows as List)
          .map((r) => InventoryItem.fromRow(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('Reload inventory after reverse failed: $e');
    }
  }

  /// Aggregated inventory draw-down for a single cart line, expanded through
  /// its modifiers + add-ons and multiplied by the line quantity. Returned
  /// as `[{inventory_item_id, quantity}]` so it can be stored on the
  /// order_line and reversed exactly if the cashier voids/refunds just that
  /// item later. Empty for non-stock items (e.g. Service).
  List<Map<String, dynamic>> recipeDeductionsForCartLine(CartLine line) {
    final kind = line.kind;
    if (kind is! CartLineCafe) return const [];
    final product = productById(kind.item.id);
    if (product == null) return const [];
    if (!tracksStock(product)) return const [];
    final expanded = expandRecipe(
      product,
      kind.selections,
      addOnQuantities: kind.addOnQuantities,
    );
    final agg = <String, double>{};
    for (final r in expanded) {
      final total = r.quantity * line.quantity;
      agg.update(r.inventoryItemId, (v) => v + total, ifAbsent: () => total);
    }
    return [
      for (final e in agg.entries)
        {'inventory_item_id': e.key, 'quantity': e.value},
    ];
  }

  /// Voids or refunds a SINGLE line of a paid order. Restocks just that
  /// line's ingredients, recomputes the order total from the lines that
  /// remain, and (when the last active line is reversed) flips the whole
  /// order to voided/refunded. [kind] is 'void' or 'refund'. Same
  /// Owner/Manager PIN rule as the whole-order reversal.
  Future<String?> reverseOrderLine({
    required String orderLineId,
    required String kind,
    required String reason,
    required String authorizerPin,
  }) async {
    final verb = kind == 'refund' ? 'refund' : 'void';
    try {
      await supabase.rpc('reverse_order_line', params: {
        'p_line_id': orderLineId,
        'p_kind': kind,
        'p_reason': reason,
        'p_authorizer_pin': authorizerPin.trim(),
      });
      await refreshOrders();
      await _reloadInventoryFromDb();
      return null;
    } on sb.PostgrestException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('bad_authorizer_pin')) {
        return 'Incorrect owner or manager PIN.';
      }
      if (msg.contains('line_already_reversed')) {
        return 'That item was already voided or refunded.';
      }
      if (msg.contains('already')) {
        return 'This order was already voided or refunded.';
      }
      return 'Could not $verb this item. Please try again.';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Returns orders for the current tenant created on or after [since]
  /// (and strictly before [until] if supplied), most-recent first.
  /// Includes related order_lines and payments via the PostgREST
  /// nested-select syntax.
  Future<List<o.Order>> fetchOrders({
    required DateTime since,
    DateTime? until,
    int limit = 100,
  }) async {
    final tenantId = _currentTenantDbId;
    if (tenantId == null) return const [];
    try {
      var query = supabase
          .from('orders')
          .select(
              'id, tenant_id, branch_id, cashier_id, cashier_name, '
              'employee_id, employee_name, '
              'order_number, status, '
              'subtotal_cents, discount_cents, vat_cents, total_cents, '
              'customer_name, customer_phone, notes, void_reason, '
              'sc_pwd_type, sc_pwd_name, sc_pwd_id, '
              'created_at, paid_at, voided_at, '
              'order_lines(id, sellable_id, sellable_name, category_name, '
              'emoji, unit_price_cents, quantity, line_total_cents, '
              'modifiers_json, status, reverse_reason), '
              'payments(id, method, amount_cents, tendered_cents, '
              'change_cents, reference, refunded)')
          .eq('tenant_id', tenantId)
          .gte('created_at', since.toIso8601String());
      if (until != null) {
        query = query.lt('created_at', until.toIso8601String());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List).map((r) {
        final row = r as Map<String, dynamic>;
        final linesRaw = (row['order_lines'] as List? ?? const []);
        final paymentsRaw = (row['payments'] as List? ?? const []);
        return o.Order.fromRow(
          row,
          lines: linesRaw
              .map((l) => o.OrderLine.fromRow(l as Map<String, dynamic>))
              .toList(),
          payments: paymentsRaw
              .map((p) => o.OrderPayment.fromRow(p as Map<String, dynamic>))
              .toList(),
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('fetchOrders failed: $e');
      return const [];
    }
  }

  // ───── shell ─────
  void selectRoute(AppRoute route) {
    selectedRoute = route;
    notifyListeners();
  }

  /// Locks the app — clears the staff session so main.dart routes back
  /// to the PIN-entry screen. Keeps the Supabase auth session intact, so
  /// the owner doesn't have to OTP again. The next user just needs to
  /// punch their PIN.
  ///
  /// Also resets in-flight UI state (cart, tender sheet flag, currently
  /// selected route) so the next user lands on a clean dashboard rather
  /// than a route that may be off-limits for their role.
  ///
  /// While [_isLocking] is true, main.dart shows a "Locking, please
  /// wait…" loader. After ~1.5s the flag clears and the user lands on
  /// the PIN keypad. The loader gives the cashier visual confirmation
  /// the lock actually happened (rather than thinking they mis-tapped).
  void lockSession() {
    _isLocking = true;
    currentStaff = null;
    cart.clear();
    showTender = false;
    // Don't reset _selectedRoute here — doing so makes the outgoing
    // Shell rebuild to the Dashboard during the AnimatedSwitcher fade,
    // which the user sees as a flash. The floating nav's canAccess
    // snap-back handles role-mismatch on the next pin-in.
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!_isLocking) return;
      _isLocking = false;
      notifyListeners();
    });
  }

  // ───── Held / parked orders (device-local, per store) ────────────────────

  final List<HeldOrder> _heldOrders = [];
  List<HeldOrder> get heldOrders => List.unmodifiable(_heldOrders);

  String get _heldKey => 'held_orders_v1_${_currentTenantDbId ?? 'none'}';

  Future<void> _loadHeldOrders() async {
    _heldOrders.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_heldKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _heldOrders.addAll(list
            .map((e) => HeldOrder.fromJson(e as Map<String, dynamic>)));
        _heldOrders.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Held orders load failed: $e');
    }
    notifyListeners();
  }

  Future<void> _persistHeldOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _heldKey, jsonEncode([for (final h in _heldOrders) h.toJson()]));
    } catch (e) {
      if (kDebugMode) debugPrint('Held orders save failed: $e');
    }
  }

  /// Park the current cart as a held order (optionally labelled) and clear the
  /// cart for the next customer. No-op on an empty cart.
  Future<void> holdCurrentOrder({String? label}) async {
    if (cart.lines.isEmpty) return;
    final lines = <HeldLine>[];
    for (final line in cart.lines) {
      final kind = line.kind;
      if (kind is! CartLineCafe) continue;
      lines.add(HeldLine(
        itemId: kind.item.id,
        quantity: line.quantity,
        selections: Map<String, String>.from(kind.selections),
        addOns: {for (final a in kind.addOns) a.addOn.id: a.quantity},
        priceOverrideCents: kind.priceOverride?.centavos,
        note: kind.note,
      ));
    }
    if (lines.isEmpty) return;

    final name = (label ?? '').trim();
    _heldOrders.insert(
      0,
      HeldOrder(
        label: name.isEmpty ? '#${_heldOrders.length + 1}' : name,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
        lines: lines,
        itemCount: cart.itemCount,
        totalCents: cart.total.centavos,
      ),
    );
    cart.clear();
    notifyListeners();
    await _persistHeldOrders();
  }

  /// Rebuild [held] into the live cart (re-resolved from the catalog so prices
  /// are current) and remove it from the held list. Items whose product was
  /// since deleted are skipped.
  Future<void> resumeHeldOrder(HeldOrder held) async {
    for (final hl in held.lines) {
      final item = productById(hl.itemId);
      if (item == null) continue;
      final addOns = <CartAddOn>[];
      hl.addOns.forEach((addOnId, qty) {
        for (final a in _addOns) {
          if (a.id == addOnId) {
            addOns.add(CartAddOn(a, qty));
            break;
          }
        }
      });
      cart.addCafe(item, Map<String, String>.from(hl.selections),
          quantity: hl.quantity,
          addOns: addOns,
          priceOverride: hl.priceOverrideCents == null
              ? null
              : Money(hl.priceOverrideCents!),
          note: hl.note);
    }
    _heldOrders.removeWhere((h) => h.id == held.id);
    notifyListeners();
    await _persistHeldOrders();
  }

  Future<void> discardHeldOrder(HeldOrder held) async {
    _heldOrders.removeWhere((h) => h.id == held.id);
    notifyListeners();
    await _persistHeldOrders();
  }

  void openTender() {
    showTender = true;
    notifyListeners();
  }

  void closeTender() {
    showTender = false;
    notifyListeners();
  }
}
