import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/stores/hr_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/money.dart';
import '../../models/payroll.dart';
import '../../models/payroll_rules.dart';
import '../widgets/numpad_field.dart';
import '../widgets/push_toast.dart';

/// Two-pane payroll: left = timesheet (per-day hours per employee for the
/// current period), right = pay run preview computing gross / deductions /
/// net by employee. Owner can finalize a run and mark it paid.
class PayrollView extends StatefulWidget {
  const PayrollView({super.key});

  @override
  State<PayrollView> createState() => _PayrollViewState();
}

class _PayrollViewState extends State<PayrollView> {
  PayPeriodKind _period = PayPeriodKind.weekly;
  /// Index of the period, counted backwards from the current week (0 = this week).
  int _periodOffset = 0;
  PayrollRun? _selectedRun;
  bool _generating = false;

  /// Current period's [start, end] for the active [_period] and [_periodOffset],
  /// honoring the tenant's semi-monthly cutoff [style] (15 & 30 vs 10 & 25).
  ({DateTime start, DateTime end}) _periodRange(SemiMonthlyStyle style) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case PayPeriodKind.weekly:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final s = monday.subtract(Duration(days: 7 * _periodOffset));
        return (start: s, end: s.add(const Duration(days: 6)));
      case PayPeriodKind.biweekly:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final s = monday.subtract(Duration(days: 14 * _periodOffset));
        return (start: s, end: s.add(const Duration(days: 13)));
      case PayPeriodKind.monthly:
        final s = DateTime(today.year, today.month - _periodOffset, 1);
        return (start: s, end: DateTime(s.year, s.month + 1, 0));
      case PayPeriodKind.semiMonthly:
        var r = _currentSemiMonthly(style, today);
        for (var i = 0; i < _periodOffset; i++) {
          r = _prevSemiMonthly(style, r.start);
        }
        return r;
    }
  }

  /// The semi-monthly period that contains [today] for the given [style].
  ({DateTime start, DateTime end}) _currentSemiMonthly(
      SemiMonthlyStyle style, DateTime today) {
    final y = today.year, m = today.month, d = today.day;
    if (style == SemiMonthlyStyle.fifteenThirty) {
      return d <= 15
          ? (start: DateTime(y, m, 1), end: DateTime(y, m, 15))
          : (start: DateTime(y, m, 16), end: DateTime(y, m + 1, 0));
    }
    // 10 & 25: periods are 11–25 and 26–10 (the latter spans the month end).
    if (d >= 11 && d <= 25) {
      return (start: DateTime(y, m, 11), end: DateTime(y, m, 25));
    }
    return d >= 26
        ? (start: DateTime(y, m, 26), end: DateTime(y, m + 1, 10))
        : (start: DateTime(y, m - 1, 26), end: DateTime(y, m, 10));
  }

  /// The semi-monthly period immediately before the one starting at [start].
  ({DateTime start, DateTime end}) _prevSemiMonthly(
      SemiMonthlyStyle style, DateTime start) {
    if (style == SemiMonthlyStyle.fifteenThirty) {
      return start.day == 16
          ? (start: DateTime(start.year, start.month, 1),
              end: DateTime(start.year, start.month, 15))
          : (start: DateTime(start.year, start.month - 1, 16),
              end: DateTime(start.year, start.month, 0));
    }
    return start.day == 26
        ? (start: DateTime(start.year, start.month, 11),
            end: DateTime(start.year, start.month, 25))
        : (start: DateTime(start.year, start.month - 1, 26),
            end: DateTime(start.year, start.month, 10));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HrStore>();
    final range = _periodRange(state.payrollRules.semiMonthlyStyle);
    final periodStart = range.start;
    final periodEnd = range.end;

    return Container(
      color: YColor.surface2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left — timesheet
          Expanded(
            flex: 6,
            child: _TimesheetPane(
              state: state,
              period: _period,
              periodStart: periodStart,
              periodEnd: periodEnd,
              periodOffset: _periodOffset,
              onPeriodChange: (p) => setState(() {
                _period = p;
                _periodOffset = 0;
                _selectedRun = null;
              }),
              onShift: (delta) => setState(() {
                _periodOffset = (_periodOffset + delta).clamp(0, 60);
              }),
            ),
          ),
          Container(width: 0.5, color: YColor.hairline),
          // Right — pay run
          Expanded(
            flex: 5,
            child: _PayRunPane(
              state: state,
              period: _period,
              periodStart: periodStart,
              periodEnd: periodEnd,
              selectedRun: _selectedRun,
              generating: _generating,
              onSelectRun: (r) => setState(() => _selectedRun = r),
              onGenerate: () async {
                // Debounce: ignore taps while a run is already being built so
                // a double-tap can't stack duplicate runs.
                if (_generating) return;
                setState(() => _generating = true);
                final res = await state.generatePayrollRun(
                  start: periodStart,
                  end: periodEnd,
                  kind: _period,
                );
                if (!context.mounted) return;
                setState(() {
                  _generating = false;
                  // Open the run whether it was just created or already existed.
                  if (res.run != null) _selectedRun = res.run;
                });
                if (res.error != null) {
                  PushToast.show(
                    context,
                    title: res.run != null
                        ? 'Run already exists'
                        : 'Could not generate run',
                    subtitle: res.error!,
                    leadingIcon: res.run != null
                        ? Icons.info_outline
                        : Icons.error_outline,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ───── Timesheet pane ─────

class _TimesheetPane extends StatelessWidget {
  const _TimesheetPane({
    required this.state,
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.periodOffset,
    required this.onPeriodChange,
    required this.onShift,
  });

  final HrStore state;
  final PayPeriodKind period;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int periodOffset;
  final ValueChanged<PayPeriodKind> onPeriodChange;
  final ValueChanged<int> onShift;

  @override
  Widget build(BuildContext context) {
    final employees = state.employees
        .where((e) => e.status != EmployeeStatus.terminated)
        .toList();
    final days = _enumerateDays(periodStart, periodEnd);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: YColor.surface1,
                borderRadius: BorderRadius.circular(YRadius.lg),
              ),
              child: employees.isEmpty
                  ? Center(
                      child: Text('No employees yet.',
                          style: YFont.caption()))
                  // Size to content (narrow employee col + roomy day cells) so
                  // the Total sits just past the days and stays visible without
                  // the table stretching and squeezing the dates. Horizontal
                  // scroll only as a fallback on very narrow screens.
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _grid(employees, days),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final fmt = DateFormat('MMM d');
    return Row(
      children: [
        _IconBtn(
          icon: Icons.chevron_left,
          onTap: () => onShift(1),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${fmt.format(periodStart)} – ${fmt.format(periodEnd)}',
            style: YFont.bodyStrong(),
          ),
        ),
        const SizedBox(width: 6),
        _IconBtn(
          icon: Icons.chevron_right,
          onTap: periodOffset > 0 ? () => onShift(-1) : null,
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () async {
            final res =
                await state.syncTimesheetFromAttendance(periodStart, periodEnd);
            if (!context.mounted) return;
            final String title;
            final String subtitle;
            final IconData icon;
            if (res.error != null) {
              title = 'Could not sync';
              subtitle = res.error!;
              icon = Icons.error_outline;
            } else if (res.count == 0) {
              title = 'No hours to pull';
              subtitle =
                  'No completed shifts with payable hours in this period. '
                  'Make sure staff clocked OUT (open shifts count as 0).';
              icon = Icons.info_outline;
            } else {
              title = 'Pulled ${res.count} day(s) from attendance';
              subtitle = 'Timesheet updated from clock-ins';
              icon = Icons.check_circle_outline;
            }
            PushToast.show(context,
                title: title, subtitle: subtitle, leadingIcon: icon);
          },
          icon: const Icon(Icons.download_done, size: 16),
          label: const Text('Pull from attendance'),
          style: OutlinedButton.styleFrom(
            foregroundColor: YColor.brandDeep,
            side: const BorderSide(color: YColor.hairline),
          ),
        ),
        const SizedBox(width: 12),
        // Pay-period kind picker — compact icon popup (no inline label) so the
        // header stays tight and the timesheet grid keeps its width.
        PopupMenuButton<PayPeriodKind>(
          tooltip: 'Pay period',
          position: PopupMenuPosition.under,
          offset: const Offset(0, 8),
          color: YColor.surface1,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: YColor.hairline),
          ),
          onSelected: onPeriodChange,
          itemBuilder: (_) => [
            for (final p in PayPeriodKind.values)
              PopupMenuItem<PayPeriodKind>(
                value: p,
                height: 42,
                child: Row(children: [
                  Icon(Icons.check,
                      size: 15,
                      color: p == period ? YColor.brand : Colors.transparent),
                  const SizedBox(width: 8),
                  Text(p.label,
                      style: YFont.bodyStrong().copyWith(
                        fontSize: 13,
                        color: p == period ? YColor.brand : YColor.ink,
                      )),
                ]),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: YColor.surface1,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: YColor.hairline),
            ),
            child: const Icon(Icons.calendar_view_week_outlined,
                size: 18, color: YColor.brandDeep),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<Employee> employees, List<DateTime> days) {
    final dayFmt = DateFormat('E\nd');
    return DataTable(
      dataRowMaxHeight: 56,
      columnSpacing: 6,
      horizontalMargin: 12,
      headingTextStyle: YFont.caption().copyWith(
            fontWeight: FontWeight.w700,
            color: YColor.inkMuted,
            letterSpacing: 0.4,
          ),
      columns: [
        const DataColumn(label: Text('Employee')),
        for (final d in days)
          DataColumn(
            label: SizedBox(
              width: 44,
              child: Text(
                dayFmt.format(d).toUpperCase(),
                textAlign: TextAlign.center,
                style: YFont.caption().copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
            numeric: true,
          ),
        const DataColumn(label: Text('Total'), numeric: true),
      ],
      rows: [
        for (final emp in employees)
          DataRow(cells: [
            DataCell(_employeeChip(emp)),
            for (final d in days)
              DataCell(_HoursCell(
                employee: emp,
                date: d,
                hours: state.hoursIn(emp.id, d, d),
                onChanged: (h) => state.upsertTimeEntry(
                  employeeId: emp.id,
                  date: d,
                  hours: h,
                ),
              )),
            DataCell(_totalCell(emp)),
          ]),
      ],
    );
  }

  Widget _employeeChip(Employee e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(e.gender.icon, size: 18, color: YColor.brandDeep),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(fontSize: 13)),
              Text(
                switch (e.compensationType) {
                  CompensationType.hourly =>
                    'Hourly · ₱${e.hourlyRate.toStringAsFixed(0)}/hr',
                  CompensationType.daily =>
                    'Daily · ₱${e.dailyRate.toStringAsFixed(0)}/day',
                  CompensationType.salaried =>
                    'Salaried · ₱${e.monthlySalary.toStringAsFixed(0)}/mo',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YFont.caption().copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _totalCell(Employee e) {
    final total = state.hoursIn(e.id, periodStart, periodEnd);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        total == 0 ? '–' : '${total.toStringAsFixed(1)}h',
        style: YFont.bodyStrong().copyWith(fontSize: 13),
      ),
    );
  }

  List<DateTime> _enumerateDays(DateTime start, DateTime end) {
    final out = <DateTime>[];
    var d = start;
    while (!d.isAfter(end)) {
      out.add(d);
      d = d.add(const Duration(days: 1));
    }
    return out;
  }
}

class _HoursCell extends StatefulWidget {
  const _HoursCell({
    required this.employee,
    required this.date,
    required this.hours,
    required this.onChanged,
  });
  final Employee employee;
  final DateTime date;
  final double hours;
  final ValueChanged<double> onChanged;

  @override
  State<_HoursCell> createState() => _HoursCellState();
}

class _HoursCellState extends State<_HoursCell> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(
        text: widget.hours == 0 ? '' : _format(widget.hours));
  }

  @override
  void didUpdateWidget(covariant _HoursCell old) {
    super.didUpdateWidget(old);
    // Stale cache repaint — only refresh the text if the user isn't
    // actively typing. The KeyboardAccessoryField handles focus, so
    // we mirror the old behaviour by checking if our controller is
    // out of sync.
    if (widget.hours != old.hours &&
        (double.tryParse(_c.text) ?? 0) != widget.hours) {
      _c.text = widget.hours == 0 ? '' : _format(widget.hours);
    }
  }

  String _format(double h) {
    if (h == h.roundToDouble()) return h.toStringAsFixed(0);
    return h.toStringAsFixed(1);
  }

  void _commit() {
    final v = double.tryParse(_c.text) ?? 0;
    if (v != widget.hours) widget.onChanged(v);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Sheet header like "Hours · Maria · Mon 18" so the numpad identifies
  /// which cell is being edited.
  String _sheetTitle() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = weekdays[widget.date.weekday - 1];
    final firstName = widget.employee.name.split(' ').first;
    return 'Hours · $firstName · $weekday ${widget.date.day}';
  }

  Future<void> _edit() async {
    final result = await showNumpadSheet(
      context,
      title: _sheetTitle(),
      initial: _c.text,
      decimal: true,
      suffix: 'hr',
    );
    if (result != null) {
      _c.text = result;
      _commit();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fixed 44×34 envelope keeps the grid row height constant. Tapping the
    // cell opens the shared numpad sheet instead of the OS keyboard.
    final has = _c.text.trim().isNotEmpty;
    return SizedBox(
      width: 44,
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _edit,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.surface1,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: YColor.hairline),
            ),
            child: Text(
              has ? _c.text : '–',
              textAlign: TextAlign.center,
              style: YFont.body().copyWith(
                fontSize: 13,
                color: has ? YColor.ink : YColor.inkSubtle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon,
              size: 18,
              color: enabled ? YColor.ink : YColor.inkSubtle),
        ),
      ),
    );
  }
}

/// Pill-shaped back link rendered in the pay-run detail header so
/// the owner can pop back to the full list without leaving the
/// Payroll page. Mirrors the back-chip pattern used by other
/// detail screens in the app for visual consistency.
class _BackChip extends StatelessWidget {
  const _BackChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back_rounded,
                size: 14, color: YColor.brandDeep),
            const SizedBox(width: 6),
            Text(
              label,
              style: YFont.bodyStrong()
                  .copyWith(fontSize: 12, color: YColor.brandDeep),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───── Pay run pane ─────

class _PayRunPane extends StatelessWidget {
  const _PayRunPane({
    required this.state,
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.selectedRun,
    required this.generating,
    required this.onSelectRun,
    required this.onGenerate,
  });

  final HrStore state;
  final PayPeriodKind period;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PayrollRun? selectedRun;
  final bool generating;
  final ValueChanged<PayrollRun?> onSelectRun;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final runs = state.payrollRuns;
    final fmt = DateFormat('MMM d');
    final inDetail = selectedRun != null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header switches between list mode ("Pay runs" title) and
          // detail mode (back button + the run's period). The back
          // chip pops the selection so the user lands back on the
          // list of every run.
          Row(children: [
            if (inDetail) ...[
              _BackChip(
                label: 'All payroll runs',
                onTap: () => onSelectRun(null),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${fmt.format(selectedRun!.periodStart)} – '
                  '${fmt.format(selectedRun!.periodEnd)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.titleLG().copyWith(fontSize: 20),
                ),
              ),
            ] else
              Text('Pay runs',
                  style: YFont.titleLG().copyWith(fontSize: 20)),
            if (!inDetail) const Spacer(),
            ElevatedButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add, size: 16),
              label: Text(generating ? 'Generating…' : 'Generate run'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YColor.brand.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (inDetail)
            Expanded(child: _RunDetail(state: state, run: selectedRun!))
          else if (runs.isEmpty)
            Expanded(child: _emptyHint())
          else
            Expanded(child: _runList(runs)),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    final fmt = DateFormat('MMM d');
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.payments_outlined,
                size: 40, color: YColor.brandDeep),
            const SizedBox(height: 12),
            Text('No pay runs yet',
                style: YFont.titleMD().copyWith(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'Tap Generate run to snapshot ${fmt.format(periodStart)}–${fmt.format(periodEnd)} from the timesheet.',
              textAlign: TextAlign.center,
              style: YFont.caption(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runList(List<PayrollRun> runs) {
    final fmt = DateFormat('MMM d');
    return ListView.separated(
      itemCount: runs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = runs[i];
        return Material(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(YRadius.lg),
            onTap: () => onSelectRun(r),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: YColor.brandTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.payments_outlined,
                      color: YColor.brandDeep, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${fmt.format(r.periodStart)} – ${fmt.format(r.periodEnd)}',
                        style: YFont.bodyStrong(),
                      ),
                      Text(
                        '${r.slips.length} employees',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₱${r.totalNet.toStringAsFixed(0)}',
                        style: YFont.bodyStrong()
                            .copyWith(color: YColor.brand)),
                    const SizedBox(height: 2),
                    _statusChip(r.status),
                  ],
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(PayrollStatus status) {
    final (bg, fg) = switch (status) {
      PayrollStatus.draft => (YColor.surface3, YColor.inkMuted),
      PayrollStatus.finalized => (YColor.brandTint, YColor.brandDeep),
      PayrollStatus.paid => (YColor.successSoft, YColor.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: fg,
          )),
    );
  }
}

class _RunDetail extends StatelessWidget {
  const _RunDetail({required this.state, required this.run});
  final HrStore state;
  final PayrollRun run;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    final readonly = run.status == PayrollStatus.paid;
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmt.format(run.periodStart)} – ${fmt.format(run.periodEnd)}',
                    style: YFont.titleMD().copyWith(fontSize: 16),
                  ),
                  Text(
                    '${run.slips.length} employees',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            // Re-generate only on a draft — a finalized/paid run is locked.
            if (run.status == PayrollStatus.draft)
              OutlinedButton.icon(
                onPressed: () => _regenerate(context),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-generate'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: YColor.brandDeep,
                  side: const BorderSide(color: YColor.hairline),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            const SizedBox(width: 6),
            PopupMenuButton<PayrollStatus>(
              tooltip: 'Change status',
              icon: const Icon(Icons.more_vert, color: YColor.inkMuted),
              color: YColor.surface1,
              elevation: 8,
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: YColor.hairline),
              ),
              onSelected: (s) => state.setPayrollStatus(run.id, s),
              itemBuilder: (_) => [
                PopupMenuItem<PayrollStatus>(
                  enabled: false,
                  height: 34,
                  child: Text('SET STATUS',
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                        color: YColor.inkMuted,
                      )),
                ),
                for (final s in PayrollStatus.values)
                  PopupMenuItem<PayrollStatus>(
                    value: s,
                    height: 44,
                    child: Row(children: [
                      Icon(_statusIcon(s),
                          size: 16,
                          color: run.status == s
                              ? YColor.brand
                              : YColor.inkMuted),
                      const SizedBox(width: 10),
                      Text(s.label,
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 13,
                            color:
                                run.status == s ? YColor.brand : YColor.ink,
                            fontWeight: run.status == s
                                ? FontWeight.w700
                                : FontWeight.w500,
                          )),
                      if (run.status == s) ...[
                        const Spacer(),
                        const Icon(Icons.check,
                            size: 15, color: YColor.brand),
                      ],
                    ]),
                  ),
              ],
            ),
          ]),
        ),
        Container(height: 0.5, color: YColor.hairline),
        Expanded(
          child: ListView.separated(
            itemCount: run.slips.length,
            separatorBuilder: (_, __) =>
                Container(height: 0.5, color: YColor.hairline),
            itemBuilder: (_, i) {
              final s = run.slips[i];
              return _SlipRow(
                slip: s,
                period: run.kind,
                periodStart: run.periodStart,
                periodEnd: run.periodEnd,
                readonly: readonly,
                onChange: (updated) =>
                    state.updatePayslip(run.id, updated),
              );
            },
          ),
        ),
        Container(height: 0.5, color: YColor.hairline),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Gross', run.totalGross),
                  _summaryRow('Deductions', -run.totalDeductions),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('NET PAYABLE',
                    style: YFont.caption().copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    )),
                Text(
                  '₱${run.totalNet.toStringAsFixed(2)}',
                  style: YFont.titleLG()
                      .copyWith(fontSize: 22, color: YColor.brand),
                ),
              ],
            ),
          ]),
        ),
      ]),
    );
  }

  IconData _statusIcon(PayrollStatus s) => switch (s) {
        PayrollStatus.draft => Icons.edit_note_outlined,
        PayrollStatus.finalized => Icons.lock_outline,
        PayrollStatus.paid => Icons.check_circle_outline,
      };

  Widget _summaryRow(String label, double amount) {
    final neg = amount < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label, style: YFont.caption())),
          Text(
            '${neg ? '−' : ''}₱${amount.abs().toStringAsFixed(2)}',
            style: YFont.bodyStrong().copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Re-snapshot the run from current data (employee statutory / rates / time
  /// entries / attendance) while keeping each slip's manual bonus + deductions.
  Future<void> _regenerate(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: YColor.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.lg)),
        title: const Text('Re-generate this run?'),
        content: const Text(
          'Refreshes hours, overtime, undertime, rates and statutory '
          'deductions from current data. Bonuses and manual deductions you '
          'entered are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white),
            child: const Text('Re-generate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await state.regeneratePayrollRun(run.id);
    if (!context.mounted) return;
    PushToast.show(
      context,
      title: err == null ? 'Run re-generated' : 'Could not re-generate',
      subtitle: err ??
          'Hours, overtime, undertime and statutory were refreshed.',
      leadingIcon:
          err == null ? Icons.check_circle_outline : Icons.error_outline,
    );
  }
}

class _SlipRow extends StatefulWidget {
  const _SlipRow({
    required this.slip,
    required this.period,
    required this.periodStart,
    required this.periodEnd,
    required this.readonly,
    required this.onChange,
  });
  final Payslip slip;
  final PayPeriodKind period;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool readonly;
  final ValueChanged<Payslip> onChange;

  @override
  State<_SlipRow> createState() => _SlipRowState();
}

class _SlipRowState extends State<_SlipRow> {
  late final TextEditingController _bonus;
  late final TextEditingController _ded;

  @override
  void initState() {
    super.initState();
    _bonus = TextEditingController(
        text: widget.slip.bonus == 0
            ? ''
            : widget.slip.bonus.toStringAsFixed(0));
    _ded = TextEditingController(
        text: widget.slip.deductions == 0
            ? ''
            : widget.slip.deductions.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _bonus.dispose();
    _ded.dispose();
    super.dispose();
  }

  void _commit() {
    final bonus = double.tryParse(_bonus.text) ?? 0;
    final ded = double.tryParse(_ded.text) ?? 0;
    if (bonus == widget.slip.bonus && ded == widget.slip.deductions) {
      return;
    }
    final s = widget.slip;
    // Carry EVERY snapshot field forward — only bonus/deductions change here.
    widget.onChange(Payslip(
      id: s.id,
      employeeId: s.employeeId,
      employeeName: s.employeeName,
      employeeRole: s.employeeRole,
      compensationType: s.compensationType,
      hoursWorked: s.hoursWorked,
      hourlyRate: s.hourlyRate,
      dailyRate: s.dailyRate,
      monthlySalary: s.monthlySalary,
      bonus: bonus,
      deductions: ded,
      sss: s.sss,
      philHealth: s.philHealth,
      pagIbig: s.pagIbig,
      regularHoursPerDay: s.regularHoursPerDay,
      otHours: s.otHours,
      undertimeHours: s.undertimeHours,
      lateMinutes: s.lateMinutes,
      otMultiplier: s.otMultiplier,
      deductUndertime: s.deductUndertime,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slip;
    final gross = s.grossFor(widget.period);
    final net = s.netFor(widget.period);

    final detail = switch (s.compensationType) {
      CompensationType.hourly =>
        '${s.hoursWorked.toStringAsFixed(1)}h × ₱${s.hourlyRate.toStringAsFixed(0)}',
      CompensationType.daily =>
        '${(s.hoursWorked / (s.regularHoursPerDay > 0 ? s.regularHoursPerDay : 8)).toStringAsFixed(1)}d × ₱${s.dailyRate.toStringAsFixed(0)}',
      CompensationType.salaried =>
        'Salaried · ₱${s.monthlySalary.toStringAsFixed(0)}/mo',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.employeeName, style: YFont.bodyStrong()),
                  Text(
                    '${s.employeeRole} · $detail',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₱${net.toStringAsFixed(2)}',
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.brand)),
                Text('Gross ₱${gross.toStringAsFixed(0)}',
                    style: YFont.caption()),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          _payBreakdown(s),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openDtr(s),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_note_outlined,
                      size: 14, color: YColor.brandDeep),
                  const SizedBox(width: 5),
                  Text('View daily time record',
                      style: YFont.caption().copyWith(
                          color: YColor.brandDeep,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _amountField(
                label: 'Bonus',
                accessoryLabel: 'BONUS',
                controller: _bonus,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _amountField(
                label: 'Deductions / advances',
                accessoryLabel: 'DEDUCTIONS',
                controller: _ded,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Fully itemized payslip: EARNINGS (base pay + overtime) then DEDUCTIONS
  /// (undertime, statutory pro-rated, other). Every line is derived from the
  /// snapshot so the math reconciles to the net shown above, to the centavo.
  Widget _payBreakdown(Payslip s) {
    final p = widget.period;
    final perDay = s.regularHoursPerDay > 0 ? s.regularHoursPerDay : 8;
    final bonusC = (s.bonus * 100).round();
    // Base = gross minus OT minus bonus (the straight-time portion).
    final base = s.grossCentavosFor(p) - s.otPayCentavos - bonusC;
    final ot = s.otPayCentavos;
    final ut = s.undertimeCentavos;
    final sss = s.sssCentavosFor(p);
    final ph = s.philHealthCentavosFor(p);
    final pi = s.pagIbigCentavosFor(p);
    final other = (s.deductions * 100).round();

    final baseLabel = switch (s.compensationType) {
      CompensationType.hourly =>
        'Regular  ${s.hoursWorked.toStringAsFixed(1)}h × ₱${s.hourlyRate.toStringAsFixed(0)}',
      CompensationType.daily =>
        'Regular  ${(s.hoursWorked / perDay).toStringAsFixed(2)}d × ₱${s.dailyRate.toStringAsFixed(0)}',
      CompensationType.salaried => 'Salary  (this pay run)',
    };

    final hasDeduction =
        ut > 0 || sss > 0 || ph > 0 || pi > 0 || other > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _payLine(baseLabel, base, earning: true),
        if (ot > 0)
          _payLine(
              'Overtime  ${s.otHours.toStringAsFixed(1)}h × ${s.otMultiplier.toStringAsFixed(2)}×',
              ot,
              earning: true),
        if (bonusC > 0) _payLine('Bonus', bonusC, earning: true),
        if (hasDeduction) ...[
          const SizedBox(height: 2),
          if (ut > 0)
            _payLine('Undertime  ${s.undertimeHours.toStringAsFixed(1)}h', ut,
                earning: false),
          if (sss > 0) _payLine('SSS', sss, earning: false),
          if (ph > 0) _payLine('PhilHealth', ph, earning: false),
          if (pi > 0) _payLine('Pag-IBIG', pi, earning: false),
          if (other > 0)
            _payLine('Other deductions', other, earning: false),
        ],
      ],
    );
  }

  /// One itemized line: label left, signed amount right (green for an earning,
  /// danger red for a deduction).
  Widget _payLine(String label, int centavos, {required bool earning}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Expanded(child: Text(label, style: YFont.caption())),
          Text(
            '${earning ? '+' : '−'} ${Money(centavos).formatted}',
            style: YFont.caption().copyWith(
              color: earning ? YColor.success : YColor.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Open the per-day daily time record for this employee + period.
  Future<void> _openDtr(Payslip s) async {
    final store = context.read<HrStore>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: YColor.surface1,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DtrSheet(
        slip: s,
        start: widget.periodStart,
        end: widget.periodEnd,
        future: store.fetchEmployeeDtr(
            s.employeeId, widget.periodStart, widget.periodEnd),
      ),
    );
  }

  /// Bonus / Deductions input — same accessory-card treatment as
  /// every other money field in the app, so when you focus the
  /// keyboard a glass card pops up with a live peso preview of
  /// what's being typed.
  Widget _amountField({
    required String label,
    required String accessoryLabel,
    required TextEditingController controller,
  }) {
    final field = NumpadField(
      controller: controller,
      label: label,
      prefix: '₱',
      hint: '0',
      onChanged: (_) => _commit(),
    );
    // Paid runs are read-only — wrap with IgnorePointer (instead of
    // disabling the field) so the accessory bar styling still
    // matches the rest of the form.
    return widget.readonly
        ? Opacity(opacity: 0.55, child: IgnorePointer(child: field))
        : field;
  }
}

/// Per-day daily time record for one employee + pay period. Pulls the
/// schedule-aware server breakdown (regular / OT / undertime / late) and shows
/// it day-by-day so the owner can see exactly how the payslip hours were built.
class _DtrSheet extends StatelessWidget {
  const _DtrSheet({
    required this.slip,
    required this.start,
    required this.end,
    required this.future,
  });
  final Payslip slip;
  final DateTime start;
  final DateTime end;
  final Future<Map<String, dynamic>?> future;

  String _clock(int? mins) {
    if (mins == null) return '—';
    final h = mins ~/ 60, m = mins % 60;
    final ap = h < 12 ? 'AM' : 'PM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} $ap';
  }

  String _h(num minutes) {
    final v = minutes / 60.0;
    return v == v.roundToDouble()
        ? '${v.toStringAsFixed(0)}h'
        : '${v.toStringAsFixed(1)}h';
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: YFont.caption().copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d');
    final dfDay = DateFormat('EEE');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: YColor.hairline,
                  borderRadius: BorderRadius.circular(999)),
            ),
            Row(children: [
              const Icon(Icons.event_note_outlined,
                  size: 18, color: YColor.brandDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Daily time record',
                        style: YFont.titleMD().copyWith(fontSize: 16)),
                    Text(
                        '${slip.employeeName} · ${df.format(start)} – ${df.format(end)}',
                        style: YFont.caption()),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>?>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }
                final data = snap.data;
                final days = (data?['days'] as List?) ?? const [];
                if (data == null || days.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(children: [
                      const Icon(Icons.inbox_outlined,
                          size: 30, color: YColor.inkMuted),
                      const SizedBox(height: 8),
                      Text('No attendance punches in this period.',
                          style: YFont.caption()),
                      const SizedBox(height: 2),
                      Text('Hours came from the manual timesheet.',
                          style: YFont.caption()
                              .copyWith(color: YColor.inkSubtle)),
                    ]),
                  );
                }
                final reg = (data['regular_hours'] as num?) ?? 0;
                final ot = (data['ot_hours'] as num?) ?? 0;
                final ut = (data['undertime_hours'] as num?) ?? 0;
                final late = (data['late_minutes'] as num?) ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period totals strip.
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      _chip('Regular ${reg.toStringAsFixed(1)}h',
                          YColor.brandDeep),
                      if (ot > 0)
                        _chip('OT ${ot.toStringAsFixed(1)}h', YColor.success),
                      if (ut > 0)
                        _chip('Undertime ${ut.toStringAsFixed(1)}h',
                            YColor.danger),
                      if (late > 0)
                        _chip('Late ${late.toStringAsFixed(0)}m',
                            YColor.warning),
                    ]),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(context).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: days.length,
                        separatorBuilder: (_, __) => Container(
                            height: 0.5, color: YColor.hairline),
                        itemBuilder: (_, i) {
                          final day =
                              days[i] as Map<String, dynamic>;
                          final date =
                              DateTime.parse(day['date'] as String);
                          final inMin = (day['first_in'] as num?)?.toInt();
                          final outMin = (day['last_out'] as num?)?.toInt();
                          final dayOt = (day['ot_min'] as num?) ?? 0;
                          final dayUt =
                              (day['undertime_min'] as num?) ?? 0;
                          final dayLate = (day['late_min'] as num?) ?? 0;
                          final dayReg = (day['regular_min'] as num?) ?? 0;
                          final dayRest =
                              (day['restday_min'] as num?) ?? 0;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              SizedBox(
                                width: 64,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(dfDay.format(date),
                                        style: YFont.bodyStrong()
                                            .copyWith(fontSize: 12)),
                                    Text(df.format(date),
                                        style: YFont.caption()),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${_clock(inMin)}  –  ${_clock(outMin)}',
                                  style: YFont.caption()
                                      .copyWith(color: YColor.ink),
                                ),
                              ),
                              Wrap(spacing: 5, children: [
                                _chip(_h(dayReg + dayRest), YColor.brandDeep),
                                if (dayOt > 0)
                                  _chip('OT ${_h(dayOt)}', YColor.success),
                                if (dayUt > 0)
                                  _chip('UT ${_h(dayUt)}', YColor.danger),
                                if (dayLate > 0)
                                  _chip('${dayLate.toStringAsFixed(0)}m',
                                      YColor.warning),
                              ]),
                            ]),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
