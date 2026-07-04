import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/cart.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../printing/print_jobs.dart';
import '../printing/receipt_builder.dart';
import '../widgets/push_toast.dart';

/// Add-to-pay-later flow.
///
/// When the cashier is building an order for an existing pay-later customer,
/// they don't choose a payment method — the order is just fired (unpaid) onto
/// that customer's tab. This sheet does that fire and then shows the
/// barista/kitchen ticket print buttons, so the cashier can print the prep
/// tickets before returning to the Pay Later page.
Future<void> showPayLaterAddSheet(BuildContext context) {
  final state = context.read<AppState>();
  if (state.activeTabName == null || state.cart.lines.isEmpty) {
    return Future.value();
  }
  // Stock guard up-front so we don't open the sheet on an impossible order.
  final stockError = state.validateCartStock();
  if (stockError != null) {
    PushToast.show(context,
        title: 'Not enough stock',
        subtitle: stockError,
        leadingIcon: Icons.inventory_2_outlined);
    return Future.value();
  }
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ChangeNotifierProvider.value(
      value: state,
      child: const _PayLaterAddSheet(),
    ),
  );
}

String _newRequestId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

Map<String, dynamic>? _modifiersSnapshot(CartLine line) {
  if (line.kind case CartLineCafe(
    :final item,
    :final selections,
    :final addOns,
    :final note
  )) {
    final mods = <String, String>{};
    for (final g in item.modifierGroups) {
      final optId = selections[g.id];
      if (optId == null) continue;
      final opt = g.options.where((o) => o.id == optId).firstOrNull;
      if (opt != null) mods[g.name] = opt.name;
    }
    final addOnList = addOns
        .where((a) => a.quantity > 0)
        .map((a) => {'name': a.addOn.name, 'quantity': a.quantity})
        .toList();
    final trimmedNote = note?.trim() ?? '';
    if (mods.isEmpty && addOnList.isEmpty && trimmedNote.isEmpty) return null;
    return {
      if (mods.isNotEmpty) 'options': mods,
      if (addOnList.isNotEmpty) 'add_ons': addOnList,
      if (trimmedNote.isNotEmpty) 'note': trimmedNote,
    };
  }
  return null;
}

class _PayLaterAddSheet extends StatefulWidget {
  const _PayLaterAddSheet();

  @override
  State<_PayLaterAddSheet> createState() => _PayLaterAddSheetState();
}

class _PayLaterAddSheetState extends State<_PayLaterAddSheet> {
  bool _firing = true;
  String? _error;
  o.Order? _order;
  String _name = '';

