import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/stores/bookings_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart' show iconFromKey;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/booking.dart';
import 'booking_form_dialog.dart';
import 'booking_detail_sheet.dart';

/// Day-view bookings calendar — half-hour rows × bookable-resource
/// columns. Cashiers tap any empty slot to create a reservation; tap an
/// existing booking card to view / cancel / mark complete. Hours run
/// from 8 AM to 10 PM by default; bookings outside that window still
/// show but the grid scrolls.
class BookingsView extends StatefulWidget {
  const BookingsView({super.key});

  @override
  State<BookingsView> createState() => _BookingsViewState();
}

class _BookingsViewState extends State<BookingsView> {
  DateTime _day = DateTime.now();
  List<Booking> _bookings = const [];
  bool _loading = true;

  /// Calendar bounds. 30-minute granularity.
  static const _startHour = 8;
  static const _endHour = 22;
  static const _slotMinutes = 30;
  static const _rowHeight = 56.0;
  static const _columnMinWidth = 200.0;

  int get _totalSlots =>
      ((_endHour - _startHour) * 60) ~/ _slotMinutes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final state = context.read<BookingsStore>();
    setState(() => _loading = true);
    final rows = await state.fetchBookingsForDay(_day);
    if (!mounted) return;
    setState(() {
      _bookings = rows;
      _loading = false;
    });
  }

  void _jumpDay(int days) {
    setState(() {
      _day = DateTime(_day.year, _day.month, _day.day)
          .add(Duration(days: days));
    });
    _refresh();
  }

  DateTime _slotStart(int slotIndex) {
    final base = DateTime(_day.year, _day.month, _day.day, _startHour);
    return base.add(Duration(minutes: slotIndex * _slotMinutes));
  }

  String _fmtTime(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  Color _resourceAccent(BookableResource r) {
    final raw = r.color;
    if (raw == null || raw.isEmpty) return YColor.brand;
    final hex = raw.replaceFirst('#', '');
    final v = int.tryParse('FF$hex', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BookingsStore>();
    final resources = state.bookableResources;
    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          _header(resources.length),
          if (resources.isEmpty) Expanded(child: _emptyResources()) else
            Expanded(child: _gridArea(resources)),
        ],
      ),
    );
  }

  Widget _header(int resourceCount) {
    final fmtDay = _fmtDay(_day);
    final today = DateTime.now();
    final isToday = _day.year == today.year &&
        _day.month == today.month &&
        _day.day == today.day;
    final confirmed = _bookings
        .where((b) => b.status == BookingStatus.confirmed)
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      decoration: const BoxDecoration(
        color: YColor.surface1,
        border: Border(
            bottom: BorderSide(color: YColor.hairline, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: () => _jumpDay(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(fmtDay,
                    style: YFont.titleLG().copyWith(
                        fontSize: 22, letterSpacing: -0.3)),
                if (isToday) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: YColor.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Today',
                        style: YFont.caption().copyWith(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                _loading
                    ? 'Loading reservations…'
                    : '$resourceCount resource${resourceCount == 1 ? "" : "s"} · '
                        '$confirmed confirmed',
                style: YFont.caption(),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Next day',
            onPressed: () => _jumpDay(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              setState(() => _day = DateTime.now());
              _refresh();
            },
            icon: const Icon(Icons.today, size: 16),
            label: const Text('Jump to today'),
            style: TextButton.styleFrom(
              foregroundColor: YColor.brand,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: resourceCount == 0 ? null : () => _openBookingForm(null),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New booking'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyResources() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: YColor.brandTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_available_outlined,
                  size: 38, color: YColor.brandDeep),
            ),
            const SizedBox(height: 14),
            Text('No bookable resources yet',
                style: YFont.titleMD().copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Add meeting rooms, hot desks, or event spaces in\n'
              'Maintenance → Resources to start taking reservations.',
              textAlign: TextAlign.center,
              style: YFont.caption(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gridArea(List<BookableResource> resources) {
    // Reuse a single vertical scroll controller so the time-column
    // gutter and the resource lanes scroll together.
    return LayoutBuilder(builder: (ctx, c) {
      // Lane width: split available width between resources, but never
      // narrower than _columnMinWidth (then horizontal scrolls).
      final lanesWidth =
          c.maxWidth - 72; // 72px = time gutter
      final fittedLaneWidth =
          (lanesWidth / resources.length).clamp(_columnMinWidth, 320.0);
      final totalLanesWidth = fittedLaneWidth * resources.length;

      // +2 accounts for the lane Container's 1px Border.all on top and
      // bottom — without it, the inner empty-slot Column ends up 2px
      // short of `_rowHeight * _totalSlots` and Flutter throws a
      // "RenderFlex overflowed by 2 pixels" warning.
      final laneHeight = _rowHeight * _totalSlots + 40 + 2;
      return SingleChildScrollView(
        child: SizedBox(
          height: laneHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time gutter
              _timeGutter(),
              // Resource lanes — horizontally scrollable when many resources
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalLanesWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in resources)
                          SizedBox(
                            width: fittedLaneWidth,
                            child: _resourceLane(r),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _timeGutter() {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          const SizedBox(height: 40),
          for (var i = 0; i < _totalSlots; i++)
            SizedBox(
              height: _rowHeight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    _fmtTime(_slotStart(i)),
                    style: YFont.caption().copyWith(
                      fontSize: 10,
                      color: YColor.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resourceLane(BookableResource r) {
    final accent = _resourceAccent(r);
    final iconData = iconFromKey(r.iconName) ?? r.kind.icon;
    final lanes = _bookings.where((b) => b.resourceId == r.id).toList();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          // Lane header — resource name + hourly rate.
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: YColor.hairline.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(iconData, size: 14, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YFont.bodyStrong().copyWith(fontSize: 12)),
                      Text(
                        '₱${r.hourlyRatePesos.toStringAsFixed(0)}/hr',
                        style: YFont.caption().copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Time grid — tappable empty slots + booking cards overlaid via
          // a Stack so they can span multiple rows.
          Expanded(
            child: Stack(
              children: [
                // Empty grid (tappable rows for "create at this time")
                Column(
                  children: [
                    for (var i = 0; i < _totalSlots; i++)
                      _emptySlot(r, i),
                  ],
                ),
                // Booking cards
                for (final b in lanes) _bookingCard(b, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySlot(BookableResource r, int slotIndex) {
    final isHalfHour = slotIndex % 2 == 1;
    return InkWell(
      onTap: () => _openBookingForm(_PrefilledSlot(
        resourceId: r.id,
        startsAt: _slotStart(slotIndex),
        endsAt: _slotStart(slotIndex).add(const Duration(hours: 1)),
      )),
      child: Container(
        height: _rowHeight,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: YColor.hairline.withValues(alpha: isHalfHour ? 0.25 : 0.5),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingCard(Booking b, Color accent) {
    // Compute top + height from the booking's start / end relative to
    // the lane's slot grid. Clamp to the visible window so a booking
    // that bleeds across midnight doesn't paint outside the lane.
    // Open sessions (ends_at == null) are drawn from check-in to
    // "now", so they grow on the grid until the session is stopped.
    final base = DateTime(_day.year, _day.month, _day.day, _startHour);
    final endOfLane = base
        .add(Duration(minutes: _totalSlots * _slotMinutes));
    final effectiveEnd = b.endsAt ?? DateTime.now();
    final startsAt = b.startsAt.isBefore(base) ? base : b.startsAt;
    final endsAt =
        effectiveEnd.isAfter(endOfLane) ? endOfLane : effectiveEnd;
    if (!endsAt.isAfter(startsAt)) return const SizedBox.shrink();
    final topMinutes = startsAt.difference(base).inMinutes;
    final durMinutes = endsAt.difference(startsAt).inMinutes;
    final top = (topMinutes / _slotMinutes) * _rowHeight;
    final height = (durMinutes / _slotMinutes) * _rowHeight;

    final isPast = b.endsAt != null &&
        b.endsAt!.isBefore(DateTime.now()) &&
        b.status == BookingStatus.confirmed;
    final cardBg = switch (b.status) {
      BookingStatus.cancelled => YColor.surface3,
      BookingStatus.noShow => YColor.dangerSoft,
      BookingStatus.completed => YColor.successSoft,
      _ => accent.withValues(alpha: 0.16),
    };
    final stripeColor = switch (b.status) {
      BookingStatus.cancelled => YColor.inkMuted,
      BookingStatus.noShow => YColor.danger,
      BookingStatus.completed => YColor.success,
      _ => accent,
    };
    final textColor = switch (b.status) {
      BookingStatus.cancelled => YColor.inkMuted,
      _ => YColor.ink,
    };
    final timeRange = b.endsAt == null
        ? '${_fmtTime(b.startsAt)} – now (live)'
        : '${_fmtTime(b.startsAt)} – ${_fmtTime(b.endsAt!)}';
    return Positioned(
      top: top + 2,
      left: 4,
      right: 4,
      height: (height - 4).clamp(28.0, double.infinity),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(YRadius.md),
          onTap: () => _openBookingDetail(b),
          child: Opacity(
            opacity: b.status == BookingStatus.cancelled ? 0.55 : 1.0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(YRadius.md),
                border: Border(
                  left: BorderSide(color: stripeColor, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        b.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 12,
                          color: textColor,
                          decoration: b.status == BookingStatus.cancelled
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    if (isPast)
                      const Icon(Icons.history,
                          size: 11, color: YColor.inkMuted),
                  ]),
                  if (height >= 40)
                    Text(
                      timeRange,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        color: textColor.withValues(alpha: 0.75),
                      ),
                    ),
                  if (height >= 64 && b.priceCents > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '₱${b.pricePesos.toStringAsFixed(0)}',
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 11,
                          color: stripeColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBookingForm(_PrefilledSlot? prefill) async {
    final result = await showDialog<Booking>(
      context: context,
      barrierDismissible: true,
      builder: (_) => BookingFormDialog(
        day: _day,
        prefilledResourceId: prefill?.resourceId,
        prefilledStart: prefill?.startsAt,
        prefilledEnd: prefill?.endsAt,
      ),
    );
    if (result != null) _refresh();
  }

  Future<void> _openBookingDetail(Booking b) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BookingDetailSheet(booking: b),
    );
    if (changed == true) _refresh();
  }

  String _fmtDay(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

class _PrefilledSlot {
  const _PrefilledSlot({
    required this.resourceId,
    required this.startsAt,
    required this.endsAt,
  });
  final String resourceId;
  final DateTime startsAt;
  final DateTime endsAt;
}
