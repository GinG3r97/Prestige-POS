import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import 'attendance_view.dart';
import 'requests_view.dart';

/// The "Attendance" destination: a left rail (DTR · OT · UT · Leave) hosting
/// the daily time record and the per-type request approvals.
class AttendanceHubView extends StatefulWidget {
  const AttendanceHubView({super.key});

  @override
  State<AttendanceHubView> createState() => _AttendanceHubViewState();
}

class _AttendanceHubViewState extends State<AttendanceHubView> {
  int _index = 0;

  static const _items = <_RailItem>[
    _RailItem(Icons.fact_check_outlined, 'DTR', 'Daily record'),
    _RailItem(Icons.more_time, 'Overtime', 'OT filings'),
    _RailItem(Icons.timer_off_outlined, 'Undertime', 'UT filings'),
    _RailItem(Icons.beach_access_outlined, 'Leave', 'Leave filings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColor.surface2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(),
          Container(width: 0.5, color: YColor.hairline),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                AttendanceView(embedded: true),
                RequestsView(kind: 'ot', embedded: true),
                RequestsView(kind: 'undertime', embedded: true),
                RequestsView(kind: 'leave', embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail() {
    return Container(
      width: 188,
      color: YColor.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Text('ATTENDANCE',
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: YColor.inkMuted,
                )),
          ),
          for (var i = 0; i < _items.length; i++) _railItem(i, _items[i]),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _railItem(int i, _RailItem item) {
    final sel = _index == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: sel ? YColor.brand : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _index = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon,
                    size: 20,
                    color: sel ? Colors.white : YColor.inkMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label,
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : YColor.ink,
                          )),
                      Text(item.sub,
                          style: YFont.caption().copyWith(
                            fontSize: 10.5,
                            color: sel
                                ? Colors.white.withValues(alpha: 0.82)
                                : YColor.inkMuted,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem {
  const _RailItem(this.icon, this.label, this.sub);
  final IconData icon;
  final String label;
  final String sub;
}
