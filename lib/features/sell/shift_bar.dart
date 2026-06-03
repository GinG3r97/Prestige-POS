import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../../models/shift.dart';
import '../printing/print_jobs.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// The cashier-shift bar shown at the top of the Sell page. Open Cashier (with
/// a starting float) when closed; live sales + Close Cashier (Z-reading) when
/// open.
class ShiftBar extends StatefulWidget {
  const ShiftBar({super.key});

  @override
  State<ShiftBar> createState() => _ShiftBarState();
}

class _ShiftBarState extends State<ShiftBar> {
  Timer? _timer;
  ShiftTotals _totals = const ShiftTotals();

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    if (!state.hasOpenShift) return;
    final t = await state.shiftTotals();
    if (mounted) setState(() => _totals = t);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final shift = state.currentShift;
    final open = state.hasOpenShift && shift != null;

    return Container(
      width: double.infinity,
      color: open ? YColor.brandTint : YColor.surface1,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: Row(children: [
        Icon(open ? Icons.point_of_sale : Icons.lock_clock_outlined,
            size: 18, color: open ? YColor.brandDeep : YColor.inkMuted),
        const SizedBox(width: 10),
        Expanded(
          child: open
              ? Row(children: [
                  _stat('Cash float', Money(shift.openingFloatCents).formatted),
                  _dot(),
                  _stat('Sales today', Money(_totals.totalSalesCents).formatted),
                  _dot(),
                  _stat('Orders', '${_totals.orderCount}'),
                ])
              : Text('Cashier is closed — open it to start the day.',
                  style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        const SizedBox(width: 12),
        if (open)
          OutlinedButton.icon(
            onPressed: () => _close(context, state),
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Close Cashier'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.danger,
              side: const BorderSide(color: YColor.hairline),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () => _open(context, state),
            icon: const Icon(Icons.lock_open_outlined, size: 16),
            label: const Text('Open Cashier'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
      ]),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: YFont.caption().copyWith(
                fontSize: 9, letterSpacing: 0.8, color: YColor.inkMuted)),
        Text(value, style: YFont.bodyStrong().copyWith(color: YColor.brandDeep)),
      ],
    );
  }

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: Text('·', style: TextStyle(color: YColor.inkMuted)),
      );

  Future<void> _open(BuildContext context, AppState state) async {
    await showDialog(context: context, builder: (_) => const _OpenShiftDialog());
    if (mounted) _refresh();
  }

  Future<void> _close(BuildContext context, AppState state) async {
    await showDialog(context: context, builder: (_) => const _CloseShiftDialog());
    if (mounted) _refresh();
  }
}

