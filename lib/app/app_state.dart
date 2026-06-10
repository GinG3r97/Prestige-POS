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
import '../models/tenant.dart';
import 'stores/bookings_store.dart';
import 'stores/catalog_store.dart';
import 'stores/hr_store.dart';
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

  /// HR domain (employees, roles, leave types, employment templates, payroll
  /// rules, time entries, payroll runs) lives in its own ChangeNotifier so HR
  /// changes don't rebuild every AppState watcher. AppState owns the instance
  /// and drives its lifecycle (hydrateCore/hydratePayrollCache/ensureTenant/
  /// reset); the auth/PIN/permission code on AppState READS this store for
  /// employee/role data. Consumers watch this store directly via its own
  /// provider (see main.dart).
  final HrStore hr = HrStore();

  /// Catalog domain (product types, sub-type categories, master modifier
  /// groups, add-ons, products) lives in its own ChangeNotifier so catalog
  /// changes don't rebuild every AppState watcher. AppState owns the instance
  /// and drives its lifecycle (hydrate/seedDefaultProductTypes/reset); the
  /// money-path coordinator methods on AppState (expandRecipe / tracksStock /
  /// projected deductions / checkout) READ this store via the thin delegates
  /// below. Consumers watch this store directly via its own provider (see
  /// main.dart).
  final CatalogStore catalog = CatalogStore();

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
        _features = cat.TenantFeatures();
        hr.reset();
        catalog.reset();
        _inventory = [];
        _inventoryCategories = [];
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
        hr.ensureTenant(tenantObj.id);
      }
      _currentStoreIndex = 0;
      _currentTenantDbId = tenantRows.first['id'] as String;

      // These per-tenant reads are independent of each other, so run them
      // CONCURRENTLY (was ~12 serial round-trips on every cold start). Each
      // closure does its own fetch + assignment exactly as before. The catalog
      // (categories/modifier groups/types/products/add-ons) hydrates as one
      // entry — CatalogStore.hydrate parallelizes its independent tables
      // internally then fetches products + add-ons.
      final tid = _currentTenantDbId as Object;
      await Future.wait<void>([
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
        // HR core (roles/employees/payrollRules/leaveTypes/templates) lives
        // in HrStore. hydrateCore runs its own internal Future.wait over the
        // same five fetches, so the parallelism is unchanged — it just runs
        // as one entry in this concurrent batch.
        hr.hydrateCore(tid as String),
        // Catalog (categories, master modifier groups, product types,
        // products + per-product runtime modifier-group join, add-ons) lives
        // in CatalogStore. hydrate runs its own internal Future.wait over the
        // independent catalog tables then fetches products + add-ons, so the
        // parallelism is unchanged — it just runs as one entry in this batch.
        catalog.hydrate(tid),
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

      // Payroll — time entries + payroll runs live in HrStore. The per-tenant
      // cache key is the in-memory Tenant id (matches what we initialised at
      // the top of this method); the queries are scoped by the DB id.
      await hr.hydratePayrollCache(_currentTenantDbId!, tenant!.id);

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

  // ───── Catalog domain delegates (data now lives in CatalogStore) ─────
  //
  // Products / categories / product types / master modifier groups / add-ons
  // + their CRUD moved to [catalog] (CatalogStore). The money-path coordinator
  // methods below (expandRecipe / tracksStock / projected deductions /
  // checkout) and a few un-migrated shell screens still read these via
  // AppState, so these thin delegates forward to the store. Catalog FEATURE
  // screens watch the store directly via its own provider.

  /// Live products for the active tenant. Delegates to [catalog].
  List<CafeItem> get products => catalog.products;

  /// Live sub-type categories for the active tenant. Delegates to [catalog].
  List<cat.Category> get categories => catalog.categories;

  /// Live add-ons for the active tenant. Delegates to [catalog].
  List<AddOn> get addOns => catalog.addOns;

  /// Live product types for the active tenant. Delegates to [catalog].
  List<ProductType> get productTypes => catalog.productTypes;

  /// Find a category (sub-type) by id. Delegates to [catalog].
  cat.Category? categoryById(String? id) => catalog.categoryById(id);

  /// Sub-types (categories) under a given product type. Delegates to [catalog].
  List<cat.Category> categoriesForType(String? typeId) =>
      catalog.categoriesForType(typeId);

  /// The product type a product effectively belongs to. Delegates to [catalog].
  String? effectiveTypeId(CafeItem p) => catalog.effectiveTypeId(p);

  /// Resolve a product type by id. Delegates to [catalog].
  ProductType? productTypeById(String? id) => catalog.productTypeById(id);

  /// Resolve a product by id. Delegates to [catalog]. Used by the money-path
  /// (projected deductions / checkout) + held-order resume.
  CafeItem? productById(String id) => catalog.productById(id);

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
      final typeIds = await catalog.seedDefaultProductTypes(tenantDbId);

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
      await hr.seedDefaultPayrollSurface(tenantDbId);

      // (Product types were seeded earlier so categories could link to them.)
    } on sb.PostgrestException catch (e) {
      return 'Could not save your business: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
    // Seed the catalog store's categories from the rows we just inserted, so
    // the freshly-onboarded session shows them in Sell immediately (a full
    // catalog hydrate happens on the next _restoreTenantFromDb cycle).
    catalog.seedCategoriesFromOnboarding(tenantDbId, fetchedCategories);

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
    hr.ensureTenant(newStore.id);

    // Seed default employee roles for this fresh tenant. Idempotent against
    // the SQL backfill via unique(tenant_id, name).
    await hr.seedDefaultEmployeeRoles(tenantDbId);
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
        final ownerRole = hr.employeeRoles
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
          final ownerRole = hr.employeeRoles
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
    for (final e in hr.employees) {
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
    for (final emp in hr.employees) {
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

  /// Master modifier groups for the active tenant. Delegates to [catalog].
  /// Kept on AppState so un-migrated shell screens (more_view) keep working.
  List<MasterModifierGroup> get modifierGroups => catalog.modifierGroups;

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
        final addOn = catalog.addOns.where((a) => a.id == entry.key).firstOrNull;
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

  // ───── HR domain delegates (data now lives in HrStore) ─────
  //
  // The employees/roles/payroll data + CRUD moved to [hr] (HrStore). The
  // session/permission code below and a few un-migrated shell screens still
  // call `state.employees` / `state.employeeRoles` / `state.roleById`, so
  // these thin delegates forward to the store. HR feature screens watch the
  // store directly via its own provider.

  /// Live employee roster for the active tenant. Delegates to [hr] so the
  /// PIN flow, more_view tiles, and reports keep working via AppState.
  List<Employee> get employees => hr.employees;

  /// Live employee roles for the active tenant. Delegates to [hr].
  List<EmployeeRole> get employeeRoles => hr.employeeRoles;

  /// Resolve a role by id. Delegates to [hr]. Kept on AppState so the
  /// permission getters and un-migrated shell screens (topbar / more_view)
  /// that call `state.roleById(...)` keep working.
  EmployeeRole? roleById(String? id) => hr.roleById(id);

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
        for (final a in catalog.addOns) {
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
