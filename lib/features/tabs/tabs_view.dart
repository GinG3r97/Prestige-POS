import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../widgets/push_toast.dart';

/// Pay Later — unpaid orders grouped by customer, settled when they pay.
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
  DateTime get oldest => orders
      .map((x) => x.createdAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
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
      // Oldest tab first — the customer who's been waiting longest to settle.
      ..sort((a, b) => a.oldest.compareTo(b.oldest));
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
          if (_busy)
            const LinearProgressIndicator(
                minHeight: 2, color: YColor.brand, backgroundColor: YColor.brandTint)
          else
            Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tabs.isEmpty
                    ? _empty()
                    : RefreshIndicator(
                        color: YColor.brandDeep,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(YSpacing.md),
                          itemCount: _tabs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: YSpacing.sm),
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
    final orderCount = _tabs.fold<int>(0, (a, t) => a + t.orders.length);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      color: YColor.surface1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pay Later', style: YFont.titleLG().copyWith(fontSize: 24)),
                  Text('Unpaid orders · settle when the customer pays',
                      style: YFont.caption().copyWith(color: YColor.inkMuted)),
                ],
              ),
              const Spacer(),
              IconButton(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh)),
            ],
          ),
          if (!_loading && _tabs.isNotEmpty) ...[
            const SizedBox(height: YSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(YRadius.md),
                border: Border.all(color: YColor.brandSoft),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                        color: YColor.brandSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.schedule_outlined,
                        size: 19, color: YColor.brandDeep),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Outstanding',
                          style: YFont.caption().copyWith(color: YColor.brandDeep)),
                      Text(Money(grand).formatted,
                          style: YFont.priceLG().copyWith(color: YColor.brandDeep)),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${_tabs.length} customer${_tabs.length == 1 ? '' : 's'} · '
                    '$orderCount order${orderCount == 1 ? '' : 's'}',
                    style: YFont.caption().copyWith(color: YColor.brandDeep),
                  ),
                ],
              ),
            ),
          ],
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
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                    color: YColor.brandTint, shape: BoxShape.circle),
                child: const Icon(Icons.schedule_outlined,
                    size: 32, color: YColor.brandDeep),
              ),
              const SizedBox(height: YSpacing.md),
              Text('No pay-later tabs', style: YFont.titleMD()),
              const SizedBox(height: YSpacing.xxs),
              SizedBox(
                width: 300,
                child: Text(
                  'When a customer says “pay later” at checkout, their order lands here until they settle.',
                  textAlign: TextAlign.center,
                  style: YFont.caption().copyWith(color: YColor.inkMuted),
                ),
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
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: _avatar(tab.name),
          title: Text(tab.name,
              style: YFont.bodyStrong().copyWith(fontSize: 16)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${tab.orders.length} order${tab.orders.length == 1 ? '' : 's'} · '
              '${tab.itemCount} item${tab.itemCount == 1 ? '' : 's'}',
              style: YFont.caption(),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Money(tab.totalCents).formatted,
                  style: YFont.price().copyWith(color: YColor.brandDeep)),
              const SizedBox(height: 2),
              Text(_ago(tab.oldest),
                  style: YFont.caption()
                      .copyWith(fontSize: 11, color: YColor.inkSubtle)),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < tab.orders.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Container(height: 0.5, color: YColor.hairline),
                      ),
                    _orderBlock(tab.orders[i]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: YSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => context.read<AppState>().startTabOrder(tab.name),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add order'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: YColor.brandDeep,
                      side: const BorderSide(color: YColor.brandSoft),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _settle(tab),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text('Settle ${Money(tab.totalCents).formatted}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brandDeep,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    var initials = parts.take(2).map((p) => p[0].toUpperCase()).join();
    if (initials.isEmpty) initials = '?';
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
          color: YColor.brandTint, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(initials,
          style: YFont.bodyStrong().copyWith(color: YColor.brandDeep)),
    );
  }

  Widget _orderBlock(o.Order ord) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(YRadius.pill),
              ),
              child: Text('#${ord.orderNumber}',
                  style: YFont.caption().copyWith(
                      fontSize: 11,
                      color: YColor.brandDeep,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(_time(ord.createdAt),
                style: YFont.caption().copyWith(color: YColor.inkSubtle)),
            const Spacer(),
            Text(Money(ord.totalCents).formatted, style: YFont.bodyStrong()),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in ord.lines)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text('${l.quantity}×',
                      style: YFont.caption()
                          .copyWith(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(
                    l.emoji.isNotEmpty ? '${l.emoji} ${l.name}' : l.name,
                    style: YFont.caption().copyWith(color: YColor.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(Money(l.lineTotalCents).formatted,
                    style: YFont.caption().copyWith(color: YColor.inkSubtle)),
              ],
            ),
          ),
      ],
    );
  }

  String _time(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final ap = l.hour < 12 ? 'AM' : 'PM';
    return '$h:${l.minute.toString().padLeft(2, '0')} $ap';
  }

  /// Relative age of the tab's oldest order: "just now", "12m", "3h", "2d".
  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _SettleSheet extends StatelessWidget {
  const _SettleSheet({required this.tab});
  final _Tab tab;

  static const _methods = <(String, String, IconData)>[
    ('cash', 'Cash', Icons.payments_outlined),
    ('gcash', 'GCash', Icons.account_balance_wallet_outlined),
    ('qrph', 'QR Ph', Icons.qr_code_2),
    ('bank_transfer', 'Bank transfer', Icons.account_balance_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: YColor.surface4,
                      borderRadius: BorderRadius.circular(YRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: YSpacing.md),
                Text('Settle ${tab.name}’s tab',
                    textAlign: TextAlign.center, style: YFont.titleMD()),
                const SizedBox(height: 2),
                Text(
                  '${tab.orders.length} order${tab.orders.length == 1 ? '' : 's'} · '
                  '${tab.itemCount} item${tab.itemCount == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: YFont.caption(),
                ),
                const SizedBox(height: YSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: YColor.brandTint,
                    borderRadius: BorderRadius.circular(YRadius.md),
                  ),
                  child: Column(
                    children: [
                      Text('Total to collect',
                          style:
                              YFont.caption().copyWith(color: YColor.brandDeep)),
                      Text(Money(tab.totalCents).formatted,
                          style: YFont.titleXL()
                              .copyWith(color: YColor.brandDeep, fontSize: 28)),
                    ],
                  ),
                ),
                const SizedBox(height: YSpacing.md),
                Text('How did they pay?', style: YFont.bodyStrong()),
                const SizedBox(height: YSpacing.xs),
                for (var i = 0; i < _methods.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _methodTile(context, _methods[i])),
                      const SizedBox(width: 10),
                      Expanded(child: _methodTile(context, _methods[i + 1])),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodTile(BuildContext context, (String, String, IconData) m) {
    return Material(
      color: YColor.surface1,
      borderRadius: BorderRadius.circular(YRadius.md),
      child: InkWell(
        onTap: () => Navigator.pop(context, m.$1),
        borderRadius: BorderRadius.circular(YRadius.md),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border.all(color: YColor.hairline),
            borderRadius: BorderRadius.circular(YRadius.md),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                    color: YColor.brandTint, shape: BoxShape.circle),
                child: Icon(m.$3, size: 17, color: YColor.brandDeep),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(m.$2,
                    style: YFont.bodyStrong(), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
