import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;

/// Owner home page. Pulls a rolling 14-day window of real orders from
/// Supabase on every visit, then derives today's KPIs, the weekly
/// sales bar chart, top sellers, low-stock alerts and a recent-orders
/// strip. No mock data — everything here mirrors what's been written
/// through the tender sheet.
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  List<o.Order> _orders = const [];
  bool _loading = true;
  bool _hadFetchError = false;

  @override
  void initState() {
    super.initState();
    // Defer the first fetch so AppState's tenant hydration has a
    // chance to settle before we ask for orders. Without the delay,
    // the very-first dashboard paint after sign-in can see a stale
    // null tenant_id and return an empty list.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final state = context.read<AppState>();
    setState(() => _loading = true);
    final since = DateTime.now()
        .subtract(const Duration(days: 14))
        .toUtc();
    try {
      final orders = await state.fetchOrders(since: since, limit: 500);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _hadFetchError = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hadFetchError = true;
        _loading = false;
      });
    }
  }

  bool _isToday(DateTime dt) {
    final n = DateTime.now();
    final d = dt.toLocal();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isYesterday(DateTime dt) {
    final y = DateTime.now().subtract(const Duration(days: 1));
    final d = dt.toLocal();
    return d.year == y.year && d.month == y.month && d.day == y.day;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final paid = _orders.where((ord) => ord.status == o.OrderStatus.paid);
    final todayOrders =
        paid.where((ord) => _isToday(ord.createdAt)).toList();
    final yesterdayOrders =
        paid.where((ord) => _isYesterday(ord.createdAt)).toList();

    final todayRevenueCents =
        todayOrders.fold<int>(0, (a, ord) => a + ord.totalCents);
    final yesterdayRevenueCents =
        yesterdayOrders.fold<int>(0, (a, ord) => a + ord.totalCents);
    final delta = yesterdayRevenueCents == 0
        ? null
        : (todayRevenueCents - yesterdayRevenueCents) /
            yesterdayRevenueCents *
            100;

    final todayItemCount = todayOrders.fold<int>(
        0, (a, ord) => a + ord.lines.fold(0, (b, l) => b + l.quantity));
    final avgTicketCents = todayOrders.isEmpty
        ? 0
        : todayRevenueCents ~/ todayOrders.length;
    final lowStock = state.inventory.where((i) => i.isLowStock).toList();

    final recentOrders = _orders
        .where((ord) => ord.status != o.OrderStatus.cancelled)
        .take(6)
        .toList();

    return Container(
      color: YColor.surface2,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: YColor.brand,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(state),
                  if (_hadFetchError) ...[
                    const SizedBox(height: 14),
                    _errorBanner(),
                  ],
                  const SizedBox(height: 22),
                  Row(children: [
                    Expanded(
                      child: _KpiTile(
                        icon: Icons.payments_rounded,
                        label: "Today's revenue",
                        value: Money(todayRevenueCents).formatted,
                        delta: delta,
                        tone: YColor.brand,
                        loading: _loading,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiTile(
                        icon: Icons.receipt_long_rounded,
                        label: 'Orders',
                        value: todayOrders.length.toString(),
                        delta: yesterdayOrders.isEmpty
                            ? null
                            : (todayOrders.length - yesterdayOrders.length) /
                                yesterdayOrders.length *
                                100,
                        tone: YColor.brandDeep,
                        loading: _loading,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiTile(
                        icon: Icons.local_mall_rounded,
                        label: 'Items sold',
                        value: todayItemCount.toString(),
                        tone: YColor.brand,
                        loading: _loading,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KpiTile(
                        icon: Icons.local_cafe_rounded,
                        label: 'Avg ticket',
                        value: Money(avgTicketCents).formatted,
                        tone: YColor.brandDeep,
                        loading: _loading,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _SalesChart(orders: paid.toList()),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _TopSellers(orders: todayOrders),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: _LowStockCard(items: lowStock),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: _RecentOrders(orders: recentOrders),
                      ),
                    ],
                  ),
                  // Reserve room for the floating nav so the last row
                  // isn't tucked underneath the pill.
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppState state) {
    final tenant = state.tenant;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting, ${state.currentOwner?.displayName.split(' ').first ?? ''}',
                style: YFont.titleLG().copyWith(
                  fontSize: 30,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tenant?.businessName.isNotEmpty == true
                    ? "Here's how ${tenant!.businessName} is doing today."
                    : "Here's how your store is doing today.",
                style: YFont.body().copyWith(color: YColor.inkMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Live data pill — a small reassurance that what's on screen
        // is the real database, not a demo. Spins while loading.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: YColor.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(YColor.brand),
                ),
              )
            else
              const _LiveDot(),
            const SizedBox(width: 8),
            Text(
              _loading ? 'Refreshing…' : 'Live',
              style: YFont.caption().copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: YColor.inkMuted,
              ),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        // Refresh — styled as a pill to match the Live indicator beside it.
        GestureDetector(
          onTap: _loading ? null : _refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: YColor.surface1,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: YColor.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded,
                  size: 14,
                  color: _loading ? YColor.inkSubtle : YColor.inkMuted),
              const SizedBox(width: 6),
              Text(
                'Refresh',
                style: YFont.caption().copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: _loading ? YColor.inkSubtle : YColor.inkMuted,
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: YColor.dangerSoft,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.danger.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined,
            color: YColor.danger, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not reach the server. Showing whatever loaded last '
            '— pull down to retry.',
            style: YFont.caption().copyWith(color: YColor.danger),
          ),
        ),
        TextButton(
          onPressed: _refresh,
          child: const Text('Retry'),
        ),
      ]),
    );
  }
}

/// Small breathing dot used in the "Live" pill to signal real-time
/// state without being too loud.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: YColor.success
              .withValues(alpha: 0.4 + 0.6 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ───── KPI tile ─────

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    this.delta,
    this.loading = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color tone;
  final double? delta;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isUp = delta != null && delta! >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const Spacer(),
            if (delta != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isUp ? YColor.success : YColor.danger)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    size: 14,
                    color: isUp ? YColor.success : YColor.danger,
                  ),
                  Text(
                    '${delta!.abs().toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isUp ? YColor.success : YColor.danger,
                    ),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: loading
                ? Container(
                    key: const ValueKey('skel'),
                    width: 90,
                    height: 26,
                    decoration: BoxDecoration(
                      color: YColor.surface3.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                : Text(
                    value,
                    key: ValueKey(value),
                    style: YFont.titleLG().copyWith(
                      fontSize: 26,
                      letterSpacing: -0.6,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(height: 2),
          Text(label, style: YFont.caption()),
        ],
      ),
    );
  }
}

