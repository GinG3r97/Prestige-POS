import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../../models/shift.dart';
import '../auth/otp_numpad.dart';
import '../orders/date_range_sheet.dart';
import '../printing/print_jobs.dart';
import '../widgets/push_toast.dart';

/// Opens the "Open cashier" dialog (start a shift with a float).
Future<void> showOpenCashier(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _OpenShiftDialog());

/// Opens the "Close cashier" (Z-reading) dialog.
Future<void> showCloseCashier(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _CloseShiftDialog());

/// Shows a (read-only) Z-reading summary for a past/closed shift.
void showZReadingFor(BuildContext context, CashierShift shift) =>
    showDialog(context: context, builder: (_) => _ZReadingDialog(shift: shift));

/// Big right-aligned amount display fed by the on-screen [OtpNumpad]. Digits
/// accumulate as centavos (type 1·0·0·0·0·0 → ₱1,000.00) so no keyboard is
/// raised — consistent with the OTP entry.
Widget _amountDisplay(int cents, {bool error = false}) {
  return Container(
    height: 60,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: YColor.surface2,
      borderRadius: BorderRadius.circular(YRadius.md),
      border:
          Border.all(color: error ? YColor.danger : YColor.brand, width: 1.4),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(Money(cents).formatted,
          style: YFont.titleLG().copyWith(
              fontSize: 30, color: YColor.brand, fontWeight: FontWeight.w800)),
    ),
  );
}

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

/// Compact cashier-shift status for the global TopBar (sits beside the store
/// name). Replaces the in-page bar while a shift is open:
///  • On the Sell tab — live Float · Sales · Orders + Close Cashier.
///  • On any other tab — collapses to a small "Cashier is still open" reminder
///    that taps back to Sell.
///  • Hidden entirely when no shift is open (the Sell page shows Open Cashier).
/// Slides + fades between the two states as the active tab changes.
class ShiftHeaderBar extends StatefulWidget {
  const ShiftHeaderBar({super.key});

  @override
  State<ShiftHeaderBar> createState() => _ShiftHeaderBarState();
}

class _ShiftHeaderBarState extends State<ShiftHeaderBar> {
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
    final onSell = state.selectedRoute == AppRoute.sell;

    Widget child;
    if (!open) {
      child = const SizedBox.shrink(key: ValueKey('shift-none'));
    } else if (onSell) {
      child = _full(context, shift, key: const ValueKey('shift-full'));
    } else {
      child = _reminder(state, key: const ValueKey('shift-reminder'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Keep entering/leaving children pinned to the left (the default
      // centres them, which would make the pill jump as it animates).
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (w, anim) => ClipRect(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-0.12, 0),
            end: Offset.zero,
          ).animate(anim),
          child: FadeTransition(opacity: anim, child: w),
        ),
      ),
      child: child,
    );
  }

  Widget _full(BuildContext context, CashierShift shift, {Key? key}) {
    // scaleDown guarantees the pill never overflows the header on a narrow
    // tablet — it shrinks slightly instead of throwing. Float · Sales · Orders
    // then a divider and Close Cashier, all in one header pill.
    return FittedBox(
      key: key,
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: YColor.brandTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.point_of_sale, size: 14, color: YColor.brandDeep),
          const SizedBox(width: 10),
          _hstat('Float', Money(shift.openingFloatCents).formatted),
          _hdot(),
          _hstat('Sales', Money(_totals.totalSalesCents).formatted),
          _hdot(),
          _hstat('Orders', '${_totals.orderCount}'),
          _hbar(),
          GestureDetector(
            onTap: () async {
              await showCloseCashier(context);
              if (mounted) _refresh();
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 13, color: YColor.danger),
              const SizedBox(width: 5),
              Text('Close Cashier',
                  style: YFont.bodyStrong()
                      .copyWith(fontSize: 12.5, color: YColor.danger)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _hbar() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        width: 1,
        height: 16,
        color: YColor.brandDeep.withValues(alpha: 0.3),
      );

  Widget _reminder(AppState state, {Key? key}) {
    return InkWell(
      key: key,
      onTap: () => state.selectRoute(AppRoute.sell),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: YColor.brandTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: YColor.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('Cashier is still open',
              style: YFont.bodyStrong()
                  .copyWith(fontSize: 12, color: YColor.brandDeep)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 14, color: YColor.brandDeep),
        ]),
      ),
    );
  }

  Widget _hstat(String label, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('${label.toUpperCase()} ',
          style: YFont.caption().copyWith(
              fontSize: 9, letterSpacing: 0.6, color: YColor.inkMuted)),
      Text(value,
          style: YFont.bodyStrong()
              .copyWith(fontSize: 13, color: YColor.brandDeep)),
    ]);
  }

  Widget _hdot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Text('·', style: TextStyle(color: YColor.inkMuted)),
      );
}

