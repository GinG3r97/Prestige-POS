import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../widgets/push_toast.dart';

/// Open customer tabs — unpaid orders grouped by customer, settled later.
/// Populated when a cashier chooses "Pay later" at checkout.
class TabsView extends StatefulWidget {
  const TabsView({super.key});

  @override
  State<TabsView> createState() => _TabsViewState();
}

class _Tab {
  _Tab(this.name, this.orders);
  final String name;
  final List<o.Order> orders;
  int get totalCents => orders.fold(0, (a, x) => a + x.totalCents);
  int get itemCount =>
      orders.fold(0, (a, x) => a + x.lines.fold<int>(0, (b, l) => b + l.quantity));
  List<String> get orderIds => orders.map((x) => x.id).toList();
}

class _TabsViewState extends State<TabsView> {
  bool _loading = true;
  bool _busy = false;
  List<_Tab> _tabs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final orders = await context.read<AppState>().fetchOpenOrders();
    final map = <String, List<o.Order>>{};
    for (final ord in orders) {
      final key = (ord.customerName?.trim().isNotEmpty ?? false)
          ? ord.customerName!.trim()
          : 'Walk-in';
      (map[key] ??= []).add(ord);
    }
    final tabs = map.entries.map((e) => _Tab(e.key, e.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _tabs = tabs;
      _loading = false;
    });
  }

  Future<void> _settle(_Tab tab) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: YColor.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettleSheet(tab: tab),
    );
    if (method == null || !mounted) return;
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final err = await state.settleTab(tab.orderIds, method);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      PushToast.show(context,
          title: 'Could not settle',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: '${tab.name}’s tab settled',
        subtitle: '${Money(tab.totalCents).formatted} · ${_methodLabel(method)}',
        leadingIcon: Icons.check_circle_outline);
    await state.refreshOrders();
    _load();
  }

  static String _methodLabel(String m) => switch (m) {
        'cash' => 'Cash',
        'gcash' => 'GCash',
        'qrph' => 'QR Ph',
        'bank_transfer' => 'Bank',
        _ => m,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          _header(),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tabs.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _tabs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _tabCard(_tabs[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final grand = _tabs.fold<int>(0, (a, t) => a + t.totalCents);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      color: YColor.surface1,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tabs', style: YFont.titleLG().copyWith(fontSize: 24)),
              Text('Unpaid orders · settle when the customer pays',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ),
          const Spacer(),
          if (_tabs.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Outstanding',
                    style: YFont.caption().copyWith(color: YColor.inkMuted)),
                Text(Money(grand).formatted,
                    style: YFont.titleMD().copyWith(color: YColor.brandDeep)),
              ],
            ),
          const SizedBox(width: 8),
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 44, color: YColor.inkSubtle),
              const SizedBox(height: 12),
              Text('No open tabs', style: YFont.titleMD()),
              const SizedBox(height: 4),
              Text(
                'When a customer says “pay later” at checkout, their order lands here.',
                textAlign: TextAlign.center,
                style: YFont.caption().copyWith(color: YColor.inkMuted),
              ),
            ],
          ),
        ),
      );

  Widget _tabCard(_Tab tab) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(tab.name, style: YFont.titleMD().copyWith(fontSize: 16)),
          subtitle: Text(
              '${tab.orders.length} order${tab.orders.length == 1 ? '' : 's'} · ${tab.itemCount} items',
              style: YFont.caption()),
          trailing: Text(Money(tab.totalCents).formatted,
              style: YFont.titleMD().copyWith(color: YColor.brandDeep)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final ord in tab.orders) _orderBlock(ord),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : () => _settle(tab),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Settle ${Money(tab.totalCents).formatted}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderBlock(o.Order ord) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('#${ord.orderNumber}',
                  style: YFont.caption().copyWith(
                      color: YColor.brandDeep, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(_time(ord.createdAt),
                  style: YFont.caption().copyWith(color: YColor.inkSubtle)),
              const Spacer(),
              Text(Money(ord.totalCents).formatted,
                  style: YFont.caption().copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          for (final l in ord.lines)
            Padding(
              padding: const EdgeInsets.only(left: 2, top: 2),
              child: Text('${l.quantity}× ${l.name}',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ),
        ],
      ),
    );
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ap = l.hour < 12 ? 'AM' : 'PM';
    return '$h:${l.minute.toString().padLeft(2, '0')} $ap';
  }
}

class _SettleSheet extends StatelessWidget {
  const _SettleSheet({required this.tab});
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final methods = <(String, String, IconData)>[
      ('cash', 'Cash', Icons.payments_outlined),
      ('gcash', 'GCash', Icons.account_balance_wallet_outlined),
      ('qrph', 'QR Ph', Icons.qr_code_2),
      ('bank_transfer', 'Bank transfer', Icons.account_balance_outlined),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settle ${tab.name}’s tab',
                style: YFont.titleMD().copyWith(fontSize: 18)),
            const SizedBox(height: 4),
            Text('${Money(tab.totalCents).formatted} · how did they pay?',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 16),
            for (final m in methods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, m.$1),
                  icon: Icon(m.$3, size: 18),
                  label: Align(
                      alignment: Alignment.centerLeft, child: Text(m.$2)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: YColor.ink,
                    side: const BorderSide(color: YColor.hairline),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
