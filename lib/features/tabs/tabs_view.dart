import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../tender/tender_sheet.dart';

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

  /// Settle → load this customer's unpaid orders and open the payment modal
  /// right here on the Pay Later page. The orders stay open (still listed)
  /// until the payment actually completes.
  Future<void> _settle(_Tab tab) async {
    final state = context.read<AppState>();
    state.startSettleTab(tab.name, tab.orders);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (_) => const TenderSheet(),
    );
    if (!mounted) return;
    // Dropped out without paying → clear the settle session (orders stay
    // open). If they DID pay, completeSettle already reset it — this no-ops.
    state.clearSettle();
    _load();
  }

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
                ? const Center(
                    child: CircularProgressIndicator(color: YColor.brandDeep))
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
              // Themed action button — matches the outlined chip style used
              // on Orders/Sell instead of a bare Material IconButton.
              Material(
                color: YColor.surface1,
                borderRadius: BorderRadius.circular(YRadius.md),
                child: InkWell(
                  onTap: _loading ? null : _load,
                  borderRadius: BorderRadius.circular(YRadius.md),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: YColor.hairline),
                      borderRadius: BorderRadius.circular(YRadius.md),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        size: 20, color: YColor.brandDeep),
                  ),
                ),
              ),
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
              Text('No unpaid orders', style: YFont.titleMD()),
              const SizedBox(height: YSpacing.xxs),
              SizedBox(
                width: 300,
                child: Text(
                  'When a customer pays later at checkout, their orders show here until settled.',
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
          iconColor: YColor.brandDeep,
          collapsedIconColor: YColor.inkSubtle,
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