class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();
  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  int _cents = 0;
  bool _busy = false;
  String? _error;

  void _onDigit(String d) {
    final v = _cents * 10 + int.parse(d);
    if (v <= 99999999) setState(() {
      _cents = v;
      _error = null;
    });
  }

  void _onBackspace() => setState(() => _cents = _cents ~/ 10);

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().openShift(_cents);
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
        subtitle: 'Starting cash: ${Money(_cents).formatted}',
        leadingIcon: Icons.lock_open_outlined);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: YColor.surface1,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Icon(Icons.lock_open_outlined, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Text('Open cashier',
                    style: YFont.titleLG().copyWith(fontSize: 22)),
                const Spacer(),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Count the cash in the drawer now and enter it as '
                            'your starting amount (beginning money).',
                            style: YFont.body().copyWith(
                                color: YColor.inkMuted, height: 1.4)),
                        const SizedBox(height: 20),
                        Text('BEGINNING MONEY', style: YFont.caption()),
                        const SizedBox(height: 8),
                        _amountDisplay(_cents, error: _error != null),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: YFont.caption()
                                  .copyWith(color: YColor.danger)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OtpNumpad(
                        onDigit: _onDigit,
                        onBackspace: _onBackspace,
                        enabled: !_busy,
                        keyWidth: 62,
                        keyHeight: 46,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 250,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: YColor.brand,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(YRadius.md)),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('Open cashier'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseShiftDialog extends StatefulWidget {
  const _CloseShiftDialog();
  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  int _cents = 0;
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

  void _onDigit(String d) {
    final v = _cents * 10 + int.parse(d);
    if (v <= 99999999) setState(() => _cents = v);
  }

  void _onBackspace() => setState(() => _cents = _cents ~/ 10);

  Future<void> _confirm() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    final closed = await state.closeShift(_cents);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (closed == null) {
      PushToast.show(context,
          title: 'Could not close the shift',
          subtitle: 'Please try again.',
          leadingIcon: Icons.error_outline);
      return;
    }
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
    final overShort = _cents - expected;

    return Dialog(
      backgroundColor: YColor.surface1,
      insetPadding: const EdgeInsets.symmetric(horizontal: 50, vertical: 30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          child: totals == null
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.lock_outline, color: YColor.brandDeep),
                      const SizedBox(width: 10),
                      Text('Close cashier (Z-reading)',
                          style: YFont.titleLG().copyWith(fontSize: 21)),
                      const Spacer(),
                      IconButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _row('Beginning money', Money(floatC).formatted),
                              _row('Cash sales',
                                  Money(totals.cashSalesCents).formatted),
                              const Divider(),
                              _row('Expected cash in drawer',
                                  Money(expected).formatted,
                                  bold: true),
                              const SizedBox(height: 14),
                              Text('COUNT THE DRAWER NOW',
                                  style: YFont.caption()),
                              const SizedBox(height: 8),
                              _amountDisplay(_cents),
                              if (_cents > 0) ...[
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
                              const Divider(),
                              _row('Total sales (all methods)',
                                  Money(totals.totalSalesCents).formatted),
                              _row('Card',
                                  Money(totals.cardSalesCents).formatted),
                              _row('Other',
                                  Money(totals.otherSalesCents).formatted),
                              _row('Orders', '${totals.orderCount}'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 28),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OtpNumpad(
                              onDigit: _onDigit,
                              onBackspace: _onBackspace,
                              enabled: !_busy,
                              keyWidth: 62,
                              keyHeight: 46,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Close action anchored to the bottom of the modal.
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YRadius.md)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Close shift'),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool bold = false, Color? tone}) {
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

/// Opens the Shifts history (Z-readings) — reprint any past Z-reading and
/// print a today's-sales report.
void showShiftsSheet(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(24),
      child: _ShiftsSheet(),
    ),
  );
}

class _ShiftsSheet extends StatefulWidget {
  const _ShiftsSheet();
  @override
  State<_ShiftsSheet> createState() => _ShiftsSheetState();
}

class _ShiftsSheetState extends State<_ShiftsSheet> {
  List<CashierShift>? _shifts;
  bool _printingToday = false;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await context.read<AppState>().fetchShifts();
    if (mounted) setState(() => _shifts = s);
  }

  Future<void> _printToday() async {
    final state = context.read<AppState>();
    final tenant = state.tenant;
    final printer = state.printerConfig;
    if (tenant == null || printer == null) {
      PushToast.show(context,
          title: 'No printer connected',
          subtitle: 'Set one up in Settings → Receipt printer.',
          leadingIcon: Icons.print_disabled_outlined);
      return;
    }
    setState(() => _printingToday = true);
    final totals = await state.salesTotalsForToday();
    final ok = await PrintJobs.salesReport(
      tenant: tenant,
      config: printer,
      title: 'SALES REPORT',
      subtitle: 'Today',
      totals: totals,
    );
    if (!mounted) return;
    setState(() => _printingToday = false);
    PushToast.show(context,
        title: ok ? "Today's sales printed" : 'Print failed',
        leadingIcon:
            ok ? Icons.check_circle_outline : Icons.print_disabled_outlined);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangeSheet(context, initial: _range);
    if (picked != null) setState(() => _range = picked);
  }

  bool _inRange(DateTime d, DateTimeRange r) {
    final start = DateTime(r.start.year, r.start.month, r.start.day);
    final end = DateTime(r.end.year, r.end.month, r.end.day)
        .add(const Duration(days: 1));
    return !d.isBefore(start) && d.isBefore(end);
  }

  String _fmtRange(DateTimeRange r) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final s = r.start, e = r.end;
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) return '${m[s.month - 1]} ${s.day}, ${s.year}';
    final sameYear = s.year == e.year;
    final left = '${m[s.month - 1]} ${s.day}${sameYear ? '' : ', ${s.year}'}';
    return '$left – ${m[e.month - 1]} ${e.day}, ${e.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final isOwner = state.isOwnerSession;
    final myName = state.currentStaff?.name;
    var shifts = _shifts;
    // Cashier scoping: a non-owner sees only their OWN shifts.
    if (shifts != null && !isOwner) {
      shifts = shifts.where((s) => s.openedByName == myName).toList();
    }
    // Date filter (range).
    if (shifts != null && _range != null) {
      shifts = shifts
          .where((s) => _inRange(s.openedAt.toLocal(), _range!))
          .toList();
    }
    // Fixed height keeps the dialog from re-laying-out (and "blinking") when
    // the async shift list loads in.
    final screenH = MediaQuery.of(context).size.height;
    final dialogH = screenH < 720 ? screenH - 96 : 600.0;
    return Container(
      width: 520,
      height: dialogH,
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(children: [
              const Icon(Icons.summarize_outlined, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Shifts & Z-readings',
                    style: YFont.titleMD(),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis),
              ),
              // Store-wide total — owner only. Cashiers see just their own
              // shifts and can reprint their own Z-readings by tapping a row.
              if (isOwner)
                OutlinedButton.icon(
                  onPressed: _printingToday ? null : _printToday,
                  icon: _printingToday
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_outlined, size: 16),
                  label: const Text("Print today's sales"),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: YColor.brand,
                      side: const BorderSide(color: YColor.hairline)),
                ),
              if (isOwner)
                IconButton(
                  tooltip: 'BIR exports',
                  onPressed: () => showBirExports(context),
                  icon: const Icon(Icons.description_outlined,
                      color: YColor.brandDeep),
                ),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() => _range = null),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _range == null ? YColor.brand : YColor.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('All',
                      style: YFont.bodyStrong().copyWith(
                          fontSize: 12,
                          color: _range == null ? Colors.white : YColor.ink)),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _pickRange,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _range != null ? YColor.brand : YColor.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13,
                        color:
                            _range != null ? Colors.white : YColor.brandDeep),
                    const SizedBox(width: 6),
                    Text(_range != null ? _fmtRange(_range!) : 'Pick a date',
                        style: YFont.bodyStrong().copyWith(
                            fontSize: 12,
                            color:
                                _range != null ? Colors.white : YColor.ink)),
                  ]),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Builder(builder: (_) {
              final list = shifts;
              if (list == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (list.isEmpty) {
                return Center(
                  child: Text(
                      _range != null
                          ? 'No shifts in this range.'
                          : 'No shifts yet.',
                      style:
                          YFont.caption().copyWith(color: YColor.inkMuted)),
                );
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    Container(height: 0.5, color: YColor.hairline),
                itemBuilder: (_, i) => _shiftRow(list[i]),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _shiftRow(CashierShift s) {
    final over = s.overShortCents ?? 0;
    final closed = s.status == 'closed';
    return InkWell(
      onTap: () => showZReadingFor(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: closed ? YColor.surface2 : YColor.brandTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(closed ? Icons.receipt_long_outlined : Icons.lock_open,
                size: 18,
                color: closed ? YColor.inkMuted : YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmt(s.openedAt),
                    style: YFont.bodyStrong(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    closed
                        ? '${s.openedByName ?? 'Cashier'} · ${s.orderCount ?? 0} orders'
                        : 'OPEN · ${s.openedByName ?? 'Cashier'}',
                    style: YFont.caption().copyWith(color: YColor.inkMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money(s.totalSalesCents ?? 0).formatted,
                  style: YFont.bodyStrong().copyWith(color: YColor.brand)),
              if (closed)
                Text(
                    over == 0
                        ? 'Balanced'
                        : '${over > 0 ? 'Over' : 'Short'} ${Money(over.abs()).formatted}',
                    style: YFont.caption().copyWith(
                        color: over == 0 ? YColor.success : YColor.danger)),
            ],
          ),
        ]),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${m[d.month-1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2,'0')} $ap';
  }
}

/// Owner-only BIR export menu: e-Journal, monthly eSales summary, and an
/// EIS-style JSON export. Each generates text the owner can copy out.
void showBirExports(BuildContext context) {
  showDialog(context: context, builder: (_) => const _BirExportsDialog());
}

class _BirExportsDialog extends StatelessWidget {
  const _BirExportsDialog();

  Future<void> _run(
    BuildContext context,
    String title,
    Future<String> Function(AppState s, DateTimeRange r) build,
  ) async {
    final range = await showDateRangeSheet(context);
    if (range == null || !context.mounted) return;
    final state = context.read<AppState>();
    final text = await build(state, range);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => _TextViewerDialog(title: title, text: text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 420,
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(children: [
              const Icon(Icons.description_outlined, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Expanded(child: Text('BIR exports', style: YFont.titleMD())),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          _option(
            context,
            Icons.menu_book_outlined,
            'Electronic Journal',
            'All invoices for a date range (chronological).',
            () => _run(context, 'Electronic Journal',
                (s, r) => s.buildEJournal(r.start, r.end)),
          ),
          _option(
            context,
            Icons.summarize_outlined,
            'eSales monthly summary',
            'Gross / VATable / VAT-exempt for the month you pick.',
            () => _run(context, 'eSales Monthly Summary',
                (s, r) => s.buildESalesSummary(r.start.year, r.start.month)),
          ),
          _option(
            context,
            Icons.data_object_outlined,
            'EIS invoice JSON',
            'Invoice data for a range (e-invoicing stepping stone).',
            () => _run(context, 'EIS Invoice JSON',
                (s, r) => s.buildEisInvoicesJson(r.start, r.end)),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _option(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: YColor.brandDeep),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: YFont.bodyStrong()),
                const SizedBox(height: 2),
                Text(subtitle, style: YFont.caption()),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: YColor.inkMuted, size: 18),
        ]),
      ),
    );
  }
}

/// Read-only monospace viewer with a Copy-to-clipboard action.
class _TextViewerDialog extends StatelessWidget {
  const _TextViewerDialog({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 560,
        height: h < 720 ? h - 96 : 620,
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(children: [
              Expanded(child: Text(title, style: YFont.titleMD())),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: Container(
              width: double.infinity,
              color: YColor.surface2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  text,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12, height: 1.4),
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (!context.mounted) return;
                  PushToast.show(context,
                      title: 'Copied to clipboard',
                      leadingIcon: Icons.check_circle_outline);
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
