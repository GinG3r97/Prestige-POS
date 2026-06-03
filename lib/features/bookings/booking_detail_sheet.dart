import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart' show iconFromKey;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/booking.dart';
import '../widgets/push_toast.dart';

/// Bottom-sheet detail card for an existing booking. Lets the cashier
/// mark it complete (when the time has passed) or cancel it.
class BookingDetailSheet extends StatefulWidget {
  const BookingDetailSheet({super.key, required this.booking});
  final Booking booking;

  @override
  State<BookingDetailSheet> createState() => _BookingDetailSheetState();
}

class _BookingDetailSheetState extends State<BookingDetailSheet> {
  bool _busy = false;

  Future<void> _setStatus(BookingStatus s) async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final err = await state.updateBookingStatus(widget.booking.id, s);
    if (!mounted) return;
    if (err != null) {
      setState(() => _busy = false);
      PushToast.show(context,
          title: 'Could not update',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(
      context,
      title: 'Booking ${s.label.toLowerCase()}',
      subtitle: widget.booking.customerName,
      leadingIcon: switch (s) {
        BookingStatus.cancelled => Icons.cancel_outlined,
        BookingStatus.noShow => Icons.no_accounts_outlined,
        BookingStatus.completed => Icons.check_circle_outline,
        _ => Icons.event_available_outlined,
      },
    );
    Navigator.of(context).pop(true);
  }

  String _fmtTime(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  String _fmtDate(DateTime t) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final b = widget.booking;
    final resource = state.resourceById(b.resourceId);
    final accent = _accent(resource);
    final iconData = resource == null
        ? Icons.event_outlined
        : (iconFromKey(resource.iconName) ?? resource.kind.icon);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconData, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(b.customerName,
                          style: YFont.titleMD()
                              .copyWith(fontSize: 18, letterSpacing: -0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        resource?.name ?? 'Resource removed',
                        style: YFont.caption()
                            .copyWith(color: YColor.inkMuted),
                      ),
                    ],
                  ),
                ),
                _statusPill(b.status),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 14),
              Container(height: 0.5, color: YColor.hairline),
              const SizedBox(height: 14),
              _row(
                Icons.calendar_today_outlined,
                'Date',
                _fmtDate(b.startsAt),
              ),
              const SizedBox(height: 10),
              _row(
                Icons.schedule,
                'Time',
                b.endsAt == null
                    ? '${_fmtTime(b.startsAt)} – live '
                        '(elapsed ${_fmtDuration(b.duration)})'
                    : '${_fmtTime(b.startsAt)} – ${_fmtTime(b.endsAt!)} '
                        '(${_fmtDuration(b.duration)})',
              ),
              if ((b.customerPhone ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                _row(Icons.phone_outlined, 'Phone', b.customerPhone!),
              ],
              const SizedBox(height: 10),
              _row(
                Icons.payments_outlined,
                'Price',
                '₱${b.pricePesos.toStringAsFixed(0)}',
                valueColor: YColor.brand,
                valueBold: true,
              ),
              if ((b.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _row(
                  Icons.sticky_note_2_outlined,
                  'Notes',
                  b.notes!.trim(),
                ),
              ],
              const SizedBox(height: 18),
              // Actions
              if (b.status == BookingStatus.confirmed)
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _setStatus(BookingStatus.cancelled),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: YColor.danger,
                        side: const BorderSide(color: YColor.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => _setStatus(BookingStatus.noShow),
                      icon: const Icon(Icons.no_accounts_outlined, size: 16),
                      label: const Text('No-show'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: YColor.ink,
                        side: const BorderSide(color: YColor.hairline),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _setStatus(BookingStatus.completed),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Mark complete'),
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
                ])
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: YColor.surface2,
                    borderRadius: BorderRadius.circular(YRadius.md),
                  ),
                  child: Row(children: [
                    Icon(_statusIcon(b.status),
                        size: 16,
                        color: _statusTone(b.status)),
                    const SizedBox(width: 8),
                    Text(
                      'This booking is ${b.status.label.toLowerCase()} — '
                      'no actions available.',
                      style: YFont.caption(),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accent(BookableResource? r) {
    final raw = r?.color;
    if (raw == null || raw.isEmpty) return YColor.brand;
    final hex = raw.replaceFirst('#', '');
    final v = int.tryParse('FF$hex', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  Color _statusTone(BookingStatus s) => switch (s) {
        BookingStatus.cancelled => YColor.inkMuted,
        BookingStatus.noShow => YColor.danger,
        BookingStatus.completed => YColor.success,
        _ => YColor.brand,
      };

  IconData _statusIcon(BookingStatus s) => switch (s) {
        BookingStatus.cancelled => Icons.cancel_outlined,
        BookingStatus.noShow => Icons.no_accounts_outlined,
        BookingStatus.completed => Icons.check_circle_outline,
        _ => Icons.event_available_outlined,
      };

  Widget _statusPill(BookingStatus s) {
    final tone = _statusTone(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_statusIcon(s), size: 10, color: tone),
        const SizedBox(width: 4),
        Text(
          s.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: tone,
          ),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor, bool valueBold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: YColor.inkMuted),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(label,
              style: YFont.caption().copyWith(color: YColor.inkMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: (valueBold ? YFont.bodyStrong() : YFont.body()).copyWith(
              fontSize: 13,
              color: valueColor ?? YColor.ink,
            ),
          ),
        ),
      ],
    );
  }

  String _fmtDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inMinutes % 60 == 0) return '${d.inHours} hr';
    return '${d.inHours} hr ${d.inMinutes % 60} min';
  }
}
