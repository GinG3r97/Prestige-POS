import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/stores/bookings_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart' show iconFromKey;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/booking.dart';
import '../widgets/push_toast.dart';

/// Live "Active Sessions" board. Each card is one walk-in customer who
/// is currently sitting at a bookable resource (hot desk / room).
/// Elapsed time and running cost tick every second so the cashier
/// always sees the truth. "Stop & charge" closes the session, rounds
/// the time UP to the next 15 minutes, and stamps the final price.
class SessionsView extends StatefulWidget {
  const SessionsView({super.key});

  @override
  State<SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<SessionsView> {
  List<Booking> _sessions = const [];
  bool _loading = true;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _refresh();
    // Tick once a second — minimum granularity the cashier needs to
    // believe the running cost is "live".
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final state = context.read<BookingsStore>();
    setState(() => _loading = true);
    final rows = await state.fetchActiveSessions();
    if (!mounted) return;
    setState(() {
      _sessions = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BookingsStore>();
    final resources = state.bookableResources
        .where((r) => r.isActive)
        .toList();
    // Resources that DON'T already have an active session — the
    // "Start session" picker only lists what's actually available.
    final occupiedIds = _sessions.map((s) => s.resourceId).toSet();
    final available =
        resources.where((r) => !occupiedIds.contains(r.id)).toList();

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          _header(available.isNotEmpty),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? _empty(resources.isEmpty, available)
                    : _grid(available),
          ),
        ],
      ),
    );
  }

  Widget _header(bool canStart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      decoration: const BoxDecoration(
        color: YColor.surface1,
        border: Border(
          bottom: BorderSide(color: YColor.hairline, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.timer_outlined,
                color: YColor.brandDeep, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Active Sessions',
                      style: YFont.titleLG().copyWith(
                          fontSize: 22, letterSpacing: -0.3)),
                  const SizedBox(width: 10),
                  if (_sessions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: YColor.success,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const _PulseDot(),
                        const SizedBox(width: 6),
                        Text('${_sessions.length} live',
                            style: YFont.caption().copyWith(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5)),
                      ]),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(
                  'Walk-in customers currently sitting at a hot desk, '
                  'room, or space. Time bills up to the nearest 15 minutes.',
                  style: YFont.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: canStart ? () => _openStartDialog() : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start session'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool noResources, List<BookableResource> available) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: YColor.brandTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_seat_outlined,
                  size: 42, color: YColor.brandDeep),
            ),
            const SizedBox(height: 16),
            Text(
              noResources ? 'No bookable resources yet' : 'No active sessions',
              style: YFont.titleMD().copyWith(fontSize: 18),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 360,
              child: Text(
                noResources
                    ? 'Add hot desks, meeting rooms, or event spaces in '
                        'Maintenance → Bookable first. Then come back here '
                        'to start a walk-in timer.'
                    : 'Tap "Start session" when a walk-in customer sits '
                        'down. The timer runs live; tap "Stop & charge" '
                        'when they leave to bill the rounded-up time.',
                textAlign: TextAlign.center,
                style: YFont.caption(),
              ),
            ),
            if (!noResources && available.isNotEmpty) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => _openStartDialog(),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start your first session'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _grid(List<BookableResource> available) {
    return LayoutBuilder(builder: (_, c) {
      // Aim for ~340px cards so two-three fit per row on a desktop and
      // one fills a tablet.
      final cols = (c.maxWidth / 360).floor().clamp(1, 4);
      return SingleChildScrollView(
        // Bottom padding clears the floating nav pill so the last
        // session card isn't hidden behind it once enough sessions
        // are running to scroll.
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final s in _sessions)
              SizedBox(
                width: (c.maxWidth - 40 - (cols - 1) * 14) / cols,
                child: _SessionCard(
                  session: s,
                  resource: context
                      .read<BookingsStore>()
                      .resourceById(s.resourceId),
                  now: _now,
                  onStop: () => _confirmStop(s),
                ),
              ),
          ],
        ),
      );
    });
  }

  Future<void> _openStartDialog() async {
    final state = context.read<BookingsStore>();
    final resources = state.bookableResources
        .where((r) => r.isActive)
        .toList();
    final occupiedIds = _sessions.map((s) => s.resourceId).toSet();
    final available =
        resources.where((r) => !occupiedIds.contains(r.id)).toList();
    if (available.isEmpty) {
      PushToast.show(
        context,
        title: 'No resources available',
        subtitle: 'Every desk / room / space is currently in use.',
        leadingIcon: Icons.info_outline,
      );
      return;
    }
    final started = await showDialog<Booking>(
      context: context,
      builder: (_) => _StartSessionDialog(resources: available),
    );
    if (started == null) return;
    if (!mounted) return;
    PushToast.show(
      context,
      title: 'Session started',
      subtitle: '${started.customerName} · '
          '${state.resourceById(started.resourceId)?.name ?? "resource"}',
      leadingIcon: Icons.play_circle_outline,
    );
    _refresh();
  }

  Future<void> _confirmStop(Booking session) async {
    final state = context.read<BookingsStore>();
    final resource = state.resourceById(session.resourceId);
    final rate = resource?.hourlyRateCents ?? 0;
    final rounded = roundSessionEnd(session.startsAt, DateTime.now());
    final preview = ((rate * rounded.billed.inSeconds) / 3600).round();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.lg)),
        backgroundColor: YColor.surface1,
        title: Text('Stop session?',
            style: YFont.titleMD().copyWith(fontSize: 18)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${session.customerName} · '
                '${resource?.name ?? "this resource"}',
                style: YFont.bodyStrong().copyWith(fontSize: 13),
              ),
              const SizedBox(height: 14),
              _summaryRow('Elapsed', _fmtElapsed(session.duration)),
              const SizedBox(height: 6),
              _summaryRow(
                  'Billed (rounded up 15 min)',
                  _fmtElapsed(rounded.billed),
                  bold: true),
              const SizedBox(height: 6),
              _summaryRow(
                  'Rate', '₱${(rate / 100).toStringAsFixed(0)}/hr'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: YColor.brandTint,
                  borderRadius: BorderRadius.circular(YRadius.md),
                ),
                child: Row(children: [
                  Text('Total to charge',
                      style: YFont.bodyStrong().copyWith(fontSize: 13)),
                  const Spacer(),
                  Text(
                    '₱${(preview / 100).toStringAsFixed(0)}',
                    style: YFont.titleLG().copyWith(
                      fontSize: 22,
                      color: YColor.brand,
                      letterSpacing: -0.3,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep running'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
            child: const Text('Stop & charge'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await state.stopSession(session.id);
    if (!mounted) return;
    if (res.error != null) {
      PushToast.show(
        context,
        title: 'Could not stop',
        subtitle: res.error!,
        leadingIcon: Icons.error_outline,
      );
      return;
    }
    PushToast.show(
      context,
      title: 'Session closed',
      subtitle:
          '${res.booking!.customerName} · ₱${res.booking!.pricePesos.toStringAsFixed(0)}',
      leadingIcon: Icons.check_circle_outline,
    );
    _refresh();
  }

  Widget _summaryRow(String label, String value, {bool bold = false}) {
    return Row(children: [
      Text(label, style: YFont.caption()),
      const Spacer(),
      Text(
        value,
        style: bold
            ? YFont.bodyStrong().copyWith(fontSize: 13)
            : YFont.body().copyWith(fontSize: 13),
      ),
    ]);
  }

  String _fmtElapsed(Duration d) {
    if (d.inHours == 0) return '${d.inMinutes} min';
    if (d.inMinutes % 60 == 0) return '${d.inHours} hr';
    return '${d.inHours} hr ${d.inMinutes % 60} min';
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.resource,
    required this.now,
    required this.onStop,
  });
  final Booking session;
  final BookableResource? resource;
  final DateTime now;
  final VoidCallback onStop;

  Color get _accent {
    final raw = resource?.color;
    if (raw == null || raw.isEmpty) return YColor.brand;
    final hex = raw.replaceFirst('#', '');
    final v = int.tryParse('FF$hex', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  IconData get _iconData =>
      iconFromKey(resource?.iconName) ??
      (resource?.kind.icon ?? Icons.event_seat_outlined);

  @override
  Widget build(BuildContext context) {
    final elapsed = now.difference(session.startsAt);
    final rate = resource?.hourlyRateCents ?? 0;
    // Live running cost = elapsed time pro-rated. The actual charge on
    // close rounds UP, but the running display tracks current truth —
    // it's slightly less than the final bill, which is the gentler
    // direction (no surprises that are HIGHER than the ticker).
    final liveCents = ((rate * elapsed.inSeconds) / 3600).round();
    final stale = elapsed.inHours >= 6;

    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(
          color: stale
              ? YColor.danger.withValues(alpha: 0.5)
              : _accent.withValues(alpha: 0.35),
          width: stale ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YRadius.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Accent strip + resource header
            Container(
              padding:
                  const EdgeInsets.fromLTRB(16, 14, 14, 14),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.10),
                border: Border(
                  bottom:
                      BorderSide(color: _accent.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconData, size: 18, color: _accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resource?.name ?? 'Resource',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.bodyStrong().copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₱${(rate / 100).toStringAsFixed(0)}/hr',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          color: _accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const _PulseDot(color: YColor.success),
              ]),
            ),
            // Customer + live timer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.person_outline,
                        size: 14, color: YColor.inkMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        session.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.bodyStrong().copyWith(fontSize: 13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text('ELAPSED',
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: YColor.inkMuted,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    _fmtClock(elapsed),
                    style: YFont.titleLG().copyWith(
                      fontSize: 34,
                      letterSpacing: -1.0,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('Running total · ₱${(liveCents / 100).toStringAsFixed(2)}',
                      style: YFont.caption().copyWith(fontSize: 11)),
                  if (stale) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: YColor.dangerSoft,
                        borderRadius: BorderRadius.circular(YRadius.sm),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 12, color: YColor.danger),
                        const SizedBox(width: 6),
                        Text(
                            'Running ${elapsed.inHours}h — did the '
                            'customer forget to check out?',
                            style: YFont.caption().copyWith(
                                fontSize: 10, color: YColor.danger)),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            // Stop button — full-width, can't miss it
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Stop & charge'),
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
            ),
          ],
        ),
      ),
    );
  }

  String _fmtClock(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _StartSessionDialog extends StatefulWidget {
  const _StartSessionDialog({required this.resources});
  final List<BookableResource> resources;

  @override
  State<_StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends State<_StartSessionDialog> {
  final TextEditingController _name = TextEditingController();
  String? _resourceId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to the first available resource so the cashier can
    // single-tap start (just hit "Start") for the most common case.
    if (widget.resources.isNotEmpty) {
      _resourceId = widget.resources.first.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy || _resourceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<BookingsStore>();
    final res = await state.startSession(
      resourceId: _resourceId!,
      customerName: _name.text,
    );
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }
    Navigator.of(context).pop(res.booking);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(children: [
                Text('Start a session',
                    style: YFont.titleLG().copyWith(fontSize: 20)),
                const Spacer(),
                IconButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Container(height: 0.5, color: YColor.hairline),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('WHERE?',
                      style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.resources.map((r) {
                      final on = _resourceId == r.id;
                      final icon = iconFromKey(r.iconName) ?? r.kind.icon;
                      return GestureDetector(
                        onTap: () => setState(() => _resourceId = r.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 130),
                          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: on ? YColor.brand : YColor.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: on ? YColor.brand : YColor.hairline,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon,
                                  size: 14,
                                  color: on ? Colors.white : YColor.brandDeep),
                              const SizedBox(width: 6),
                              Text(
                                r.name,
                                style: YFont.bodyStrong().copyWith(
                                  fontSize: 12,
                                  color: on ? Colors.white : YColor.ink,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '₱${r.hourlyRatePesos.toStringAsFixed(0)}/hr',
                                style: YFont.caption().copyWith(
                                  fontSize: 10,
                                  color: on
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : YColor.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text('CUSTOMER (OPTIONAL)',
                      style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      hintText: 'e.g. Maria, or leave blank for "Walk-in"',
                      filled: true,
                      fillColor: YColor.surface1,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(YRadius.md),
                        borderSide:
                            const BorderSide(color: YColor.hairline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(YRadius.md),
                        borderSide:
                            const BorderSide(color: YColor.hairline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(YRadius.md),
                        borderSide:
                            const BorderSide(color: YColor.brand, width: 1.5),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: YColor.dangerSoft,
                        borderRadius: BorderRadius.circular(YRadius.md),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: YColor.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: YFont.caption()
                                  .copyWith(color: YColor.danger)),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            Container(height: 0.5, color: YColor.hairline),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                const Spacer(),
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _resourceId == null || _busy ? null : _start,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Start now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny breathing-light dot used to signal "live" status.
class _PulseDot extends StatefulWidget {
  const _PulseDot({this.color = Colors.white});
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color:
              widget.color.withValues(alpha: 0.45 + 0.55 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
