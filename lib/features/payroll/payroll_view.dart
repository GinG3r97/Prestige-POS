import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/stores/hr_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/payroll.dart';
import '../widgets/keyboard_accessory_field.dart';
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

  DateTime get _periodStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_period) {
      case PayPeriodKind.weekly:
        // Monday of the target week
        final monday =
            today.subtract(Duration(days: today.weekday - 1));
        return monday.subtract(Duration(days: 7 * _periodOffset));
      case PayPeriodKind.biweekly:
        final monday =
            today.subtract(Duration(days: today.weekday - 1));
        return monday.subtract(Duration(days: 14 * _periodOffset));
      case PayPeriodKind.semiMonthly:
        final isSecondHalf = today.day >= 16;
        final base = isSecondHalf
            ? DateTime(today.year, today.month, 16)
            : DateTime(today.year, today.month, 1);
        var s = base;
        for (var i = 0; i < _periodOffset; i++) {
          s = _previousSemiMonthly(s);
        }
        return s;
      case PayPeriodKind.monthly:
        return DateTime(today.year, today.month - _periodOffset, 1);
    }
  }

  DateTime _previousSemiMonthly(DateTime s) {
    if (s.day == 16) return DateTime(s.year, s.month, 1);
    final prev = DateTime(s.year, s.month - 1, 16);
    return prev;
  }

  DateTime get _periodEnd {
    final start = _periodStart;
    switch (_period) {
      case PayPeriodKind.weekly:
        return start.add(const Duration(days: 6));
      case PayPeriodKind.biweekly:
        return start.add(const Duration(days: 13));
      case PayPeriodKind.semiMonthly:
        if (start.day == 1) {
          return DateTime(start.year, start.month, 15);
        }
        return DateTime(start.year, start.month + 1, 0); // last of month
      case PayPeriodKind.monthly:
        return DateTime(start.year, start.month + 1, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HrStore>();

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
              periodStart: _periodStart,
              periodEnd: _periodEnd,
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
              periodStart: _periodStart,
              periodEnd: _periodEnd,
              selectedRun: _selectedRun,
              onSelectRun: (r) => setState(() => _selectedRun = r),
              onGenerate: () async {
                final res = await state.generatePayrollRun(
                  start: _periodStart,
                  end: _periodEnd,
                  kind: _period,
                );
                if (!context.mounted) return;
                if (res.error != null) {
                  PushToast.show(
                    context,
                    title: 'Could not generate run',
                    subtitle: res.error!,
                    leadingIcon: Icons.error_outline,
                  );
                  return;
                }
                setState(() => _selectedRun = res.run);
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
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth:
                              MediaQuery.sizeOf(context).width * 0.55,
                        ),
                        child: SingleChildScrollView(
                          child: _grid(employees, days),
                        ),
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
        Text('Timesheet', style: YFont.titleLG().copyWith(fontSize: 20)),
        const SizedBox(width: 12),
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
        DropdownButtonHideUnderline(
          child: DropdownButton<PayPeriodKind>(
            value: period,
            onChanged: (p) => p == null ? null : onPeriodChange(p),
            items: PayPeriodKind.values
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.label, style: YFont.body()),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<Employee> employees, List<DateTime> days) {
    final dayFmt = DateFormat('E\nd');
    return DataTable(
      dataRowMaxHeight: 56,
      columnSpacing: 14,
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
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.name,
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
              style: YFont.caption().copyWith(fontSize: 11),
            ),
          ],
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

  /// Builds the accessory-bar label like "HOURS · MARIA · MON 18"
  /// so the floating card identifies which cell the user is editing.
  String _accessoryLabel() {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final weekday = weekdays[widget.date.weekday - 1];
    final firstName =
        widget.employee.name.split(' ').first.toUpperCase();
    return 'HOURS · $firstName · $weekday ${widget.date.day}';
  }

  @override
  Widget build(BuildContext context) {
    // Fixed 44×34 envelope so the grid row stays the same height
    // whether or not the cell is focused. `isDense: true` collapses
    // the default 48px Material min-height that was making cells
    // look oversized.
    return SizedBox(
      width: 44,
      height: 34,
      child: KeyboardAccessoryField(
        controller: _c,
        accessoryLabel: _accessoryLabel(),
        hint: '–',
        textAlign: TextAlign.center,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        // Numbers + one decimal only — rejects letters and symbols
        // before they reach the controller, so paste / hardware
        // keyboards can't sneak invalid input in.
        inputFormatters: moneyInputFormatters,
        textStyle: YFont.body().copyWith(fontSize: 13),
        fillColor: YColor.surface1,
        borderColor: YColor.hairline,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        // Live preview of the typed value as "8.0 hrs" — gives the
        // owner instant confirmation in the accessory card without
        // squinting at the small grid cell.
        formatPreview: (raw) {
          final n = double.tryParse(raw) ?? 0;
          return n == n.roundToDouble()
              ? '${n.toStringAsFixed(0)} hrs'
              : '${n.toStringAsFixed(1)} hrs';
        },
        // Defer the DB write until the user moves on — avoids a
        // round-trip per keystroke.
        onFocusLost: _commit,
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
    required this.onSelectRun,
    required this.onGenerate,
  });

  final HrStore state;
  final PayPeriodKind period;
  final DateTime periodStart;
  final DateTime periodEnd;
  final PayrollRun? selectedRun;
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
              onPressed: onGenerate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Generate run'),
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
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
                        '${r.slips.length} employees · ${r.kind.label}',
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
                    '${run.kind.label} · ${run.slips.length} employees',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            PopupMenuButton<PayrollStatus>(
              tooltip: 'Change status',
              icon: const Icon(Icons.more_vert),
              onSelected: (s) => state.setPayrollStatus(run.id, s),
              itemBuilder: (_) => PayrollStatus.values
                  .map((s) => PopupMenuItem(
                        value: s,
                        child: Text(s.label),
                      ))
                  .toList(),
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
}

class _SlipRow extends StatefulWidget {
  const _SlipRow({
    required this.slip,
    required this.period,
    required this.readonly,
    required this.onChange,
  });
  final Payslip slip;
  final PayPeriodKind period;
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
    widget.onChange(Payslip(
      id: widget.slip.id,
      employeeId: widget.slip.employeeId,
      employeeName: widget.slip.employeeName,
      employeeRole: widget.slip.employeeRole,
      compensationType: widget.slip.compensationType,
      hoursWorked: widget.slip.hoursWorked,
      hourlyRate: widget.slip.hourlyRate,
      dailyRate: widget.slip.dailyRate,
      monthlySalary: widget.slip.monthlySalary,
      bonus: bonus,
      deductions: ded,
      regularHoursPerDay: widget.slip.regularHoursPerDay,
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

  /// Bonus / Deductions input — same accessory-card treatment as
  /// every other money field in the app, so when you focus the
  /// keyboard a glass card pops up with a live peso preview of
  /// what's being typed.
  Widget _amountField({
    required String label,
    required String accessoryLabel,
    required TextEditingController controller,
  }) {
    final field = KeyboardAccessoryField(
      controller: controller,
      label: label,
      accessoryLabel: accessoryLabel,
      hint: '0',
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      // Numbers + one decimal only — letters and special characters
      // can't reach the controller even via paste or a hardware
      // keyboard.
      inputFormatters: moneyInputFormatters,
      fillColor: YColor.surface1,
      borderColor: YColor.hairline,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      formatPreview: (raw) {
        final n = double.tryParse(raw) ?? 0;
        return '₱${n.toStringAsFixed(2)}';
      },
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
