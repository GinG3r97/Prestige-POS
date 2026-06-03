import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// A friendly, on-theme date-range picker for the Orders screen.
///
/// Built to replace Flutter's stock full-screen `showDateRangePicker`, which
/// is clunky on a tablet. This one leads with one-tap presets (the thing an
/// owner reaches for 95% of the time) and offers a simple inline calendar for
/// custom spans: tap a start day, tap an end day, done.
///
/// Returns the chosen [DateTimeRange], or null if dismissed.
Future<DateTimeRange?> showDateRangeSheet(
  BuildContext context, {
  DateTimeRange? initial,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _DateRangeSheet(initial: initial),
  );
}

class _DateRangeSheet extends StatefulWidget {
  const _DateRangeSheet({this.initial});
  final DateTimeRange? initial;

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  late DateTime _month; // the month shown in the calendar
  DateTime? _start;
  DateTime? _end;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  @override
  void initState() {
    super.initState();
    final today = _d(DateTime.now());
    _start = widget.initial != null ? _d(widget.initial!.start) : null;
    _end = widget.initial != null ? _d(widget.initial!.end) : null;
    _month = DateTime((_end ?? today).year, (_end ?? today).month);
  }

  // ───── presets ─────
  void _applyPreset(DateTime start, DateTime end) {
    Navigator.of(context).pop(DateTimeRange(start: _d(start), end: _d(end)));
  }

  // ───── calendar tap logic ─────
  void _tapDay(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        // Start a fresh selection.
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  bool _inRange(DateTime d) {
    if (_start == null) return false;
    final s = _start!;
    final e = _end ?? _start!;
    return !d.isBefore(s) && !d.isAfter(e);
  }

  @override
  Widget build(BuildContext context) {
    final today = _d(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final monthStart = DateTime(today.year, today.month, 1);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 380,
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                const Icon(Icons.event_outlined, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Filter by date', style: YFont.titleMD())),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Container(height: 0.5, color: YColor.hairline),

            // Quick presets
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _preset('Today', () => _applyPreset(today, today)),
                  _preset('Yesterday',
                      () => _applyPreset(yesterday, yesterday)),
                  _preset('Last 7 days',
                      () => _applyPreset(
                          today.subtract(const Duration(days: 6)), today)),
                  _preset('Last 30 days',
                      () => _applyPreset(
                          today.subtract(const Duration(days: 29)), today)),
                  _preset('This month', () => _applyPreset(monthStart, today)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Text('Or pick a custom range',
                    style: YFont.caption().copyWith(color: YColor.inkMuted)),
                const Spacer(),
                Text(_rangeLabel(),
                    style: YFont.bodyStrong()
                        .copyWith(fontSize: 12, color: YColor.brandDeep)),
              ]),
            ),

            _calendar(today),

            Container(height: 0.5, color: YColor.hairline),
            // Footer actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(children: [
                TextButton(
                  onPressed: _start == null
                      ? null
                      : () => setState(() {
                            _start = null;
                            _end = null;
                          }),
                  style: TextButton.styleFrom(
                      foregroundColor: YColor.inkMuted),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _start == null
                      ? null
                      : () => Navigator.of(context).pop(DateTimeRange(
                          start: _start!, end: _end ?? _start!)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: YColor.surface3,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                  child: const Text('Apply'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preset(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: YColor.brandTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        child: Text(label,
            style: YFont.bodyStrong()
                .copyWith(fontSize: 13, color: YColor.brandDeep)),
      ),
    );
  }

  // ───── calendar ─────
  Widget _calendar(DateTime today) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final canNext = _month.year < today.year ||
        (_month.year == today.year && _month.month < today.month);

    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sun-first grid (Sun=0)

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const Expanded(child: SizedBox(height: 40)));
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      cells.add(Expanded(child: _dayCell(date, today)));
    }
    while (cells.length % 7 != 0) {
      cells.add(const Expanded(child: SizedBox(height: 40)));
    }
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 7) {
      rows.add(Row(children: cells.sublist(i, i + 7)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          // Month nav
          Row(children: [
            IconButton(
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left, color: YColor.brandDeep),
            ),
            Expanded(
              child: Text('${months[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center, style: YFont.bodyStrong()),
            ),
            IconButton(
              onPressed: canNext
                  ? () => setState(() =>
                      _month = DateTime(_month.year, _month.month + 1))
                  : null,
              icon: Icon(Icons.chevron_right,
                  color: canNext ? YColor.brandDeep : YColor.inkSubtle),
            ),
          ]),
          // Weekday header
          Row(
            children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map((w) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 6),
                          child: _Weekday(w),
                        ),
                      ),
                    ))
                .toList(),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _dayCell(DateTime date, DateTime today) {
    final disabled = date.isAfter(today);
    final isStart = _start != null && date == _start;
    final isEnd = _end != null && date == _end;
    final isEndpoint = isStart || isEnd;
    final inRange = _inRange(date);
    final isToday = date == today;

    return GestureDetector(
      onTap: disabled ? null : () => _tapDay(date),
      child: Container(
        height: 40,
        // Continuous tint band across the selected span.
        color: inRange && !isEndpoint
            ? YColor.brandTint
            : Colors.transparent,
        alignment: Alignment.center,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isEndpoint ? YColor.brand : Colors.transparent,
            shape: BoxShape.circle,
            border: isToday && !isEndpoint
                ? Border.all(color: YColor.brand, width: 1.2)
                : null,
          ),
          child: Text(
            '${date.day}',
            style: YFont.body().copyWith(
              color: disabled
                  ? YColor.inkSubtle
                  : isEndpoint
                      ? Colors.white
                      : YColor.ink,
              fontWeight: isEndpoint || isToday
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  String _rangeLabel() {
    if (_start == null) return 'None';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String fmt(DateTime d) => '${m[d.month - 1]} ${d.day}';
    if (_end == null || _end == _start) return fmt(_start!);
    return '${fmt(_start!)} – ${fmt(_end!)}';
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: YFont.caption()
          .copyWith(color: YColor.inkSubtle, fontWeight: FontWeight.w700));
}