// ───── Sales chart ─────

class _SalesChart extends StatelessWidget {
  const _SalesChart({required this.orders});
  final List<o.Order> orders;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day - (6 - i));
      final total = orders.fold<int>(0, (acc, ord) {
        final od = ord.createdAt.toLocal();
        return od.year == d.year &&
                od.month == d.month &&
                od.day == d.day
            ? acc + ord.totalCents
            : acc;
      });
      return (date: d, totalCents: total);
    });
    final maxValue = days.fold<double>(
        0, (a, b) => b.totalCents / 100 > a ? b.totalCents / 100 : a);
    final yMax = ((maxValue / 1000).ceil() * 1000).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sales this week',
                      style: YFont.titleMD().copyWith(fontSize: 16)),
                  Text('Last 7 days, peso', style: YFont.caption()),
                ],
              ),
            ),
            _legendDot('Today', color: YColor.brand, filled: true),
            const SizedBox(width: 10),
            _legendDot('Earlier',
                color: YColor.brandDeep.withValues(alpha: 0.5)),
          ]),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: yMax == 0 ? 1000 : yMax * 1.1,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yMax == 0 ? 250 : yMax / 4,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: YColor.hairline.withValues(alpha: 0.6),
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= days.length) {
                          return const SizedBox.shrink();
                        }
                        final d = days[i].date;
                        const dayNames = [
                          'Mon', 'Tue', 'Wed', 'Thu',
                          'Fri', 'Sat', 'Sun',
                        ];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            dayNames[d.weekday - 1],
                            style: YFont.caption().copyWith(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 44,
                      interval: yMax == 0 ? 250 : yMax / 4,
                      getTitlesWidget: (v, _) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          '₱${v.toInt()}',
                          style: YFont.caption().copyWith(fontSize: 10),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < days.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: days[i].totalCents / 100,
                          color: i == days.length - 1
                              ? YColor.brand
                              : YColor.brandDeep.withValues(alpha: 0.5),
                          width: 22,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label,
      {required Color color, bool filled = false}) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(label, style: YFont.caption().copyWith(fontSize: 11)),
    ]);
  }
}

// ───── Top sellers card ─────

class _TopSellers extends StatelessWidget {
  const _TopSellers({required this.orders});
  final List<o.Order> orders;

