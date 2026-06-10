import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/stores/bookings_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart' show iconFromKey;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/booking.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

class BookingFormDialog extends StatefulWidget {
  const BookingFormDialog({
    super.key,
    required this.day,
    this.prefilledResourceId,
    this.prefilledStart,
    this.prefilledEnd,
  });

  final DateTime day;
  final String? prefilledResourceId;
  final DateTime? prefilledStart;
  final DateTime? prefilledEnd;

  @override
  State<BookingFormDialog> createState() => _BookingFormDialogState();
}

class _BookingFormDialogState extends State<BookingFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  String? _resourceId;
  late DateTime _startsAt;
  late Duration _duration;
  bool _busy = false;
  String? _error;

  static const _durationOptions = <Duration>[
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 4),
    Duration(hours: 8),
  ];

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _notes = TextEditingController();
    _resourceId = widget.prefilledResourceId;
    final now = DateTime.now();
    final defaultStart = widget.prefilledStart ??
        DateTime(widget.day.year, widget.day.month, widget.day.day,
            now.hour, now.minute >= 30 ? 30 : 0);
    _startsAt = _roundToHalf(defaultStart);
    _duration = widget.prefilledEnd != null
        ? widget.prefilledEnd!.difference(_startsAt)
        : const Duration(hours: 1);
  }

  DateTime _roundToHalf(DateTime t) {
    final m = t.minute >= 30 ? 30 : 0;
    return DateTime(t.year, t.month, t.day, t.hour, m);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _resourceId != null && !_busy;

  DateTime get _endsAt => _startsAt.add(_duration);

  int _previewPriceCents() {
    final state = context.read<BookingsStore>();
    final r = state.resourceById(_resourceId);
    if (r == null) return 0;
    return r.priceFor(_duration);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (picked == null) return;
    setState(() {
      _startsAt = DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        picked.hour,
        picked.minute >= 30 ? 30 : 0,
      );
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<BookingsStore>();
    final result = await state.createBooking(
      resourceId: _resourceId!,
      customerName: _name.text,
      customerPhone: _phone.text,
      startsAt: _startsAt,
      endsAt: _endsAt,
      notes: _notes.text,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    PushToast.show(
      context,
      title: 'Booking saved',
      subtitle: '${_name.text.trim()} · '
          '${_fmtTime(_startsAt)} – ${_fmtTime(_endsAt)}',
      leadingIcon: Icons.event_available_outlined,
    );
    Navigator.of(context).pop(result.booking);
  }

  String _fmtTime(DateTime t) {
    final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    final p = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $p';
  }

  String _fmtDuration(Duration d) {
    if (d.inHours == 0) return '${d.inMinutes} min';
    if (d.inMinutes % 60 == 0) return '${d.inHours} hr';
    return '${d.inHours} hr ${d.inMinutes % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BookingsStore>();
    final resources = state.bookableResources;
    final preview = _previewPriceCents();
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          // Cap dialog height so the body scrolls instead of overflowing
          // when the keyboard is up or the screen is short.
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(children: [
                Text('New Booking',
                    style: YFont.titleLG().copyWith(fontSize: 20)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Container(height: 0.5, color: YColor.hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Resource picker (chips)
                    _label('Resource'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: resources.map((r) {
                        final on = _resourceId == r.id;
                        final icon = iconFromKey(r.iconName) ?? r.kind.icon;
                        return GestureDetector(
                          onTap: () => setState(() => _resourceId = r.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 130),
                            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
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
                                    color: on
                                        ? Colors.white
                                        : YColor.brandDeep),
                                const SizedBox(width: 6),
                                Text(
                                  r.name,
                                  style: YFont.bodyStrong().copyWith(
                                    fontSize: 12,
                                    color: on ? Colors.white : YColor.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    KeyboardAccessoryField(
                      controller: _name,
                      label: 'Customer name',
                      accessoryLabel: 'CUSTOMER',
                      hint: 'e.g. Maria Reyes',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    KeyboardAccessoryField(
                      controller: _phone,
                      label: 'Phone (optional)',
                      accessoryLabel: 'PHONE',
                      hint: '09xx xxx xxxx',
                      keyboardType: TextInputType.phone,
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Start'),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: _pickStartTime,
                              borderRadius: BorderRadius.circular(YRadius.md),
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                decoration: BoxDecoration(
                                  color: YColor.surface1,
                                  borderRadius:
                                      BorderRadius.circular(YRadius.md),
                                  border: Border.all(color: YColor.hairline),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.schedule,
                                      size: 16, color: YColor.brandDeep),
                                  const SizedBox(width: 8),
                                  Text(_fmtTime(_startsAt),
                                      style: YFont.bodyStrong()
                                          .copyWith(fontSize: 13)),
                                  const Spacer(),
                                  const Icon(Icons.expand_more,
                                      size: 16, color: YColor.inkMuted),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Duration'),
                            const SizedBox(height: 6),
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              decoration: BoxDecoration(
                                color: YColor.surface1,
                                borderRadius:
                                    BorderRadius.circular(YRadius.md),
                                border: Border.all(color: YColor.hairline),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<Duration>(
                                  value: _durationOptions.contains(_duration)
                                      ? _duration
                                      : _durationOptions[1],
                                  isExpanded: true,
                                  icon: const Icon(Icons.expand_more,
                                      size: 16, color: YColor.inkMuted),
                                  items: _durationOptions
                                      .map((d) => DropdownMenuItem(
                                            value: d,
                                            child: Text(_fmtDuration(d),
                                                style: YFont.bodyStrong()
                                                    .copyWith(fontSize: 13)),
                                          ))
                                      .toList(),
                                  onChanged: (d) {
                                    if (d != null) {
                                      setState(() => _duration = d);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: YColor.brandTint.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(YRadius.md),
                      ),
                      child: Row(children: [
                        const Icon(Icons.event_outlined,
                            size: 16, color: YColor.brandDeep),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_fmtTime(_startsAt)} – ${_fmtTime(_endsAt)}',
                            style: YFont.bodyStrong()
                                .copyWith(fontSize: 13),
                          ),
                        ),
                        Text(
                          '₱${(preview / 100).toStringAsFixed(0)}',
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 16,
                            color: YColor.brand,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    KeyboardAccessoryField(
                      controller: _notes,
                      label: 'Notes (optional)',
                      accessoryLabel: 'NOTES',
                      hint: 'AV setup, catering, special requests',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: YColor.dangerSoft,
                          borderRadius: BorderRadius.circular(YRadius.md),
                          border:
                              Border.all(color: YColor.danger.withValues(alpha: 0.4)),
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
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ))
                      : const Text('Save booking'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text.toUpperCase(),
        style: YFont.caption().copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: YColor.brandDeep,
        ),
      );
}
