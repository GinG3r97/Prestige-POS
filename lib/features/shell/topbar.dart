import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../printing/bt_printer.dart';
import '../printing/printer_setup_sheet.dart';
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
          // Back-to-More button — only visible while the active route is one
          // of the secondary destinations hosted inside the More hub.
          if (_isMoreChild(state.selectedRoute)) ...[
            _BackToMoreButton(onTap: () => state.selectRoute(AppRoute.more)),
            const SizedBox(width: 10),
          ],
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
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Topbar title is the store name, not the route name — the
              // active page already shows its own H1, so doubling up was
              // redundant. Falls back to "Store" while the tenant is still
              // loading on cold start.
              Text(
                state.tenant?.businessName.isNotEmpty == true
                    ? state.tenant!.businessName
                    : 'Store',
                style: YFont.titleLG(),
              ),
              Text(_dateString(), style: YFont.caption()),
            ],
          ),
          const Spacer(),
          // Branch picker (current store's branches)
          PopupMenuButton<Branch>(
            position: PopupMenuPosition.under,
            onSelected: (b) => state.selectBranch(b),
            itemBuilder: (_) =>
                (state.tenant?.branches ?? MockData.branches)
                    .map((b) => PopupMenuItem(value: b, child: Text(b.name)))
                    .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: YColor.surface3, borderRadius: BorderRadius.circular(999)),
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

  String _dateString() => DateFormat('EEEE, MMM d · h:mm a').format(DateTime.now());

  static bool _isMoreChild(AppRoute r) {
    const inMore = <AppRoute>{
      AppRoute.reports,
      AppRoute.employees,
      AppRoute.payroll,
      AppRoute.products,
      AppRoute.maintenance,
      AppRoute.settings,
    };
    return inMore.contains(r);
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

class _BackToMoreButton extends StatelessWidget {
  const _BackToMoreButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: YColor.surface3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 14),
            const SizedBox(width: 6),
            Text('More',
                style: YFont.bodyStrong().copyWith(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