  String? _requestId;
  bool _printBusy = false;
  bool _baristaPrinted = false;
  bool _kitchenPrinted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fire());
  }

  Future<void> _fire() async {
    final state = context.read<AppState>();
    _name = state.activeTabName ?? '';
    final cart = state.cart;
    _requestId ??= _newRequestId();

    final lines = cart.lines.map((line) {
      String? categoryName;
      if (line.kind case CartLineCafe(:final item)) {
        categoryName = item.categoryName.isNotEmpty
            ? item.categoryName
            : item.category.title;
      }
      return (
        sellableId: null as String?,
        name: line.title,
        categoryName: categoryName,
        emoji: line.emoji,
        unitPriceCents: line.unitPrice.centavos,
        quantity: line.quantity,
        lineTotalCents: line.lineTotal.centavos,
        modifiers: _modifiersSnapshot(line),
        recipeDeductions: state.recipeDeductionsForCartLine(line),
      );
    }).toList();

    // Empty payments + unpaid → the DB records an OPEN order onto this tab.
    final result = await state.createPaidOrder(
      lines: lines,
      payments: const [],
      customerName: _name.trim(),
      clientRequestId: _requestId,
      unpaid: true,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _firing = false;
        _error = result.error;
      });
      return;
    }
    _requestId = null;
    state.deductCartFromInventory();

    o.Order? order;
    try {
      await state.refreshOrders();
      final fresh = state.recentOrders.where((x) => x.id == result.id);
      if (fresh.isNotEmpty) order = fresh.first;
    } catch (_) {/* best-effort */}

    if (!mounted) return;
    setState(() {
      _firing = false;
      _order = order;
    });
  }

  Future<void> _print(bool barista) async {
    if (_printBusy) return;
    final state = context.read<AppState>();
    final order = _order;
    final printer = state.printerConfig;
    final tenant = state.tenant;
    if (order == null || printer == null || tenant == null) {
      PushToast.show(context,
          title: 'No printer connected',
          subtitle: 'Pair a printer in Settings to print tickets.',
          leadingIcon: Icons.print_disabled_outlined);
      return;
    }
    setState(() => _printBusy = true);
    final ok = barista
        ? await PrintJobs.barista(order: order, tenant: tenant, config: printer)
        : await PrintJobs.kitchen(order: order, tenant: tenant, config: printer);
    if (!mounted) return;
    setState(() {
      _printBusy = false;
      if (ok && barista) _baristaPrinted = true;
      if (ok && !barista) _kitchenPrinted = true;
    });
    PushToast.show(context,
        title: ok
            ? '${barista ? 'Barista' : 'Kitchen'} ticket printed'
            : 'Ticket didn\'t print',
        subtitle: ok ? null : 'Check the printer is on and nearby.',
        leadingIcon:
            ok ? Icons.check_circle_outline : Icons.print_disabled_outlined);
  }

  void _done() {
    final state = context.read<AppState>();
    state.cart.clear();
    state.clearActiveTab();
    state.selectRoute(AppRoute.tabs);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(YRadius.lg)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _firing
              ? _firingBody()
              : _error != null
                  ? _errorBody()
                  : _doneBody(),
        ),
      ),
    );
  }

  Widget _firingBody() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const CircularProgressIndicator(color: YColor.brandDeep),
          const SizedBox(height: 18),
          Text('Saving order…', style: YFont.titleMD()),
          const SizedBox(height: 4),
          Text('Adding to ${context.read<AppState>().activeTabName ?? ''}',
              style: YFont.caption().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 8),
        ],
      );

  Widget _errorBody() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: YColor.danger),
          const SizedBox(height: 12),
          Text('Could not save order', style: YFont.titleMD()),
          const SizedBox(height: 6),
          Text(_error ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: YFont.caption().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: YColor.brandDeep,
                side: const BorderSide(color: YColor.hairline),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Close'),
            ),
          ),
        ],
      );

  Widget _doneBody() {
    final order = _order;
    final hasDrinks = order != null && ReceiptBuilder.hasDrinks(order);
    final hasFood = order != null && ReceiptBuilder.hasFood(order);
    final total = order == null ? null : Money(order.totalCents);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration:
              const BoxDecoration(color: YColor.brandTint, shape: BoxShape.circle),
          child: const Icon(Icons.schedule_outlined,
              size: 28, color: YColor.brandDeep),
        ).paddedCenter(),
        const SizedBox(height: 14),
        Text('Order added for $_name',
            textAlign: TextAlign.center, style: YFont.titleMD()),
        const SizedBox(height: 4),
        Text(
          order?.orderNumber != null
              ? 'Order #${order!.orderNumber.toString().padLeft(4, '0')}'
                  '${total != null ? ' · ${total.formatted}' : ''}'
              : 'Saved to the Pay Later page',
          textAlign: TextAlign.center,
          style: YFont.caption().copyWith(color: YColor.inkMuted),
        ),
        const SizedBox(height: 18),
        if (hasDrinks || hasFood) ...[
          Text('Print prep tickets',
              style: YFont.caption()
                  .copyWith(color: YColor.brandDeep, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_printBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: YColor.brandDeep)),
              ),
            )
          else
            Row(
              children: [
                if (hasDrinks)
                  Expanded(
                    child: _printBtn(
                        _baristaPrinted ? 'Barista ✓' : 'Print barista',
                        Icons.local_cafe_outlined,
                        _baristaPrinted,
                        () => _print(true)),
                  ),
                if (hasDrinks && hasFood) const SizedBox(width: 10),
                if (hasFood)
                  Expanded(
                    child: _printBtn(
                        _kitchenPrinted ? 'Kitchen ✓' : 'Print kitchen',
                        Icons.restaurant_outlined,
                        _kitchenPrinted,
                        () => _print(false)),
                  ),
              ],
            ),
          const SizedBox(height: 16),
        ],
        ElevatedButton(
          onPressed: _printBusy ? null : _done,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brandDeep,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YRadius.md)),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _printBtn(
      String label, IconData icon, bool done, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: done ? YColor.success : YColor.brandDeep,
        side: BorderSide(color: done ? YColor.success : YColor.hairline),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.md)),
      ),
    );
  }
}

extension on Widget {
  Widget paddedCenter() => Align(alignment: Alignment.center, child: this);
}
