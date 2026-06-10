import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../data/supabase_client.dart';
import '../../models/booking.dart';

/// Owns the Bookings domain (bookable resources + bookings/sessions),
/// extracted from the monolithic [AppState] so that Sell / Products / etc.
/// watching AppState no longer rebuild when a resource changes. All
/// booking-data consumers watch this store directly.
///
/// AppState owns a single instance ([AppState.bookings]) and drives its
/// lifecycle via [hydrate] (on tenant restore) and [reset] (on sign-out /
/// tenant switch). The Supabase calls, sorting, and notify timing are
/// identical to what AppState used to do inline.
class BookingsStore extends ChangeNotifier {
  /// The active tenant DB id, set by [hydrate]. All mutations are scoped to
  /// this tenant. `null` means no store is selected (signed out / no tenant).
  String? _tenantId;

  // ───── bookings + bookable resources (Supabase-backed) ───────────

  /// Tenant-owned reservable resources (rooms, desks, event spaces).
  /// Loaded once during tenant restore; the live booking grid for a day
  /// is fetched on demand via [fetchBookingsForDay].
  List<BookableResource> _bookableResources = [];
  List<BookableResource> get bookableResources =>
      List.unmodifiable(_bookableResources);

  BookableResource? resourceById(String? id) {
    if (id == null) return null;
    for (final r in _bookableResources) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Loads the bookable resources for [tenantId] from Supabase, then
  /// notifies. Called by AppState during tenant hydration. The actual
  /// [Booking] rows are loaded per-day on demand from BookingsView.
  Future<void> hydrate(String tenantId) async {
    _tenantId = tenantId;

    // Bookable resources (rooms, hot desks, event spaces). The actual
    // [Booking] rows are loaded per-day on demand from BookingsView.
    final resRows = await supabase
        .from('bookable_resources')
        .select('*')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('sort_order');
    _bookableResources = (resRows as List)
        .map((r) => BookableResource.fromRow(r as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  /// Clears all booking state (sign-out / tenant switch).
  void reset() {
    _tenantId = null;
    _bookableResources = [];
    notifyListeners();
  }

  /// Loads every booking whose start OR end overlaps the given calendar
  /// day. Wider than `starts_at::date = :day` so a booking that spans
  /// midnight or already started yesterday still shows up. Open
  /// sessions (ends_at IS NULL) are treated as extending forever, so
  /// they show on every day from their check-in date onward.
  Future<List<Booking>> fetchBookingsForDay(DateTime day) async {
    final tenantId = _tenantId;
    if (tenantId == null) return const [];
    final from = DateTime(day.year, day.month, day.day);
    final to = from.add(const Duration(days: 1));
    try {
      final rows = await supabase
          .from('bookings')
          .select('*')
          .eq('tenant_id', tenantId)
          .lt('starts_at', to.toUtc().toIso8601String())
          .or('ends_at.is.null,ends_at.gt.${from.toUtc().toIso8601String()}')
          .order('starts_at');
      return (rows as List)
          .map((r) => Booking.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// All currently-open sessions across all resources, oldest first.
  /// The Active Sessions view uses this for its live grid and
  /// recomputes the elapsed timer / running total client-side every
  /// second.
  Future<List<Booking>> fetchActiveSessions() async {
    final tenantId = _tenantId;
    if (tenantId == null) return const [];
    try {
      final rows = await supabase
          .from('bookings')
          .select('*')
          .eq('tenant_id', tenantId)
          .eq('status', 'confirmed')
          .isFilter('ends_at', null)
          .order('starts_at');
      return (rows as List)
          .map((r) => Booking.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Inserts a booking after a server-side conflict check (any existing
  /// confirmed booking on the same resource that overlaps the new
  /// window). Returns `(booking, null)` on success or `(null, errMsg)`
  /// when something prevented the write.
  Future<({Booking? booking, String? error})> createBooking({
    required String resourceId,
    required String customerName,
    String? customerPhone,
    required DateTime startsAt,
    required DateTime endsAt,
    int? priceCentsOverride,
    String? notes,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return (booking: null, error: 'No store selected.');
    if (customerName.trim().isEmpty) {
      return (booking: null, error: 'Customer name is required.');
    }
    if (!endsAt.isAfter(startsAt)) {
      return (booking: null, error: 'End time must be after start time.');
    }
    final resource = resourceById(resourceId);
    if (resource == null) {
      return (booking: null, error: 'That resource no longer exists.');
    }

    try {
      // Conflict check — any non-cancelled booking on this resource
      // whose window overlaps the new one. Open sessions (ends_at
      // IS NULL) are treated as extending to infinity so they block
      // future reservations until the cashier stops the session.
      final clashRows = await supabase
          .from('bookings')
          .select('id, customer_name, starts_at, ends_at, status')
          .eq('tenant_id', tenantId)
          .eq('resource_id', resourceId)
          .neq('status', 'cancelled')
          .lt('starts_at', endsAt.toUtc().toIso8601String())
          .or('ends_at.is.null,ends_at.gt.${startsAt.toUtc().toIso8601String()}');
      if (clashRows.isNotEmpty) {
        final clash = Map<String, dynamic>.from(
            clashRows.first as Map);
        final openTag = clash['ends_at'] == null ? ' (active session)' : '';
        return (
          booking: null,
          error: '${resource.name} is already booked by '
              '${clash["customer_name"]}$openTag during this window. '
              'Pick a different time or resource.',
        );
      }

      final price = priceCentsOverride ??
          resource.priceFor(endsAt.difference(startsAt));
      final inserted = await supabase
          .from('bookings')
          .insert({
            'tenant_id': tenantId,
            'resource_id': resourceId,
            'customer_name': customerName.trim(),
            'customer_phone': (customerPhone ?? '').trim().isEmpty
                ? null
                : customerPhone!.trim(),
            'starts_at': startsAt.toUtc().toIso8601String(),
            'ends_at': endsAt.toUtc().toIso8601String(),
            'status': 'confirmed',
            'price_cents': price,
            'notes': (notes ?? '').trim().isEmpty ? null : notes!.trim(),
          })
          .select('*')
          .single();
      return (booking: Booking.fromRow(inserted), error: null);
    } on sb.PostgrestException catch (e) {
      return (booking: null, error: 'Could not save booking: ${e.message}');
    } catch (_) {
      return (
        booking: null,
        error: 'Could not reach the server. Please try again.'
      );
    }
  }

  // ── Bookable resources CRUD (Maintenance → Bookable resources) ──

  Future<String?> addBookableResource(BookableResource r) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (r.name.trim().isEmpty) return 'Resource name is required.';
    try {
      final row = await supabase
          .from('bookable_resources')
          .insert(r.toRowPayload(tenantId))
          .select('*')
          .single();
      _bookableResources.add(BookableResource.fromRow(row));
      _bookableResources.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A resource named "${r.name}" already exists.';
      }
      return 'Could not add resource: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateBookableResource(BookableResource updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Resource name is required.';
    try {
      final row = await supabase
          .from('bookable_resources')
          .update(updated.toRowPayload(tenantId))
          .eq('id', updated.id)
          .select('*')
          .single();
      final fresh = BookableResource.fromRow(row);
      final i = _bookableResources.indexWhere((x) => x.id == fresh.id);
      if (i >= 0) _bookableResources[i] = fresh;
      _bookableResources.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update resource: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeBookableResource(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('bookable_resources').delete().eq('id', id);
      _bookableResources.removeWhere((r) => r.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      // FK from bookings → bookable_resources is ON DELETE RESTRICT,
      // so the DB rejects deletes that would orphan bookings. Surface
      // a friendlier message than the raw FK error.
      if (e.code == '23503') {
        return 'This resource has bookings on it — cancel or move them first.';
      }
      return 'Could not delete resource: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateBookingStatus(String id, BookingStatus status) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase
          .from('bookings')
          .update({'status': status.dbValue})
          .eq('id', id);
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update booking: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ───── active sessions (walk-in timers) ──────────────────────────

  /// Start an open-ended session on [resourceId] *now*. The booking is
  /// inserted with `ends_at = NULL` and stays that way until the
  /// cashier hits Stop. A partial unique index on (resource_id) WHERE
  /// ends_at IS NULL guarantees at most one active session per
  /// resource, so we don't even need a client-side check.
  Future<({Booking? booking, String? error})> startSession({
    required String resourceId,
    required String customerName,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return (booking: null, error: 'No store selected.');
    final name = customerName.trim().isEmpty
        ? 'Walk-in'
        : customerName.trim();
    final resource = resourceById(resourceId);
    if (resource == null) {
      return (booking: null, error: 'That resource no longer exists.');
    }
    final startsAt = DateTime.now();
    try {
      final inserted = await supabase
          .from('bookings')
          .insert({
            'tenant_id': tenantId,
            'resource_id': resourceId,
            'customer_name': name,
            'starts_at': startsAt.toUtc().toIso8601String(),
            'ends_at': null,
            'status': 'confirmed',
            'price_cents': 0,
          })
          .select('*')
          .single();
      return (booking: Booking.fromRow(inserted), error: null);
    } on sb.PostgrestException catch (e) {
      // 23505 = unique violation → bookings_one_open_per_resource. A
      // session is already running on this resource, probably from
      // another device.
      if (e.code == '23505') {
        return (
          booking: null,
          error: '${resource.name} already has an active session. '
              'Refresh and stop the existing one first.',
        );
      }
      return (booking: null, error: 'Could not start session: ${e.message}');
    } catch (_) {
      return (
        booking: null,
        error: 'Could not reach the server. Please try again.',
      );
    }
  }

  /// Close an active session, stamping the rounded-up end time and
  /// final billed amount. Returns the closed [Booking] so the UI can
  /// show a receipt-style summary.
  Future<({Booking? booking, String? error})> stopSession(
      String bookingId) async {
    if (_tenantId == null) {
      return (booking: null, error: 'No store selected.');
    }
    try {
      // Re-fetch the booking so we use the server-side starts_at as
      // the source of truth (avoids drift if the cashier's clock is
      // off by minutes).
      final row = await supabase
          .from('bookings')
          .select('*')
          .eq('id', bookingId)
          .single();
      final current = Booking.fromRow(row);
      if (!current.isOpenSession) {
        return (
          booking: null,
          error: 'This session is no longer active.',
        );
      }
      final resource = resourceById(current.resourceId);
      final hourlyCents = resource?.hourlyRateCents ?? 0;
      final rounded = roundSessionEnd(current.startsAt, DateTime.now());
      final price =
          ((hourlyCents * rounded.billed.inSeconds) / 3600).round();
      final updated = await supabase
          .from('bookings')
          .update({
            'ends_at': rounded.endsAt.toUtc().toIso8601String(),
            'price_cents': price,
            'status': 'completed',
          })
          .eq('id', bookingId)
          .select('*')
          .single();
      return (booking: Booking.fromRow(updated), error: null);
    } on sb.PostgrestException catch (e) {
      return (booking: null, error: 'Could not stop session: ${e.message}');
    } catch (_) {
      return (
        booking: null,
        error: 'Could not reach the server. Please try again.',
      );
    }
  }
}
