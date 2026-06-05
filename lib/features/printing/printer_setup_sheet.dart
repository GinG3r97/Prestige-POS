import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/printer_config.dart';
import '../widgets/push_toast.dart';
import 'bt_permissions.dart';
import 'bt_printer.dart';
import 'drawer_prefs.dart';
import 'receipt_builder.dart';

/// Opens the Bluetooth printer setup dialog (scan → select → test → save).
Future<void> showPrinterSetup(BuildContext context) {
  return showDialog(
    context: context,
    builder: (_) => const _PrinterSetupDialog(),
  );
}

class _PrinterSetupDialog extends StatefulWidget {
  const _PrinterSetupDialog();

  @override
  State<_PrinterSetupDialog> createState() => _PrinterSetupDialogState();
}

class _PrinterSetupDialogState extends State<_PrinterSetupDialog> {
  bool _btOn = true;
  bool _scanning = false;
  bool _working = false;
  bool _connected = false;
  List<BtDevice> _devices = const [];
  String? _selectedAddress;
  String _selectedName = '';
  int _paperWidth = 58;
  String? _status;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppState>().printerConfig;
    if (existing != null) {
      _selectedAddress = existing.bluetoothId;
      _selectedName = existing.name;
      _paperWidth = existing.paperWidth;
    }
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = null;
    });
    // Android 12+ needs the runtime BLUETOOTH_CONNECT/SCAN permission before
    // paired devices are visible — the plugin checks but never asks. No-op on
    // iOS. If the user declines, the list below stays empty, so hint at it.
    final granted = await BtPermissions.ensure();
    if (!granted && mounted) {
      setState(() {
        _scanning = false;
        _btOn = false;
        _status = 'Bluetooth permission is needed to find printers. '
            'Allow it when prompted, or enable it in Settings → Apps → '
            'Prestige POS → Permissions, then tap rescan.';
      });
      return;
    }
    // The BLE adapter often reports "off" right at launch before it's ready —
    // retry a few times before believing it.
    var on = await BtPrinter.isEnabled();
    for (var i = 0; i < 3 && !on; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      on = await BtPrinter.isEnabled();
    }
    final connected = await BtPrinter.isConnected;
    // Scan regardless — if we find devices, Bluetooth is clearly on.
    final devices = await BtPrinter.scan();
    if (!mounted) return;
    setState(() {
      _connected = connected;
      _btOn = on || devices.isNotEmpty || connected;
      _devices = devices;
      _scanning = false;
    });
  }

  /// Scanned devices, with the saved printer always included at the top — BLE
  /// hides already-connected devices from new scans, so without this your
  /// working printer would vanish from the list.
  List<BtDevice> _displayDevices() {
    final saved = context.read<AppState>().printerConfig;
    final list = <BtDevice>[];
    final savedAddr = saved?.bluetoothId ?? '';
    if (savedAddr.isNotEmpty && !_devices.any((d) => d.address == savedAddr)) {
      list.add(BtDevice(saved!.name, savedAddr));
    }
    list.addAll(_devices);
    return list;
  }

  Future<void> _testPrint() async {
    final addr = _selectedAddress;
    if (addr == null) {
      setState(() => _status = 'Pick a printer first.');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Connecting…';
    });
    final state = context.read<AppState>();
    final tenant = state.tenant;
    if (tenant == null) {
      setState(() {
        _working = false;
        _status = 'No store selected.';
      });
      return;
    }
    final connected = await BtPrinter.connect(addr);
    if (!connected) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = 'Could not connect. Make sure the printer is on and nearby.';
      });
      return;
    }
    final bytes = await ReceiptBuilder.testTicket(
      tenant: tenant,
      printer: _tempConfig(),
    );
    final ok = await BtPrinter.printBytes(addr, bytes);
    if (!mounted) return;
    setState(() {
      _working = false;
      _status = ok
          ? 'Test sent! Check the printer.'
          : 'Connected, but the test didn\'t print. Try again.';
    });
  }

  /// Pops the cash drawer wired to the selected printer (ESC/POS kick). Lets
  /// the owner confirm the printer→drawer cable works before relying on the
  /// automatic open-on-cash-sale behaviour.
  Future<void> _openDrawer() async {
    final addr = _selectedAddress;
    if (addr == null) {
      setState(() => _status = 'Pick a printer first.');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Opening drawer…';
    });
    final connected = await BtPrinter.connect(addr);
    if (!connected) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = 'Could not connect. Make sure the printer is on and nearby.';
      });
      return;
    }
    final ok = await BtPrinter.printBytes(
        addr, ReceiptBuilder.drawerKick(pin5: await DrawerPrefs.usesPin5()));
    if (!mounted) return;
    setState(() {
      _working = false;
      _status = ok
          ? 'Drawer signal sent — it should pop open.'
          : 'Sent, but nothing happened. Check the cable from the printer to '
              'the drawer (and that the drawer uses pin 2).';
    });
  }

  /// A throwaway config matching the current selection — used to build the
  /// test ticket before the printer is saved.
  PrinterConfig _tempConfig() => PrinterConfig(
        id: 'temp',
        name: _selectedName.isEmpty ? 'Printer' : _selectedName,
        role: PrinterRole.receipt,
        transport: PrinterTransport.bluetooth,
        bluetoothId: _selectedAddress,
        paperWidth: _paperWidth,
      );

  Future<void> _save() async {
    final addr = _selectedAddress;
    if (addr == null) {
      setState(() => _status = 'Pick a printer first.');
      return;
    }
    setState(() => _working = true);
    final state = context.read<AppState>();
    final err = await state.saveBluetoothPrinter(
      name: _selectedName.isEmpty ? 'Receipt printer' : _selectedName,
      address: addr,
      paperWidth: _paperWidth,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _working = false;
        _status = err;
      });
      return;
    }
    Navigator.of(context).pop();
    PushToast.show(context,
        title: 'Printer saved',
        subtitle: 'Receipts will print to $_selectedName.',
        leadingIcon: Icons.check_circle_outline);
  }

  Future<void> _forget() async {
    setState(() => _working = true);
    await context.read<AppState>().clearPrinter();
    if (!mounted) return;
    Navigator.of(context).pop();
    PushToast.show(context,
        title: 'Printer removed', leadingIcon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final hasPrinter = context.watch<AppState>().printerConfig != null;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.print_outlined, color: YColor.brandDeep),
        const SizedBox(width: 10),
        Expanded(child: Text('Receipt printer', style: YFont.titleMD())),
        IconButton(
          tooltip: 'Rescan',
          onPressed: _scanning || _working ? null : _scan,
          icon: _scanning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, color: YColor.inkMuted),
        ),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_connected && _selectedAddress != null)
              _banner(
                  'Connected to ${_selectedName.isEmpty ? 'your printer' : _selectedName} ✓',
                  YColor.success)
            else if (!_btOn)
              _banner('Bluetooth is off — turn it on, then tap rescan.',
                  YColor.danger),
            Text('PRINTERS', style: YFont.caption()),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: _displayDevices().isEmpty
                  ? _empty()
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final d in _displayDevices()) _deviceTile(d),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Text('PAPER WIDTH', style: YFont.caption()),
            const SizedBox(height: 6),
            Row(children: [
              _paperChip('58 mm', 58),
              const SizedBox(width: 8),
              _paperChip('80 mm', 80),
            ]),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!,
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ],
        ),
      ),
      actions: [
        if (hasPrinter)
          TextButton(
            onPressed: _working ? null : _forget,
            child: Text('Forget',
                style: YFont.bodyStrong().copyWith(color: YColor.danger)),
          ),
        OutlinedButton(
          onPressed: _working || _selectedAddress == null ? null : _openDrawer,
          style: OutlinedButton.styleFrom(
            foregroundColor: YColor.brand,
            side: const BorderSide(color: YColor.hairline),
          ),
          child: const Text('Open drawer'),
        ),
        OutlinedButton(
          onPressed: _working || _selectedAddress == null ? null : _testPrint,
          style: OutlinedButton.styleFrom(
            foregroundColor: YColor.brand,
            side: const BorderSide(color: YColor.hairline),
          ),
          child: const Text('Test print'),
        ),
        ElevatedButton(
          onPressed: _working || _selectedAddress == null ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: _working
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _deviceTile(BtDevice d) {
    final selected = _selectedAddress == d.address;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedAddress = d.address;
        _selectedName = d.name.isEmpty ? 'Printer' : d.name;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? YColor.brandTint : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? YColor.brand : YColor.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(children: [
          Icon(Icons.bluetooth,
              size: 18,
              color: selected ? YColor.brandDeep : YColor.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(d.name.isEmpty ? d.address : d.name,
                style: YFont.bodyStrong(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          if (selected)
            const Icon(Icons.check_circle, size: 18, color: YColor.brand),
        ]),
      ),
    );
  }

  Widget _paperChip(String label, int width) {
    final selected = _paperWidth == width;
    return GestureDetector(
      onTap: () => setState(() => _paperWidth = width),
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

  Widget _empty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Text(
        _scanning
            ? 'Scanning…'
            : 'No printers found.\nTurn the printer on, make sure it\'s paired in '
                '${Platform.isIOS ? 'iPad' : 'your tablet\'s'} Settings → '
                'Bluetooth, then tap rescan.',
        textAlign: TextAlign.center,
        style: YFont.caption().copyWith(color: YColor.inkMuted),
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
          style: YFont.caption().copyWith(color: tone, fontWeight: FontWeight.w600)),
    );
  }
}