class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();
  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _float = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pesos = double.tryParse(_float.text.trim()) ?? 0;
    final cents = Money.pesos(pesos).centavos;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().openShift(cents);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop();
    PushToast.show(context,
        title: 'Cashier opened',
        subtitle: 'Starting cash: ${Money(cents).formatted}',
        leadingIcon: Icons.lock_open_outlined);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Open cashier', style: YFont.titleMD()),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Count the cash in the drawer now and enter it as your '
                'starting amount (beginning money).',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 12),
            KeyboardAccessoryField(
              controller: _float,
              accessoryLabel: 'Beginning money (₱)',
              label: 'Beginning money (₱)',
              hint: '0.00',
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: moneyInputFormatters,
              formatPreview: (raw) {
                final n = double.tryParse(raw) ?? 0;
                return Money.pesos(n).formatted;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: YFont.caption().copyWith(color: YColor.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Open'),
        ),
      ],
    );
  }
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog();
  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _counted = TextEditingController();
  ShiftTotals? _totals;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await context.read<AppState>().shiftTotals();
    if (mounted) setState(() => _totals = t);
  }

  @override
  void dispose() {
    _counted.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final state = context.read<AppState>();
    final cents = Money.pesos(double.tryParse(_counted.text.trim()) ?? 0).centavos;
    setState(() => _busy = true);
    final closed = await state.closeShift(cents);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (closed == null) {
      PushToast.show(context,
          title: 'Could not close the shift',
          subtitle: 'Please try again.',
          leadingIcon: Icons.error_outline);
      return;
    }
    // Show the Z-reading.
    showDialog(
      context: context,
      builder: (_) => _ZReadingDialog(shift: closed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final shift = state.currentShift;
    final totals = _totals;
    final floatC = shift?.openingFloatCents ?? 0;
    final expected = floatC + (totals?.cashSalesCents ?? 0);
    final counted = Money.pesos(double.tryParse(_counted.text.trim()) ?? 0).centavos;
    final overShort = counted - expected;

    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Close cashier (Z-reading)', style: YFont.titleMD()),
      content: SizedBox(
        width: 380,
        child: totals == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Beginning money', Money(floatC).formatted),
                  _row('Cash sales', Money(totals.cashSalesCents).formatted),
                  const Divider(),
                  _row('Expected cash in drawer', Money(expected).formatted,
                      bold: true),
                  const SizedBox(height: 12),
                  KeyboardAccessoryField(
                    controller: _counted,
                    accessoryLabel: 'Counted cash (₱)',
                    label: 'Count the drawer now (₱)',
                    hint: '0.00',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: moneyInputFormatters,
                    onChanged: (_) => setState(() {}),
                    formatPreview: (raw) =>
                        Money.pesos(double.tryParse(raw) ?? 0).formatted,
                  ),
                  if (_counted.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _row(
                      overShort == 0
                          ? 'Balanced'
                          : overShort > 0
                              ? 'Over'
                              : 'Short',
                      Money(overShort.abs()).formatted,
                      tone: overShort == 0
                          ? YColor.success
                          : YColor.danger,
                      bold: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _row('Total sales (all methods)',
                      Money(totals.totalSalesCents).formatted),
                  _row('Card', Money(totals.cardSalesCents).formatted),
                  _row('Other', Money(totals.otherSalesCents).formatted),
                  _row('Orders', '${totals.orderCount}'),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton(
          onPressed: _busy || totals == null ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.danger,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Close shift'),
        ),
      ],
    );
  }

  Widget _row(String k, String v,
      {bool bold = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(k,
            style: (bold ? YFont.bodyStrong() : YFont.body())
                .copyWith(color: tone ?? YColor.ink)),
        const Spacer(),
        Text(v,
            style: (bold ? YFont.bodyStrong() : YFont.body())
                .copyWith(color: tone ?? YColor.ink)),
      ]),
    );
  }
}

/// Final Z-reading summary after closing, with a print button.
class _ZReadingDialog extends StatelessWidget {
  const _ZReadingDialog({required this.shift});
  final CashierShift shift;

  @override
  Widget build(BuildContext context) {
    final over = shift.overShortCents ?? 0;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.summarize_outlined, color: YColor.brandDeep),
        const SizedBox(width: 10),
        Text('Z-Reading', style: YFont.titleMD()),
      ]),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _r('Beginning money', Money(shift.openingFloatCents).formatted),
            _r('Cash sales', Money(shift.cashSalesCents ?? 0).formatted),
            _r('Expected cash', Money(shift.expectedCashCents ?? 0).formatted),
            _r('Counted cash', Money(shift.countedCashCents ?? 0).formatted),
            _r(over == 0 ? 'Balanced' : (over > 0 ? 'Over' : 'Short'),
                Money(over.abs()).formatted,
                tone: over == 0 ? YColor.success : YColor.danger, bold: true),
            const Divider(),
            _r('Total sales', Money(shift.totalSalesCents ?? 0).formatted,
                bold: true),
            _r('Orders', '${shift.orderCount ?? 0}'),
          ],
        ),
      ),
      actions: [
        Builder(builder: (context) {
          final state = context.read<AppState>();
          final tenant = state.tenant;
          final printer = state.printerConfig;
          if (tenant == null || printer == null) return const SizedBox.shrink();
          return OutlinedButton.icon(
            onPressed: () async {
              final ok = await PrintJobs.zReading(
                  shift: shift, tenant: tenant, config: printer);
              if (context.mounted) {
                PushToast.show(context,
                    title: ok ? 'Z-reading printed' : 'Print failed',
                    leadingIcon: ok
                        ? Icons.check_circle_outline
                        : Icons.print_disabled_outlined);
              }
            },
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print'),
            style: OutlinedButton.styleFrom(
                foregroundColor: YColor.brand,
                side: const BorderSide(color: YColor.hairline)),
          );
        }),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _r(String k, String v, {bool bold = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(k,
            style: (bold ? YFont.bodyStrong() : YFont.body())
                .copyWith(color: tone ?? YColor.ink)),
        const Spacer(),
        Text(v,
            style: (bold ? YFont.bodyStrong() : YFont.body())
                .copyWith(color: tone ?? YColor.ink)),
      ]),
    );
  }
}
