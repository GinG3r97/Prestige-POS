import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../printing/bt_printer.dart';
import '../printing/printer_setup_sheet.dart';
import '../sell/shift_bar.dart';
import '../settings/subscription_view.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/mock_data.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          if (state.tenant?.logoUrl?.isNotEmpty ?? false) ...[
            Container(
              width: 34,
              height: 34,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: YColor.hairline),
              ),
              child: Image.network(
                state.tenant!.logoUrl!,
                fit: BoxFit.cover,
                cacheWidth: 180,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Plan + live daily-order usage, with a tappable Upgrade for
          // Free/Basic. Replaces the store name (each page shows its own H1).
          const _PlanUsageChip(),
          // Cashier-shift status lives here beside the store name: full
          // float/sales/orders + Close on the Sell tab, a compact "still open"
          // reminder elsewhere. Expanded so the right-side controls stay right.
          const SizedBox(width: 16),
          Container(width: 1, height: 28, color: YColor.hairline),
          const SizedBox(width: 16),
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ShiftHeaderBar(),
            ),
          ),
          // Branch picker — only for the owner or roles granted the
          // 'switch_branch' capability, AND only when there's more than one
          // branch to switch between (single-branch stores hide it entirely).
          if (state.canSwitchBranch &&
              (state.tenant?.branches.length ?? 1) > 1) ...[
            PopupMenuButton<Branch>(
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              color: YColor.surface1,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: YColor.hairline),
              ),
              onSelected: (b) => state.selectBranch(b),
              itemBuilder: (_) {
                final branches = state.tenant?.branches ?? MockData.branches;
                final current = state.selectedBranch.name;
                return [
                  for (final b in branches)
                    PopupMenuItem(
                      value: b,
                      child: Row(children: [
                        Icon(Icons.location_city,
                            size: 16,
                            color: b.name == current
                                ? YColor.brand
                                : YColor.inkMuted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(b.name,
                              style: YFont.bodyStrong().copyWith(
                                color: b.name == current
                                    ? YColor.brand
                                    : YColor.ink,
                              )),
                        ),
                        if (b.name == current) ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.check, size: 16, color: YColor.brand),
                        ],
                      ]),
                    ),
                ];
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: YColor.surface3,
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_city, size: 13),
                  const SizedBox(width: 8),
                  Text(state.selectedBranch.name, style: YFont.bodyStrong()),
                  const SizedBox(width: 6),
                  const Icon(Icons.expand_more, size: 14),
                ]),
              ),
            ),
            const SizedBox(width: YSpacing.sm),
          ],
          const _PrinterStatusChip(),
          const SizedBox(width: YSpacing.sm),
          // Lock button — tapping signs the current staff out so the next
          // user has to re-enter their PIN. Replaces the old "Online"
          // status pill (which was a passive indicator with no action).
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              // Flip the lock state FIRST so AnimatedSwitcher swaps the
              // underlying root route to the "Locking…" loader on the
              // next frame. THEN pop open modals — they slide away
              // revealing the loader (not the shell), so no blink.
              state.lockSession();
              Navigator.of(context, rootNavigator: true)
                  .popUntil((r) => r.isFirst);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: YColor.surface3,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: YColor.hairline),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline,
                    size: 14, color: YColor.brandDeep),
                const SizedBox(width: 6),
                Text(
                  'Lock',
                  style: YFont.bodyStrong().copyWith(
                    fontSize: 12,
                    color: YColor.ink,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top-bar chip: current plan + today's order usage as a green/amber/red bar.
/// Free & Basic show an "Upgrade" affordance; Pro shows a full green bar.
/// Tapping anywhere opens Settings → Subscription.
class _PlanUsageChip extends StatelessWidget {
  const _PlanUsageChip();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isPro = state.plan == 'pro';
    final cap = state.ordersCap;
    final used = state.ordersToday;
    final frac = (cap == null || cap == 0) ? 1.0 : (used / cap).clamp(0.0, 1.0);
    final Color bar = isPro
        ? YColor.success
        : frac >= 1.0
            ? YColor.danger
            : frac >= 0.7
                ? Colors.amber.shade700
                : YColor.success;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscriptionView()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${state.planLabel} Plan',
                  style: YFont.titleMD().copyWith(fontSize: 15)),
              if (!isPro) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: YColor.brand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_upward_rounded,
                        size: 11, color: Colors.white),
                    const SizedBox(width: 3),
                    Text('Upgrade',
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 5),
            SizedBox(
              width: 154,
              child: Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: isPro ? 1.0 : frac,
                      minHeight: 5,
                      backgroundColor: YColor.surface3,
                      color: bar,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isPro ? '∞' : (cap == null ? '—' : '$used/$cap'),
                  style: YFont.caption()
                      .copyWith(fontWeight: FontWeight.w700, color: bar),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-bar chip showing the receipt printer status — green when connected,
/// amber when a printer is saved but disconnected, grey when none. Tapping it
/// opens the same printer setup as Settings → Receipt printer.
class _PrinterStatusChip extends StatefulWidget {
  const _PrinterStatusChip();

  @override
  State<_PrinterStatusChip> createState() => _PrinterStatusChipState();
}

class _PrinterStatusChipState extends State<_PrinterStatusChip> {
  Timer? _timer;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  Future<void> _check() async {
    final c = await BtPrinter.isConnected;
    if (mounted && c != _connected) setState(() => _connected = c);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final printer = state.printerConfig;
    final Color dot;
    final String label;
    if (printer == null) {
      dot = YColor.inkMuted;
      label = 'No printer';
    } else if (_connected) {
      dot = YColor.success;
      label = printer.name;
    } else {
      dot = Colors.orange;
      label = 'Reconnect';
    }
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => showPrinterSetup(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: YColor.surface3,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.print_outlined, size: 14, color: YColor.brandDeep),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: YFont.bodyStrong().copyWith(
                  fontSize: 12, color: YColor.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

