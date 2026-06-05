import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import 'drawer_prefs.dart';
import 'print_jobs.dart';

/// Cash-drawer settings + manual "no sale" open. The drawer is wired to the
/// receipt printer's RJ11/RJ12 port and pops via an ESC/POS pulse, so it shares
/// the configured printer — there's no separate device to pair.
class CashDrawerDialog extends StatefulWidget {
  const CashDrawerDialog({super.key});

  @override
  State<CashDrawerDialog> createState() => _CashDrawerDialogState();
}

class _CashDrawerDialogState extends State<CashDrawerDialog> {
  bool _pin5 = false;
  bool _loadingPin = true;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    DrawerPrefs.usesPin5().then((v) {
      if (!mounted) return;
      setState(() {
        _pin5 = v;
        _loadingPin = false;
      });
    });
  }

  Future<void> _setPin(bool pin5) async {
    setState(() {
      _pin5 = pin5;
      _status = null;
    });
    await DrawerPrefs.setUsesPin5(pin5);
  }

  Future<void> _openNow() async {
    final printer = context.read<AppState>().printerConfig;
    if (printer == null) {
      setState(() => _status = 'Connect a receipt printer first.');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Opening drawer…';
    });
    final ok = await PrintJobs.openDrawer(printer, pin5: _pin5);
    if (!mounted) return;
    setState(() {
      _working = false;
      _status = ok
          ? 'Drawer signal sent — it should pop open.'
          : 'Couldn\'t reach the printer, or nothing happened. Check the '
              'printer is on and the drawer cable is plugged in. If it still '
              'won\'t open, try the other pin below.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPrinter = context.watch<AppState>().printerConfig != null;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.monetization_on_outlined, color: YColor.brandDeep),
        const SizedBox(width: 10),
        Expanded(child: Text('Cash drawer', style: YFont.titleMD())),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!hasPrinter)
              _banner(
                'No receipt printer connected. The drawer opens through the '
                'printer, so connect one first (Settings → Receipt printer).',
                YColor.danger,
              ),
            Text(
              'The drawer is connected to your receipt printer and opens '
              'automatically on cash sales. You can also open it manually '
              'below.',
              style: YFont.caption().copyWith(color: YColor.inkMuted),
            ),
            const SizedBox(height: YSpacing.md),
            Text('CONNECTOR PIN', style: YFont.caption()),
            const SizedBox(height: 6),
            Text(
              'Most drawers use pin 2. Switch to pin 5 only if pin 2 doesn\'t '
              'open your drawer.',
              style: YFont.caption().copyWith(color: YColor.inkMuted),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _loadingPin ? 0.5 : 1,
              child: Row(children: [
                _pinChip('Pin 2', false),
                const SizedBox(width: 8),
                _pinChip('Pin 5', true),
              ]),
            ),
            if (_status != null) ...[
              const SizedBox(height: 14),
              Text(_status!,
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: Text('Close',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton.icon(
          onPressed: _working || !hasPrinter ? null : _openNow,
          icon: _working
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.lock_open_outlined, size: 18),
          label: const Text('Open drawer now'),
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _pinChip(String label, bool pin5) {
    final selected = _pin5 == pin5;
    return GestureDetector(
      onTap: _loadingPin || _working ? null : () => _setPin(pin5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? YColor.brandTint : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? YColor.brand : YColor.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 13,
              color: selected ? YColor.brandDeep : YColor.ink,
            )),
      ),
    );
  }

  Widget _banner(String text, Color tone) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Text(text,
          style:
              YFont.caption().copyWith(color: tone, fontWeight: FontWeight.w600)),
    );
  }
}