  @override
  Widget build(BuildContext context) {
    final agg = <String, ({int qty, int revenueCents})>{};
    for (final ord in orders) {
      for (final l in ord.lines) {
        final prev = agg[l.name];
        final qty = (prev?.qty ?? 0) + l.quantity;
        final rev = (prev?.revenueCents ?? 0) + l.lineTotalCents;
        agg[l.name] = (qty: qty, revenueCents: rev);
      }
    }
    final sorted = agg.entries.toList()
      ..sort((a, b) => b.value.qty.compareTo(a.value.qty));
    final top = sorted.take(5).toList();
    final maxQty = top.isEmpty ? 1 : top.first.value.qty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top sellers today',
              style: YFont.titleMD().copyWith(fontSize: 16)),
          Text('Best-moving items', style: YFont.caption()),
          const SizedBox(height: 14),
          if (top.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No sales yet today.', style: YFont.caption()),
            )
          else
            for (final e in top) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.bodyStrong()),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: e.value.qty / maxQty,
                            minHeight: 5,
                            backgroundColor: YColor.surface3,
                            valueColor:
                                AlwaysStoppedAnimation(YColor.brand),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${e.value.qty}',
                            style: YFont.bodyStrong()),
                        Text(Money(e.value.revenueCents).formatted,
                            style: YFont.caption()),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
        ],
      ),
    );
  }
}

// ───── Low stock card ─────

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.items});
  final List<InventoryItem> items;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(5).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Text('Low stock alerts',
                style: YFont.titleMD().copyWith(fontSize: 16)),
            const Spacer(),
            if (items.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.orange,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                const Icon(Icons.check_circle,
                    color: YColor.success, size: 16),
                const SizedBox(width: 8),
                Text('All stock levels healthy.', style: YFont.caption()),
              ]),
            )
          else
            for (final it in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: it.isOutOfStock
                          ? YColor.danger
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.name,
                            style: YFont.bodyStrong()
                                .copyWith(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          '${it.currentStock.toStringAsFixed(0)}${it.displayUnit} left · reorder at ${it.lowStockThreshold.toStringAsFixed(0)}${it.displayUnit}',
                          style: YFont.caption(),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
        ],
      ),
    );
  }
}

// ───── Recent orders card ─────

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders});
  final List<o.Order> orders;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Row(children: [
              Text('Recent orders',
                  style: YFont.titleMD().copyWith(fontSize: 16)),
              const Spacer(),
              TextButton(
                onPressed: () => context
                    .read<AppState>()
                    .selectRoute(AppRoute.orders),
                style: TextButton.styleFrom(
                  foregroundColor: YColor.brand,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                child: const Text('View all →'),
              ),
            ]),
          ),
          Container(
            height: 0.5,
            color: YColor.hairline,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          if (orders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
              child: Center(
                child: Column(children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: YColor.inkMuted, size: 28),
                  const SizedBox(height: 8),
                  Text('No orders yet.',
                      style: YFont.bodyStrong()),
                  const SizedBox(height: 2),
                  Text(
                    'Ring one up from the Sell page — it\'ll show up here.',
                    style: YFont.caption(),
                  ),
                ]),
              ),
            )
          else
            for (var i = 0; i < orders.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: YColor.brandTint.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _initial(orders[i].cashierName),
                      style: YFont.bodyStrong().copyWith(
                        fontSize: 14,
                        color: YColor.brandDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(_orderTag(orders[i]),
                              style: YFont.bodyStrong()
                                  .copyWith(fontSize: 13)),
                          const SizedBox(width: 6),
                          if (orders[i].status == o.OrderStatus.refunded)
                            _pill('REFUNDED', YColor.danger)
                          else if (orders[i].status ==
                              o.OrderStatus.voided)
                            _pill('VOID', YColor.inkMuted),
                        ]),
                        Text(
                          '${_itemCount(orders[i])} items · '
                          '${_methodLabel(orders[i])} · '
                          '${_fmtTime(orders[i].createdAt.toLocal())}',
                          style: YFont.caption(),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Money(orders[i].totalCents).formatted,
                    style: YFont.bodyStrong().copyWith(color: YColor.brand),
                  ),
                ]),
              ),
              if (i != orders.length - 1)
                Container(
                  height: 0.5,
                  color: YColor.hairline,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
            ],
        ],
      ),
    );
  }

  String _initial(String? name) {
    if (name == null || name.trim().isEmpty) return '·';
    return name.trim()[0].toUpperCase();
  }

  /// Sequential order number for the badge — `#000123`. Falls back to
  /// last 6 of the UUID when the order is brand new and the number
  /// hasn't been stamped yet.
  String _orderTag(o.Order ord) {
    if (ord.orderNumber > 0) {
      return '#${ord.orderNumber.toString().padLeft(6, '0')}';
    }
    final id = ord.id.replaceAll('-', '');
    return '#${id.substring(id.length - 6).toUpperCase()}';
  }

  int _itemCount(o.Order ord) =>
      ord.lines.fold(0, (a, l) => a + l.quantity);

  String _methodLabel(o.Order ord) {
    if (ord.payments.isEmpty) return 'Unpaid';
    if (ord.payments.length == 1) return ord.payments.first.method.label;
    return 'Split';
  }

  Widget _pill(String text, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: tone,
        ),
      ),
    );
  }

  String _fmtTime(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $period';
  }
}
