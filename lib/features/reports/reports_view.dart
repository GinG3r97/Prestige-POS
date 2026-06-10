import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';
import '../../models/inventory.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../../models/payroll.dart';
import '../widgets/push_toast.dart';

/// What slice of the data the owner wants to focus on. Each lens
/// hides irrelevant sections and skips fetches that aren't relevant
/// to the chosen perspective.
enum _ReportLens {
  all,
  sales,
  products,
  inventory,
  payroll,
  staff,
  attendance,
}

extension on _ReportLens {
  String get label => switch (this) {
        _ReportLens.all => 'All',
        _ReportLens.sales => 'Sales',
        _ReportLens.products => 'Products',
        _ReportLens.inventory => 'Inventory',
        _ReportLens.payroll => 'Payroll',
        _ReportLens.staff => 'Staff',
        _ReportLens.attendance => 'Attendance',
      };

  // Match the canonical app icons (see More / nav).
  IconData get icon => switch (this) {
        _ReportLens.all => Icons.space_dashboard_outlined,
        _ReportLens.sales => Icons.insights_outlined,
        _ReportLens.products => Icons.coffee_outlined,
        _ReportLens.inventory => Icons.inventory_2_outlined,
        _ReportLens.payroll => Icons.account_balance_wallet_outlined,
        _ReportLens.staff => Icons.person_outline,
        _ReportLens.attendance => Icons.event_available_outlined,
      };

  /// Sales / Products / All read from the `orders` table for the
  /// chosen date range. Inventory / Payroll / Staff are point-in-
  /// time (or read pre-hydrated AppState caches), so they hide the
  /// range chips so the controls match what's on screen.
  /// Attendance uses the date range to scope its time entries.
  bool get usesDateRange => this == _ReportLens.all ||
      this == _ReportLens.sales ||
      this == _ReportLens.products ||
      this == _ReportLens.attendance;

  /// True when the lens needs an orders fetch (vs reading from
  /// AppState's hydrated caches). Inventory / Payroll / Staff /
  /// Attendance all read from caches.
  bool get needsOrders =>
      this == _ReportLens.all ||
      this == _ReportLens.sales ||
      this == _ReportLens.products;
}

/// Owner-facing Reports page. One scrollable surface, broken into
/// labelled sections; everything answers a question the owner might
/// ask out loud ("how am I doing?", "what's selling?", "who closed
/// the most tickets?"). The top bar drives the entire page — pick a
/// preset range, optionally compare to the matching prior window,
/// and every section refreshes from the live `orders` table.
///
/// The pattern is deliberately additive: when an owner needs a new
/// cut of the data, you drop in a new `_Section` widget and feed it
/// the same `_ReportData` snapshot.
class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  _ReportLens _lens = _ReportLens.all;
  String _salesSubTab = 'general';
  _DateRange _range = _DateRange.today();
  bool _comparePrior = true;

  _ReportData? _data;
  bool _loading = true;
  bool _hadError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    // Lenses that read from AppState's already-hydrated caches (
    // inventory, payroll, staff) don't need an orders fetch.
    // Attendance does scope to the date range but reads time_entries
    // from cache too — still no fetch required.
    if (!_lens.needsOrders) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hadError = false;
      });
      return;
    }
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      // Run current + prior fetches in parallel so a 7d/7d compare
      // is two round-trips at once instead of serial. Each query is
      // tenant-scoped via RLS in fetchOrders.
      final results = await Future.wait<List<o.Order>>([
        state.fetchOrders(
          since: _range.start.toUtc(),
          until: _range.end.toUtc(),
          limit: 5000,
        ),
        if (_comparePrior)
          state.fetchOrders(
            since: _range.prior.start.toUtc(),
            until: _range.prior.end.toUtc(),
            limit: 5000,
          ),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _ReportData(
          range: _range,
          current: results[0],
          prior: results.length > 1 ? results[1] : const [],
        );
        _hadError = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hadError = true;
        _loading = false;
      });
    }
  }

  void _setLens(_ReportLens lens) {
    setState(() => _lens = lens);
    // Pull fresh orders when switching back to an orders-driven
    // lens after we'd skipped the fetch.
    if (lens.needsOrders && _data == null) {
      _refresh();
    } else if (!lens.needsOrders) {
      setState(() => _loading = false);
    }
  }

  void _setRange(_DateRange r) {
    setState(() => _range = r);
    _refresh();
  }

  Future<void> _pickCustomRange() async {
    // The internal `_range.end` is exclusive (the day *after* the
    // last sales day), but `showDateRangePicker` expects the
    // INCLUSIVE last day and asserts `end <= lastDate`. Subtract a
    // day for the seed, and clamp anything in the future back to
    // today so chip ranges that include "today" (e.g. last 7 days)
    // don't trip the assertion when we open the picker.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endInclusive = _range.end
        .subtract(const Duration(days: 1));
    final seedEnd = endInclusive.isAfter(today) ? today : endInclusive;
    final seedStart =
        _range.start.isAfter(seedEnd) ? seedEnd : _range.start;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: seedStart, end: seedEnd),
      firstDate: today.subtract(const Duration(days: 365 * 2)),
      lastDate: today,
      builder: (_, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: YColor.brand,
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    _setRange(_DateRange.custom(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          if (_hadError) _errorBanner(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _lensRail(),
                Expanded(
                  child: Column(
                    children: [
                      if (_lens.usesDateRange) ...[
                        _rangeBar(),
                        Container(height: 0.5, color: YColor.hairline),
                      ],
                      Expanded(
                        child: RefreshIndicator(
                          color: YColor.brand,
                          onRefresh: _refresh,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(24, 16, 24, 120),
                            child: _loading &&
                                    data == null &&
                                    _lens.needsOrders
                                ? _skeleton()
                                : _content(data),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Left rail — pick which report to see (Sales / Products / …).
  Widget _lensRail() {
    return SizedBox(
      width: 198,
      child: Container(
        decoration: const BoxDecoration(
          color: YColor.surface1,
          border: Border(right: BorderSide(color: YColor.hairline)),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 24),
          children: [
            for (final l in _ReportLens.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: GestureDetector(
                  onTap: () => _setLens(l),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 11),
                    decoration: BoxDecoration(
                      color: _lens == l ? YColor.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(YRadius.md),
                    ),
                    child: Row(children: [
                      Icon(l.icon,
                          size: 18,
                          color: _lens == l
                              ? Colors.white
                              : YColor.brandDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.bodyStrong().copyWith(
                              fontSize: 13.5,
                              color: _lens == l ? Colors.white : YColor.ink,
                            )),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Right-pane top bar — date presets + custom + compare toggle.
  Widget _rangeBar() {
    return Container(
      color: YColor.surface1,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final preset in _DateRange.presets()) ...[
            _chip(
              label: preset.label,
              on: _range.matchesPreset(preset),
              onTap: () => _setRange(preset),
            ),
            const SizedBox(width: 6),
          ],
          _chip(
            label: _range.isCustom
                ? '${_fmtShort(_range.start)} → ${_fmtShort(_range.end.subtract(const Duration(seconds: 1)))}'
                : 'Custom…',
            on: _range.isCustom,
            onTap: _pickCustomRange,
            icon: Icons.calendar_month,
          ),
          const SizedBox(width: 14),
          _toggle(
            label: 'Compare to previous',
            on: _comparePrior,
            onTap: () {
              setState(() => _comparePrior = !_comparePrior);
              _refresh();
            },
          ),
        ]),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool on,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? YColor.brand : YColor.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? YColor.brand : YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon,
                size: 13, color: on ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 12,
              color: on ? Colors.white : YColor.ink,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _toggle({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on
              ? YColor.brand.withValues(alpha: 0.12)
              : YColor.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? YColor.brand : YColor.hairline,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            on ? Icons.check_box : Icons.check_box_outline_blank,
            size: 16,
            color: on ? YColor.brand : YColor.inkMuted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 12,
              color: on ? YColor.brand : YColor.ink,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      color: YColor.dangerSoft,
      child: Row(children: [
        const Icon(Icons.cloud_off_outlined,
            color: YColor.danger, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not load reports. Check your connection and pull '
            'down to retry.',
            style: YFont.caption().copyWith(color: YColor.danger),
          ),
        ),
        TextButton(onPressed: _refresh, child: const Text('Retry')),
      ]),
    );
  }

  Widget _skeleton() {
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.lg),
            border:
                Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(children: [block(96), block(280), block(280), block(220)]),
    );
  }

  Widget _content(_ReportData? data) {
    // Inventory lens reads from AppState directly and doesn't need
    // the `_ReportData` order snapshot, so we pull tenant data here
    // via watch() and forward it to the inventory section.
    final state = context.watch<AppState>();
    final sections = <Widget>[];

    switch (_lens) {
      case _ReportLens.inventory:
        sections.addAll(_inventorySections(state));
      case _ReportLens.payroll:
        sections.addAll(_payrollSections(state));
      case _ReportLens.staff:
        sections.addAll(_staffSections(state, data));
      case _ReportLens.attendance:
        sections.addAll(_attendanceSections(state));
      case _ReportLens.sales:
        if (data != null) sections.addAll(_salesSections(data));
      case _ReportLens.products:
        if (data != null) sections.addAll(_productSections(data));
      case _ReportLens.all:
        if (data != null) sections.addAll(_allSections(data, state));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          sections[i],
          if (i != sections.length - 1) const SizedBox(height: 14),
        ],
      ],
    );
  }

  List<Widget> _salesSections(_ReportData data) {
    final separated = _separatedSalesGroups(context.read<AppState>(), data);
    return [
      _salesSubTabBar(),
      if (_salesSubTab == 'separated')
        _CategoryBreakdownSection(
          title: 'Separated sales',
          subtitle:
              'Consigned / separated groups (Books, Flowers…) and the products sold',
          groups: separated,
          emptyMessage:
              'No separated sales groups yet. In Maintenance, turn on '
              '"Separate in Sales reports" for a Product Type or Category '
              '(e.g. consigned Books) to settle it here.',
        )
      else ...[
        _Headline(data: data, comparing: _comparePrior),
        _KpiStrip(data: data, comparing: _comparePrior),
        _SalesOverTime(data: data, comparing: _comparePrior),
        _TwoColRow(
          left: _ByPaymentSection(data: data),
          right: _PeakHoursSection(data: data),
        ),
        _TwoColRow(
          left: _ByCashierSection(data: data),
          right: _RefundsVoidsSection(data: data),
        ),
        _SalesGroupsSection(data: data),
      ],
    ];
  }

  /// General vs Separated sub-tabs for the Sales lens.
  Widget _salesSubTabBar() {
    Widget chip(String key, String label, IconData icon) {
      final on = _salesSubTab == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _salesSubTab = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: on ? YColor.brand : YColor.surface1,
              borderRadius: BorderRadius.circular(999),
              border:
                  Border.all(color: on ? YColor.brand : YColor.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 15, color: on ? Colors.white : YColor.brandDeep),
              const SizedBox(width: 7),
              Text(label,
                  style: YFont.bodyStrong().copyWith(
                      fontSize: 13,
                      color: on ? Colors.white : YColor.ink)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        chip('general', 'General', Icons.insights_outlined),
        chip('separated', 'Separated', Icons.sell_outlined),
      ]),
    );
  }

  List<Widget> _productSections(_ReportData data) => [
        _Headline(data: data, comparing: _comparePrior),
        _ProductKpiStrip(data: data),
        _TwoColRow(
          left: _TopItemsSection(data: data),
          right: _ByCategorySection(data: data),
        ),
        _CategoryBreakdownSection(
          title: 'Products by category',
          subtitle: 'Tap a category to see the products sold under it',
          groups: data.categoryGroups,
          emptyMessage: 'No products sold in this range yet.',
        ),
      ];

  List<Widget> _inventorySections(AppState state) => [
        _InventoryHeadline(state: state),
        _InventoryKpiStrip(state: state),
        _TwoColRow(
          left: _LowStockSection(state: state),
          right: _InventoryByCategorySection(state: state),
        ),
        _InventoryValueListSection(state: state),
      ];

  List<Widget> _payrollSections(AppState state) => [
        _PayrollHeadline(state: state),
        _PayrollKpiStrip(state: state),
        _PayrollRunsListSection(state: state),
        _TwoColRow(
          left: _PayrollByEmployeeSection(state: state),
          right: _PayrollDeductionsSection(state: state),
        ),
      ];

  List<Widget> _staffSections(AppState state, _ReportData? data) => [
        _StaffHeadline(state: state),
        _StaffKpiStrip(state: state),
        _TwoColRow(
          left: _StaffRosterSection(state: state),
          // Reuse the sales cashier leaderboard when current-period
          // order data is loaded — answers "who's selling the most?"
          right: data == null
              ? _StaffComingSoonCard(
                  message:
                      'Switch to Sales lens (or All) to load order data — '
                      'we\'ll show the cashier leaderboard here once it\'s '
                      'available.')
              : _ByCashierSection(data: data),
        ),
      ];

  List<Widget> _attendanceSections(AppState state) => [
        _AttendanceHeadline(state: state, range: _range),
        _AttendanceKpiStrip(state: state, range: _range),
        _TwoColRow(
          left: _AttendanceLeaderboardSection(
              state: state, range: _range),
          right: _AttendanceByDaySection(state: state, range: _range),
        ),
      ];

  List<Widget> _allSections(_ReportData data, AppState state) => [
        _Headline(data: data, comparing: _comparePrior),
        _KpiStrip(data: data, comparing: _comparePrior),
        _SalesOverTime(data: data, comparing: _comparePrior),
        _TwoColRow(
          left: _TopItemsSection(data: data),
          right: _ByPaymentSection(data: data),
        ),
        _TwoColRow(
          left: _PeakHoursSection(data: data),
          right: _ByCashierSection(data: data),
        ),
        _TwoColRow(
          left: _ByCategorySection(data: data),
          right: _RefundsVoidsSection(data: data),
        ),
        // Inventory health pinned at the bottom in "All" mode so the
        // owner gets a one-page overview without switching lenses.
        _InventoryKpiStrip(state: state),
        _TwoColRow(
          left: _LowStockSection(state: state),
          right: _InventoryByCategorySection(state: state),
        ),
      ];
}

// ─────────────────────── Date range helper ─────────────────────────

/// A half-open `[start, end)` range. `prior` is the same-length
/// window immediately before this one — that's what powers the
/// compare-to-previous numbers and deltas.
class _DateRange {
  _DateRange({
    required this.start,
    required this.end,
    required this.label,
    this.isCustom = false,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final bool isCustom;

  Duration get span => end.difference(start);
  _DateRange get prior => _DateRange(
        start: start.subtract(span),
        end: start,
        label: 'Previous $label',
      );

  bool matchesPreset(_DateRange other) =>
      !isCustom && label == other.label;

  static _DateRange today() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _DateRange(
        start: start, end: start.add(const Duration(days: 1)), label: 'Today');
  }

  static _DateRange yesterday() {
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day - 1);
    return _DateRange(
        start: start,
        end: start.add(const Duration(days: 1)),
        label: 'Yesterday');
  }

  static _DateRange last7() {
    final now = DateTime.now();
    final endExcl =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return _DateRange(
      start: endExcl.subtract(const Duration(days: 7)),
      end: endExcl,
      label: '7 days',
    );
  }

  static _DateRange last30() {
    final now = DateTime.now();
    final endExcl =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return _DateRange(
      start: endExcl.subtract(const Duration(days: 30)),
      end: endExcl,
      label: '30 days',
    );
  }

  static _DateRange thisMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return _DateRange(start: start, end: end, label: 'This month');
  }

  static _DateRange custom(DateTime s, DateTime e) {
    final start = DateTime(s.year, s.month, s.day);
    final end = DateTime(e.year, e.month, e.day)
        .add(const Duration(days: 1));
    return _DateRange(
      start: start,
      end: end,
      label: 'Custom',
      isCustom: true,
    );
  }

  static List<_DateRange> presets() => [
        today(),
        yesterday(),
        last7(),
        last30(),
        thisMonth(),
      ];
}

String _fmtShort(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

// ─────────────────────── Aggregated snapshot ───────────────────────

/// One immutable bundle of "everything the sections need". Computing
/// it once (instead of inside each card) keeps the page fast as more
/// sections are added — every aggregation walks the order list at
/// most once.
class _ReportData {
  _ReportData({
    required this.range,
    required List<o.Order> current,
    required List<o.Order> prior,
  })  : _current = current,
        _prior = prior {
    _compute();
  }

  final _DateRange range;
  final List<o.Order> _current;
  final List<o.Order> _prior;

  late int totalCents;
  late int orderCount;
  late int itemCount;
  late int avgTicketCents;
  late int priorTotalCents;
  late int priorOrderCount;

  /// Buckets revenue centavos by local calendar day for the chart.
  /// Map key is "yyyy-MM-dd"; sorted insertion order.
  late Map<DateTime, int> dailyTotals;

  /// Top items by quantity sold across the current period. Capped at
  /// 50 to keep the export reasonable; the card shows the top 8.
  late List<_TopItem> topItems;

  /// Revenue + count grouped by payment method.
  late Map<o.OrderPaymentMethod, _PayBucket> payments;

  /// Hour-of-day buckets 0..23 with revenue centavos.
  late List<int> hourlyTotals;

  /// Cashier leaderboard — name → (orders, revenue).
  late List<_CashierRow> cashiers;

  /// Category buckets — name → revenue.
  late List<_CategoryRow> categories;

  /// Categories with the individual products sold under each (for the
  /// expandable per-category / per-sales-group breakdowns).
  late List<_CatGroup> categoryGroups;

  /// Refunds + voids in the period.
  late List<o.Order> refundsAndVoids;

  // Real (status=paid) orders from the current period; many sections
  // ignore voided / cancelled / open so we precompute the filter.
  late List<o.Order> paid;

  void _compute() {
    paid =
        _current.where((ord) => ord.status == o.OrderStatus.paid).toList();
    final priorPaid =
        _prior.where((ord) => ord.status == o.OrderStatus.paid).toList();

    totalCents = paid.fold(0, (a, ord) => a + ord.totalCents);
    orderCount = paid.length;
    itemCount = paid.fold(
        0, (a, ord) => a + ord.lines.fold(0, (b, l) => b + l.quantity));
    avgTicketCents =
        orderCount == 0 ? 0 : totalCents ~/ orderCount;
    priorTotalCents = priorPaid.fold(0, (a, ord) => a + ord.totalCents);
    priorOrderCount = priorPaid.length;

    // Daily buckets — one entry per day in the range, even days with
    // zero sales, so the chart never has missing gaps.
    dailyTotals = <DateTime, int>{};
    DateTime cursor = range.start;
    while (cursor.isBefore(range.end)) {
      dailyTotals[DateTime(cursor.year, cursor.month, cursor.day)] = 0;
      cursor = cursor.add(const Duration(days: 1));
    }
    for (final ord in paid) {
      final d = ord.createdAt.toLocal();
      final key = DateTime(d.year, d.month, d.day);
      dailyTotals[key] = (dailyTotals[key] ?? 0) + ord.totalCents;
    }

    // Top items
    final itemAgg = <String, _TopItem>{};
    for (final ord in paid) {
      for (final l in ord.lines) {
        final cur = itemAgg[l.name];
        if (cur == null) {
          itemAgg[l.name] = _TopItem(
            name: l.name,
            emoji: l.emoji,
            qty: l.quantity,
            revenueCents: l.lineTotalCents,
          );
        } else {
          itemAgg[l.name] = _TopItem(
            name: l.name,
            emoji: cur.emoji.isEmpty ? l.emoji : cur.emoji,
            qty: cur.qty + l.quantity,
            revenueCents: cur.revenueCents + l.lineTotalCents,
          );
        }
      }
    }
    topItems = itemAgg.values.toList()
      ..sort((a, b) => b.qty.compareTo(a.qty));
    if (topItems.length > 50) topItems = topItems.sublist(0, 50);

    // Payments
    payments = <o.OrderPaymentMethod, _PayBucket>{};
    for (final ord in paid) {
      for (final p in ord.payments) {
        final cur = payments[p.method];
        if (cur == null) {
          payments[p.method] = _PayBucket(count: 1, cents: p.amountCents);
        } else {
          payments[p.method] = _PayBucket(
            count: cur.count + 1,
            cents: cur.cents + p.amountCents,
          );
        }
      }
    }

    // Hourly
    hourlyTotals = List<int>.filled(24, 0);
    for (final ord in paid) {
      final h = ord.createdAt.toLocal().hour;
      hourlyTotals[h] += ord.totalCents;
    }

    // Cashiers
    final cashAgg = <String, _CashierRow>{};
    for (final ord in paid) {
      final name = (ord.cashierName ?? '').trim().isEmpty
          ? 'Unassigned'
          : ord.cashierName!.trim();
      final cur = cashAgg[name];
      if (cur == null) {
        cashAgg[name] =
            _CashierRow(name: name, orders: 1, cents: ord.totalCents);
      } else {
        cashAgg[name] = _CashierRow(
          name: name,
          orders: cur.orders + 1,
          cents: cur.cents + ord.totalCents,
        );
      }
    }
    cashiers = cashAgg.values.toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    // Categories
    final catAgg = <String, _CategoryRow>{};
    for (final ord in paid) {
      for (final l in ord.lines) {
        final name = (l.categoryName ?? '').trim().isEmpty
            ? 'Uncategorised'
            : l.categoryName!.trim();
        final cur = catAgg[name];
        if (cur == null) {
          catAgg[name] = _CategoryRow(
            name: name,
            qty: l.quantity,
            cents: l.lineTotalCents,
          );
        } else {
          catAgg[name] = _CategoryRow(
            name: name,
            qty: cur.qty + l.quantity,
            cents: cur.cents + l.lineTotalCents,
          );
        }
      }
    }
    categories = catAgg.values.toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    // Categories → products sold under each.
    final catGroupAgg = <String, Map<String, _TopItem>>{};
    for (final ord in paid) {
      for (final l in ord.lines) {
        final cat = (l.categoryName ?? '').trim().isEmpty
            ? 'Uncategorised'
            : l.categoryName!.trim();
        final byName =
            catGroupAgg.putIfAbsent(cat, () => <String, _TopItem>{});
        final cur = byName[l.name];
        byName[l.name] = _TopItem(
          name: l.name,
          emoji: cur == null
              ? l.emoji
              : (cur.emoji.isEmpty ? l.emoji : cur.emoji),
          qty: (cur?.qty ?? 0) + l.quantity,
          revenueCents: (cur?.revenueCents ?? 0) + l.lineTotalCents,
        );
      }
    }
    categoryGroups = catGroupAgg.entries.map((e) {
      final items = e.value.values.toList()
        ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents));
      return _CatGroup(
        name: e.key,
        cents: items.fold<int>(0, (s, i) => s + i.revenueCents),
        qty: items.fold<int>(0, (s, i) => s + i.qty),
        items: items,
      );
    }).toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    refundsAndVoids = _current
        .where((ord) =>
            ord.status == o.OrderStatus.refunded ||
            ord.status == o.OrderStatus.voided)
        .toList();
  }

  /// Percentage delta from prior period's total revenue. `null` when
  /// the prior period had zero revenue (division-by-zero).
  double? get deltaPct {
    if (priorTotalCents == 0) return null;
    return (totalCents - priorTotalCents) / priorTotalCents * 100;
  }
}

class _TopItem {
  _TopItem({
    required this.name,
    required this.emoji,
    required this.qty,
    required this.revenueCents,
  });
  final String name;
  final String emoji;
  final int qty;
  final int revenueCents;
}

class _PayBucket {
  _PayBucket({required this.count, required this.cents});
  final int count;
  final int cents;
}

class _CashierRow {
  _CashierRow({
    required this.name,
    required this.orders,
    required this.cents,
  });
  final String name;
  final int orders;
  final int cents;
}

class _CategoryRow {
  _CategoryRow({
    required this.name,
    required this.qty,
    required this.cents,
  });
  final String name;
  final int qty;
  final int cents;
}

/// A category with the individual products sold under it.
class _CatGroup {
  _CatGroup({
    required this.name,
    required this.qty,
    required this.cents,
    required this.items,
  });
  final String name;
  final int qty;
  final int cents;
  final List<_TopItem> items;
}

/// Re-buckets categories into sales groups for the "Separated" sales view —
/// only the categories/types flagged `separateSales` (Books, Flowers, …),
/// each carrying the products sold under it. General sales are excluded.
List<_CatGroup> _separatedSalesGroups(AppState state, _ReportData data) {
  final catByName = {
    for (final c in state.categories) c.name.trim().toLowerCase(): c,
  };
  final typeById = {for (final t in state.productTypes) t.id: t};
  final groups = <String, ({String name, Map<String, _TopItem> items})>{};
  for (final cg in data.categoryGroups) {
    final c = catByName[cg.name.trim().toLowerCase()];
    final type = c?.typeId == null ? null : typeById[c!.typeId];
    String key;
    String name;
    if (c != null && c.separateSales) {
      key = 'sub:${c.id}';
      name = c.name;
    } else if (type != null && type.separateSales) {
      key = 'type:${type.id}';
      name = type.name;
    } else {
      continue; // General — not shown in Separated.
    }
    final g = groups.putIfAbsent(
        key, () => (name: name, items: <String, _TopItem>{}));
    for (final it in cg.items) {
      final cur = g.items[it.name];
      g.items[it.name] = _TopItem(
        name: it.name,
        emoji: it.emoji,
        qty: (cur?.qty ?? 0) + it.qty,
        revenueCents: (cur?.revenueCents ?? 0) + it.revenueCents,
      );
    }
  }
  return groups.values.map((g) {
    final items = g.items.values.toList()
      ..sort((a, b) => b.revenueCents.compareTo(a.revenueCents));
    return _CatGroup(
      name: g.name,
      cents: items.fold<int>(0, (s, i) => s + i.revenueCents),
      qty: items.fold<int>(0, (s, i) => s + i.qty),
      items: items,
    );
  }).toList()
    ..sort((a, b) => b.cents.compareTo(a.cents));
}

/// Expandable list of categories/sales-groups — tap a row to reveal the
/// products sold under it (qty + revenue). Reused by the Products tab and the
/// Sales "Separated" view.
class _CategoryBreakdownSection extends StatefulWidget {
  const _CategoryBreakdownSection({
    required this.title,
    required this.subtitle,
    required this.groups,
    required this.emptyMessage,
  });
  final String title;
  final String subtitle;
  final List<_CatGroup> groups;
  final String emptyMessage;

  @override
  State<_CategoryBreakdownSection> createState() =>
      _CategoryBreakdownSectionState();
}

class _CategoryBreakdownSectionState extends State<_CategoryBreakdownSection> {
  final Set<String> _open = {};

  String _peso(int cents) => '₱${(cents / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    return _SectionCard(
      title: widget.title,
      subtitle: widget.subtitle,
      onExportCsv: () {
        final buf = StringBuffer('Category,Product,Qty,Revenue (PHP)\n');
        for (final g in groups) {
          for (final it in g.items) {
            final cat = g.name.replaceAll('"', '""');
            final p = it.name.replaceAll('"', '""');
            buf.writeln('"$cat","$p",${it.qty},'
                '${(it.revenueCents / 100).toStringAsFixed(2)}');
          }
        }
        return buf.toString();
      },
      child: groups.isEmpty
          ? _empty(widget.emptyMessage)
          : Column(children: [for (final g in groups) _tile(g)]),
    );
  }

  Widget _tile(_CatGroup g) {
    final open = _open.contains(g.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(YRadius.md),
          onTap: () => setState(
              () => open ? _open.remove(g.name) : _open.add(g.name)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            child: Row(children: [
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.chevron_right,
                    size: 20, color: YColor.inkMuted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(g.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.bodyStrong().copyWith(fontSize: 13.5)),
              ),
              Text('${g.qty} sold',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              const SizedBox(width: 14),
              Text(_peso(g.cents),
                  style: YFont.bodyStrong()
                      .copyWith(fontSize: 13.5, color: YColor.brandDeep)),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 6),
            child: Column(
              children: [
                for (final it in g.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            it.emoji.isEmpty
                                ? it.name
                                : '${it.emoji}  ${it.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.body().copyWith(fontSize: 13)),
                      ),
                      Text('${it.qty}×',
                          style: YFont.caption()
                              .copyWith(color: YColor.inkMuted)),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 80,
                        child: Text(_peso(it.revenueCents),
                            textAlign: TextAlign.right,
                            style: YFont.bodyStrong().copyWith(fontSize: 13)),
                      ),
                    ]),
                  ),
              ],
            ),
          ),
        Container(height: 0.5, color: YColor.hairline.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ─────────────────────── Generic section card ──────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onExportCsv,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final String Function()? onExportCsv;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: YFont.titleMD().copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: YFont.caption()),
                  ],
                ),
              ),
              if (onExportCsv != null)
                IconButton(
                  tooltip: 'Copy as CSV',
                  onPressed: () async {
                    final csv = onExportCsv!();
                    await Clipboard.setData(ClipboardData(text: csv));
                    if (context.mounted) {
                      PushToast.show(context,
                          title: 'Copied to clipboard',
                          subtitle:
                              'Paste into Excel or Google Sheets.',
                          leadingIcon: Icons.check_circle_outline);
                    }
                  },
                  icon: const Icon(Icons.ios_share_outlined,
                      size: 18, color: YColor.inkMuted),
                ),
            ]),
          ),
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: YColor.hairline,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _TwoColRow extends StatelessWidget {
  const _TwoColRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, c) {
      // Stack on narrow widths (phones / split-screen) so each
      // section gets full width to breathe.
      if (c.maxWidth < 760) {
        return Column(children: [
          left,
          const SizedBox(height: 14),
          right,
        ]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 14),
          Expanded(child: right),
        ],
      );
    });
  }
}

// ─────────────────────── Headline ──────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline({required this.data, required this.comparing});
  final _ReportData data;
  final bool comparing;

  @override
  Widget build(BuildContext context) {
    final delta = data.deltaPct;
    final isUp = delta != null && delta >= 0;
    final headline = _phrase(data);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YColor.brand.withValues(alpha: 0.92),
            YColor.brandDeep.withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: YColor.brand.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.range.label.toUpperCase(),
                    style: YFont.caption().copyWith(
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.85),
                    )),
                const SizedBox(height: 6),
                Text(
                  Money(data.totalCents).formatted,
                  style: YFont.titleLG().copyWith(
                    fontSize: 36,
                    letterSpacing: -1.0,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(headline,
                    style: YFont.body().copyWith(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.92),
                    )),
              ],
            ),
          ),
          if (comparing && delta != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(isUp ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '${delta.abs().toStringAsFixed(1)}%',
                  style: YFont.bodyStrong().copyWith(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  /// Plain-English summary of the period so the owner doesn't have to
  /// translate numbers themselves.
  String _phrase(_ReportData d) {
    if (d.orderCount == 0) {
      return 'No sales recorded in this period yet.';
    }
    final tail = ' across ${d.orderCount} order'
        '${d.orderCount == 1 ? "" : "s"} · '
        '${d.itemCount} item${d.itemCount == 1 ? "" : "s"}';
    final delta = d.deltaPct;
    if (delta == null) return 'Total sales$tail';
    if (delta >= 5) {
      return 'Strong period$tail · ${delta.toStringAsFixed(1)}% above the prior.';
    } else if (delta <= -5) {
      return 'Softer period$tail · ${delta.abs().toStringAsFixed(1)}% below the prior.';
    }
    return 'Holding steady$tail';
  }
}

// ─────────────────────── KPI strip ─────────────────────────────────

class _KpiStrip extends StatelessWidget {
  const _KpiStrip({required this.data, required this.comparing});
  final _ReportData data;
  final bool comparing;

  @override
  Widget build(BuildContext context) {
    final orderDelta =
        (comparing && data.priorOrderCount != 0)
            ? (data.orderCount - data.priorOrderCount) /
                data.priorOrderCount *
                100
            : null;

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.payments_outlined,
              tone: YColor.brand,
              label: 'Net sales',
              value: Money(data.totalCents).formatted,
              delta: data.deltaPct,
              showDelta: comparing,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.receipt_long_outlined,
              tone: YColor.brandDeep,
              label: 'Orders',
              value: data.orderCount.toString(),
              delta: orderDelta,
              showDelta: comparing,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.trending_up,
              tone: Colors.teal,
              label: 'Avg ticket',
              value: Money(data.avgTicketCents).formatted,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.shopping_basket_outlined,
              tone: Colors.indigo,
              label: 'Items sold',
              value: data.itemCount.toString(),
            ),
          ),
        ],
      );
    });
  }
}

class _KpiBox extends StatelessWidget {
  const _KpiBox({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    this.delta,
    this.showDelta = false,
  });
  final IconData icon;
  final Color tone;
  final String label;
  final String value;
  final double? delta;
  final bool showDelta;

  @override
  Widget build(BuildContext context) {
    final isUp = delta != null && delta! >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: tone),
            ),
            const Spacer(),
            if (showDelta && delta != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: (isUp ? YColor.success : YColor.danger)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 14,
                      color: isUp ? YColor.success : YColor.danger),
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
          const SizedBox(height: 12),
          Text(value,
              style: YFont.titleLG()
                  .copyWith(fontSize: 22, letterSpacing: -0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: YFont.caption()),
        ],
      ),
    );
  }
}

// ─────────────────────── Sales over time ───────────────────────────

class _SalesOverTime extends StatelessWidget {
  const _SalesOverTime({required this.data, required this.comparing});
  final _ReportData data;
  final bool comparing;

  @override
  Widget build(BuildContext context) {
    final entries = data.dailyTotals.entries.toList();
    final maxRaw = entries.fold<double>(
        0, (a, e) => e.value / 100 > a ? e.value / 100 : a);
    final yMax = maxRaw == 0 ? 1000.0 : ((maxRaw / 1000).ceil() * 1000).toDouble();
    final showAsBars = entries.length <= 14;

    return _SectionCard(
      title: 'Sales over time',
      subtitle:
          showAsBars ? 'Daily revenue' : 'Daily revenue (longer range)',
      onExportCsv: () {
        final buf = StringBuffer('Date,Revenue (PHP)\n');
        for (final e in entries) {
          buf.writeln('${e.key.toIso8601String().substring(0, 10)},'
              '${(e.value / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: SizedBox(
        height: 240,
        child: showAsBars
            ? _bars(entries, yMax)
            : _line(entries, yMax),
      ),
    );
  }

  Widget _bars(List<MapEntry<DateTime, int>> entries, double yMax) {
    return BarChart(
      BarChartData(
        maxY: yMax * 1.1,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (_) => FlLine(
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
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) {
                  return const SizedBox.shrink();
                }
                final d = entries[i].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    entries.length <= 7
                        ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.weekday - 1]
                        : '${d.day}',
                    style: YFont.caption().copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: yMax / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '₱${v.toInt()}',
                  style: YFont.caption().copyWith(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: entries[i].value / 100,
                color: i == entries.length - 1
                    ? YColor.brand
                    : YColor.brandDeep.withValues(alpha: 0.55),
                width: entries.length <= 7 ? 26 : 14,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _line(List<MapEntry<DateTime, int>> entries, double yMax) {
    return LineChart(
      LineChartData(
        maxY: yMax * 1.1,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (_) => FlLine(
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
              reservedSize: 28,
              interval: (entries.length / 6).clamp(1, 10).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= entries.length) {
                  return const SizedBox.shrink();
                }
                final d = entries[i].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${d.month}/${d.day}',
                      style: YFont.caption().copyWith(fontSize: 10)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: yMax / 4,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text('₱${v.toInt()}',
                    style: YFont.caption().copyWith(fontSize: 10)),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            curveSmoothness: 0.25,
            color: YColor.brand,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: YColor.brand.withValues(alpha: 0.12),
            ),
            spots: [
              for (var i = 0; i < entries.length; i++)
                FlSpot(i.toDouble(), entries[i].value / 100),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── Top items section ─────────────────────────

class _TopItemsSection extends StatelessWidget {
  const _TopItemsSection({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final top = data.topItems.take(8).toList();
    final maxQty = top.isEmpty ? 1 : top.first.qty;
    return _SectionCard(
      title: 'Top items',
      subtitle: 'What\'s moving most this period',
      onExportCsv: () {
        final buf = StringBuffer('Item,Qty,Revenue (PHP)\n');
        for (final t in data.topItems) {
          final clean = t.name.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${t.qty},${(t.revenueCents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: top.isEmpty
          ? _empty('No items sold yet.')
          : Column(
              children: [
                for (final t in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      SizedBox(
                        width: 28,
                        child: Text(
                          t.emoji.isEmpty ? '·' : t.emoji,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: t.qty / maxQty,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor:
                                    const AlwaysStoppedAnimation(YColor.brand),
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
                            Text('${t.qty}',
                                style: YFont.bodyStrong()),
                            Text(Money(t.revenueCents).formatted,
                                style: YFont.caption().copyWith(fontSize: 11)),
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

// ─────────────────────── Payment method section ────────────────────

class _ByPaymentSection extends StatelessWidget {
  const _ByPaymentSection({required this.data});
  final _ReportData data;

  static const _tones = <o.OrderPaymentMethod, Color>{
    o.OrderPaymentMethod.cash: Color(0xFF5C8A6B),
    o.OrderPaymentMethod.gcash: Color(0xFF3D5A7A),
    o.OrderPaymentMethod.paymaya: Color(0xFF8A5A8A),
    o.OrderPaymentMethod.card: Color(0xFFC29A36),
    o.OrderPaymentMethod.bankTransfer: Color(0xFF7C8F65),
    o.OrderPaymentMethod.qrPh: Color(0xFF6E5AA0),
    o.OrderPaymentMethod.other: Color(0xFF8A8A8A),
  };

  @override
  Widget build(BuildContext context) {
    final entries = data.payments.entries.toList()
      ..sort((a, b) => b.value.cents.compareTo(a.value.cents));
    final total = entries.fold<int>(0, (a, e) => a + e.value.cents);
    return _SectionCard(
      title: 'By payment method',
      subtitle: 'Where the money came in',
      onExportCsv: () {
        final buf = StringBuffer('Method,Transactions,Revenue (PHP),Share %\n');
        for (final e in entries) {
          final pct = total == 0 ? 0 : (e.value.cents / total * 100);
          buf.writeln(
              '${e.key.label},${e.value.count},'
              '${(e.value.cents / 100).toStringAsFixed(2)},'
              '${pct.toStringAsFixed(1)}');
        }
        return buf.toString();
      },
      child: entries.isEmpty
          ? _empty('No payments yet.')
          : Column(
              children: [
                for (final e in entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _tones[e.key] ?? YColor.brand,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key.label,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: total == 0
                                    ? 0
                                    : e.value.cents / total,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: AlwaysStoppedAnimation(
                                    _tones[e.key] ?? YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 86,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(e.value.cents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text(
                                '${e.value.count} tx · '
                                '${total == 0 ? "0" : (e.value.cents / total * 100).toStringAsFixed(0)}%',
                                style: YFont.caption()
                                    .copyWith(fontSize: 11)),
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

// ─────────────────────── Peak hours section ────────────────────────

class _PeakHoursSection extends StatelessWidget {
  const _PeakHoursSection({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final hours = data.hourlyTotals;
    final max = hours.fold<int>(0, (a, b) => b > a ? b : a);
    final peakHour = max == 0 ? null : hours.indexOf(max);
    return _SectionCard(
      title: 'Peak hours',
      subtitle: peakHour == null
          ? 'Hourly revenue'
          : 'Busiest hour: ${_fmtHour(peakHour)}',
      onExportCsv: () {
        final buf = StringBuffer('Hour,Revenue (PHP)\n');
        for (var h = 0; h < hours.length; h++) {
          buf.writeln(
              '${h.toString().padLeft(2, '0')}:00,${(hours[h] / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: SizedBox(
        height: 180,
        child: max == 0
            ? _empty('Not enough data to spot a peak yet.')
            : BarChart(
                BarChartData(
                  maxY: (max / 100) * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: 3,
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _fmtHourShort(v.toInt()),
                            style:
                                YFont.caption().copyWith(fontSize: 9),
                          ),
                        ),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var h = 0; h < hours.length; h++)
                      BarChartGroupData(x: h, barRods: [
                        BarChartRodData(
                          toY: hours[h] / 100,
                          width: 8,
                          color: h == peakHour
                              ? YColor.brand
                              : YColor.brandDeep.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }

  String _fmtHour(int h) {
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final p = h >= 12 ? 'PM' : 'AM';
    return '$hh:00 $p';
  }

  String _fmtHourShort(int h) {
    if (h == 0) return '12a';
    if (h == 12) return '12p';
    return h < 12 ? '${h}a' : '${h - 12}p';
  }
}

// ─────────────────────── Cashier leaderboard ───────────────────────

class _ByCashierSection extends StatelessWidget {
  const _ByCashierSection({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.cashiers.take(8).toList();
    final maxCents =
        rows.isEmpty ? 1 : rows.first.cents;
    return _SectionCard(
      title: 'By cashier',
      subtitle: 'Who closed the most tickets',
      onExportCsv: () {
        final buf = StringBuffer('Cashier,Orders,Revenue (PHP)\n');
        for (final r in data.cashiers) {
          final clean = r.name.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${r.orders},${(r.cents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? _empty('No cashier-attributed orders yet.')
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? YColor.brand
                              : YColor.brandTint,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 11,
                            color: i == 0
                                ? Colors.white
                                : YColor.brandDeep,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rows[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: rows[i].cents / maxCents,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: const AlwaysStoppedAnimation(
                                    YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(rows[i].cents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text('${rows[i].orders} orders',
                                style: YFont.caption()
                                    .copyWith(fontSize: 11)),
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

// ─────────────────────── Category section ──────────────────────────

/// One settlement line on the Sales lens — a separated Type/Sub-type
/// (consignment) or the catch-all "General".
class _SalesGroup {
  _SalesGroup(this.name, this.cents, this.qty, this.isGeneral);
  final String name;
  int cents;
  int qty;
  final bool isGeneral;
}

/// Re-buckets the per-sub-type sales into "sales groups": any Sub-type flagged
/// `separateSales` is its own line (it wins), else any Sub-type whose parent
/// Type is flagged rolls into that Type's line, and everything else merges into
/// "General". Lets a cashier ring up everything while the owner settles
/// consigned goods (e.g. Books) on their own.
class _SalesGroupsSection extends StatelessWidget {
  const _SalesGroupsSection({required this.data});
  final _ReportData data;

  List<_SalesGroup> _groups(AppState state) {
    final catByName = {
      for (final c in state.categories) c.name.trim().toLowerCase(): c,
    };
    final typeById = {for (final t in state.productTypes) t.id: t};
    final groups = <String, _SalesGroup>{};
    void add(String key, String name, bool isGeneral, int cents, int qty) {
      final g = groups[key];
      if (g == null) {
        groups[key] = _SalesGroup(name, cents, qty, isGeneral);
      } else {
        g.cents += cents;
        g.qty += qty;
      }
    }

    for (final r in data.categories) {
      final c = catByName[r.name.trim().toLowerCase()];
      final type = c?.typeId == null ? null : typeById[c!.typeId];
      if (c != null && c.separateSales) {
        add('sub:${c.id}', c.name, false, r.cents, r.qty);
      } else if (type != null && type.separateSales) {
        add('type:${type.id}', type.name, false, r.cents, r.qty);
      } else {
        add('__general__', 'General', true, r.cents, r.qty);
      }
    }
    return groups.values.toList()
      ..sort((a, b) {
        if (a.isGeneral != b.isGeneral) return a.isGeneral ? 1 : -1;
        return b.cents.compareTo(a.cents);
      });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final groups = _groups(state);
    final hasSeparate = groups.any((g) => !g.isGeneral);
    final maxCents =
        groups.fold<int>(1, (m, g) => g.cents > m ? g.cents : m);
    return _SectionCard(
      title: 'Sales groups',
      subtitle: 'Separate settlements (e.g. consigned goods) vs General',
      onExportCsv: () {
        final buf = StringBuffer('Sales group,Kind,Items sold,Revenue (PHP)\n');
        for (final g in groups) {
          final clean = g.name.replaceAll('"', '""');
          buf.writeln('"$clean",${g.isGeneral ? 'General' : 'Separate'},'
              '${g.qty},${(g.cents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: !hasSeparate
          ? _empty('No separate sales groups yet. In Maintenance, turn on '
              '"Separate in Sales reports" for a Product Type or Category '
              '(e.g. consigned Books) to settle it on its own line here.')
          : Column(
              children: [
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: g.isGeneral
                              ? YColor.surface3
                              : YColor.brandTint.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          g.isGeneral
                              ? Icons.dashboard_customize_outlined
                              : Icons.sell_outlined,
                          size: 16,
                          color:
                              g.isGeneral ? YColor.inkMuted : YColor.brandDeep,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(g.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: YFont.bodyStrong()
                                        .copyWith(fontSize: 13)),
                              ),
                              if (!g.isGeneral) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: YColor.brandTint,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('SEPARATE',
                                      style: YFont.caption().copyWith(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                        color: YColor.brandDeep,
                                      )),
                                ),
                              ],
                            ]),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: g.cents / maxCents,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: AlwaysStoppedAnimation(
                                    g.isGeneral
                                        ? YColor.inkMuted
                                        : YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(g.cents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text('${g.qty} items',
                                style:
                                    YFont.caption().copyWith(fontSize: 11)),
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

class _ByCategorySection extends StatelessWidget {
  const _ByCategorySection({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.categories.take(8).toList();
    final maxCents = rows.isEmpty ? 1 : rows.first.cents;
    return _SectionCard(
      title: 'By category',
      subtitle: 'Which buckets bring in the money',
      onExportCsv: () {
        final buf = StringBuffer('Category,Items sold,Revenue (PHP)\n');
        for (final r in data.categories) {
          final clean = r.name.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${r.qty},${(r.cents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? _empty('No sales recorded yet.')
          : Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: YColor.brandTint.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.folder_outlined,
                            size: 16, color: YColor.brandDeep),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: r.cents / maxCents,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: const AlwaysStoppedAnimation(
                                    YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(r.cents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text('${r.qty} items',
                                style: YFont.caption()
                                    .copyWith(fontSize: 11)),
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

// ─────────────────────── Refunds + voids ───────────────────────────

class _RefundsVoidsSection extends StatelessWidget {
  const _RefundsVoidsSection({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.refundsAndVoids;
    final refundedCents = rows
        .where((ord) => ord.status == o.OrderStatus.refunded)
        .fold<int>(0, (a, ord) => a + ord.totalCents);
    return _SectionCard(
      title: 'Refunds & voids',
      subtitle: 'Money that didn\'t stick',
      onExportCsv: () {
        final buf = StringBuffer('Order #,Status,Amount (PHP),When,Reason\n');
        for (final ord in rows) {
          final tag = ord.orderNumber > 0
              ? '#${ord.orderNumber.toString().padLeft(6, '0')}'
              : ord.id;
          final reason =
              (ord.voidReason ?? '').replaceAll('"', '""');
          buf.writeln(
              '$tag,${ord.status.label},'
              '${(ord.totalCents / 100).toStringAsFixed(2)},'
              '${ord.createdAt.toLocal().toIso8601String()},'
              '"$reason"');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 18, color: YColor.success),
                const SizedBox(width: 8),
                Text('No refunds or voids in this range.',
                    style: YFont.caption()),
              ]),
            )
          : Column(children: [
              Row(children: [
                Expanded(
                  child: _mini(
                    tone: YColor.danger,
                    icon: Icons.undo,
                    label: 'Refunded',
                    value: Money(refundedCents).formatted,
                    sub:
                        '${rows.where((ord) => ord.status == o.OrderStatus.refunded).length} order(s)',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _mini(
                    tone: YColor.inkMuted,
                    icon: Icons.do_not_disturb_on_outlined,
                    label: 'Voided',
                    value:
                        '${rows.where((ord) => ord.status == o.OrderStatus.voided).length}',
                    sub: 'cancelled at the till',
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              for (final ord in rows.take(4))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (ord.status == o.OrderStatus.refunded
                                ? YColor.danger
                                : YColor.inkMuted)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ord.status.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: ord.status == o.OrderStatus.refunded
                              ? YColor.danger
                              : YColor.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ord.orderNumber > 0
                            ? '#${ord.orderNumber.toString().padLeft(6, '0')}'
                            : ord.id.substring(0, 6).toUpperCase(),
                        style:
                            YFont.bodyStrong().copyWith(fontSize: 12),
                      ),
                    ),
                    Text(Money(ord.totalCents).formatted,
                        style:
                            YFont.bodyStrong().copyWith(fontSize: 12)),
                  ]),
                ),
              if (rows.length > 4) ...[
                const SizedBox(height: 6),
                Text('+ ${rows.length - 4} more',
                    style: YFont.caption()),
              ],
            ]),
    );
  }

  Widget _mini({
    required Color tone,
    required IconData icon,
    required String label,
    required String value,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(),
                  style: YFont.caption().copyWith(
                    fontSize: 9,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w800,
                    color: tone,
                  )),
              const SizedBox(height: 2),
              Text(value,
                  style: YFont.bodyStrong()
                      .copyWith(fontSize: 16, color: tone)),
              Text(sub,
                  style: YFont.caption().copyWith(fontSize: 10)),
            ],
          ),
        ),
      ]),
    );
  }
}

Widget _empty(String message) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Center(child: Text(message, style: YFont.caption())),
  );
}

// ─────────────────────── Product lens extras ───────────────────────

/// Compact strip used by the Products lens — same shape as the
/// sales KPI strip but the metrics are item-focused (distinct SKUs
/// sold, items per ticket, etc.) rather than money.
class _ProductKpiStrip extends StatelessWidget {
  const _ProductKpiStrip({required this.data});
  final _ReportData data;

  @override
  Widget build(BuildContext context) {
    final distinct = data.topItems.length;
    final categories = data.categories.length;
    final itemsPerOrder = data.orderCount == 0
        ? '0'
        : (data.itemCount / data.orderCount).toStringAsFixed(1);
    final bestSeller = data.topItems.isEmpty
        ? '—'
        : data.topItems.first.name;
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.local_cafe_outlined,
              tone: YColor.brand,
              label: 'Distinct items sold',
              value: distinct.toString(),
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.folder_outlined,
              tone: YColor.brandDeep,
              label: 'Categories moving',
              value: categories.toString(),
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.shopping_basket_outlined,
              tone: Colors.indigo,
              label: 'Items per ticket',
              value: itemsPerOrder,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.star_outline,
              tone: Colors.teal,
              label: 'Best seller',
              value: bestSeller,
            ),
          ),
        ],
      );
    });
  }
}

// ─────────────────────── Inventory lens sections ───────────────────

/// Plain-English summary of the warehouse — "450 SKUs · ₱42,300
/// on-hand · 3 low / 1 out of stock". Replaces the sales headline
/// when the Inventory lens is active.
class _InventoryHeadline extends StatelessWidget {
  const _InventoryHeadline({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.inventory;
    final totalCents = items.fold<int>(
        0,
        (a, i) =>
            a + (i.currentStock * i.costPerUnit * 100).round());
    final low = items.where((i) => i.isLowStock && !i.isOutOfStock).length;
    final out = items.where((i) => i.isOutOfStock).length;
    final healthy = items.length - low - out;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YColor.brandDeep.withValues(alpha: 0.92),
            const Color(0xFF6E7A8A).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: YColor.brandDeep.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('INVENTORY SNAPSHOT',
                  style: YFont.caption().copyWith(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.85),
                  )),
              const SizedBox(height: 6),
              Text(
                Money(totalCents).formatted,
                style: YFont.titleLG().copyWith(
                  fontSize: 36,
                  letterSpacing: -1.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                items.isEmpty
                    ? 'No inventory tracked yet.'
                    : 'On-hand value across ${items.length} '
                        'item${items.length == 1 ? "" : "s"} · '
                        '$healthy healthy · $low low · $out out.',
                style: YFont.body().copyWith(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _InventoryKpiStrip extends StatelessWidget {
  const _InventoryKpiStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final items = state.inventory;
    final totalCents = items.fold<int>(
        0,
        (a, i) =>
            a + (i.currentStock * i.costPerUnit * 100).round());
    final low = items.where((i) => i.isLowStock && !i.isOutOfStock).length;
    final out = items.where((i) => i.isOutOfStock).length;
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.account_balance_wallet_outlined,
              tone: YColor.brand,
              label: 'On-hand value',
              value: Money(totalCents).formatted,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.inventory_2_outlined,
              tone: YColor.brandDeep,
              label: 'Tracked items',
              value: '${items.length}',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.warning_amber_rounded,
              tone: Colors.orange,
              label: 'Low stock',
              value: '$low',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.do_not_disturb_on_outlined,
              tone: YColor.danger,
              label: 'Out of stock',
              value: '$out',
            ),
          ),
        ],
      );
    });
  }
}

class _LowStockSection extends StatelessWidget {
  const _LowStockSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final rows = state.inventory
        .where((i) => i.isLowStock)
        .toList()
      ..sort((a, b) {
        // Out-of-stock first, then most-depleted (closest to zero
        // relative to threshold).
        if (a.isOutOfStock != b.isOutOfStock) {
          return a.isOutOfStock ? -1 : 1;
        }
        final aGap = (a.lowStockThreshold - a.currentStock);
        final bGap = (b.lowStockThreshold - b.currentStock);
        return bGap.compareTo(aGap);
      });
    return _SectionCard(
      title: 'Restock now',
      subtitle: rows.isEmpty
          ? 'Everything\'s healthy'
          : '${rows.length} item${rows.length == 1 ? "" : "s"} need attention',
      onExportCsv: () {
        final buf = StringBuffer(
            'Item,Status,On hand,Reorder at,Unit,Supplier\n');
        for (final i in rows) {
          final clean = i.name.replaceAll('"', '""');
          final supplier = i.supplier.replaceAll('"', '""');
          final status = i.isOutOfStock ? 'Out of stock' : 'Low';
          buf.writeln(
              '"$clean",$status,${i.currentStock.toStringAsFixed(2)},'
              '${i.lowStockThreshold.toStringAsFixed(2)},'
              '${i.displayUnit},"$supplier"');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 18, color: YColor.success),
                const SizedBox(width: 8),
                Text('All stock levels are healthy.',
                    style: YFont.caption()),
              ]),
            )
          : Column(
              children: [
                for (final i in rows.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: i.isOutOfStock
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
                            Text(i.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              i.isOutOfStock
                                  ? 'Out of stock · reorder at '
                                      '${i.lowStockThreshold.toStringAsFixed(0)}${i.displayUnit}'
                                  : '${i.currentStock.toStringAsFixed(0)}${i.displayUnit} left · '
                                      'reorder at ${i.lowStockThreshold.toStringAsFixed(0)}${i.displayUnit}',
                              style: YFont.caption()
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        i.isOutOfStock ? 'OUT' : 'LOW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: i.isOutOfStock
                              ? YColor.danger
                              : Colors.orange,
                        ),
                      ),
                    ]),
                  ),
                if (rows.length > 8) ...[
                  const SizedBox(height: 6),
                  Text('+ ${rows.length - 8} more',
                      style: YFont.caption()),
                ],
              ],
            ),
    );
  }
}

class _InventoryByCategorySection extends StatelessWidget {
  const _InventoryByCategorySection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Roll up on-hand value per category. Falls back to the
    // denormalized `category` string when the FK isn't set so
    // legacy rows still get counted.
    final agg = <String, ({int valueCents, int items})>{};
    for (final i in state.inventory) {
      final categoryName = _categoryNameFor(state, i);
      final cur = agg[categoryName];
      final value = (i.currentStock * i.costPerUnit * 100).round();
      agg[categoryName] = cur == null
          ? (valueCents: value, items: 1)
          : (valueCents: cur.valueCents + value, items: cur.items + 1);
    }
    final rows = agg.entries.toList()
      ..sort((a, b) => b.value.valueCents.compareTo(a.value.valueCents));
    final maxValue =
        rows.isEmpty ? 1 : rows.first.value.valueCents;
    return _SectionCard(
      title: 'Inventory by category',
      subtitle: 'Where the on-hand money is sitting',
      onExportCsv: () {
        final buf = StringBuffer('Category,Items,Value (PHP)\n');
        for (final r in rows) {
          final clean = r.key.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${r.value.items},'
              '${(r.value.valueCents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? _empty('Add an item to inventory to see the breakdown.')
          : Column(
              children: [
                for (final r in rows.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: YColor.brandTint.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.folder_outlined,
                            size: 16, color: YColor.brandDeep),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: r.value.valueCents / maxValue,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: const AlwaysStoppedAnimation(
                                    YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 84,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(r.value.valueCents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text('${r.value.items} items',
                                style: YFont.caption()
                                    .copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }

  String _categoryNameFor(AppState state, InventoryItem i) {
    if (i.categoryId != null) {
      for (final c in state.inventoryCategories) {
        if (c.id == i.categoryId) return c.name;
      }
    }
    return i.category.isEmpty ? 'Uncategorised' : i.category;
  }
}

// ─────────────────────── Payroll lens sections ────────────────────

/// Big headline card summarising the most recent payroll run + a
/// total of all unpaid liabilities so the owner knows what's owed
/// at a glance.
class _PayrollHeadline extends StatelessWidget {
  const _PayrollHeadline({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final runs = state.payrollRuns;
    final unpaidCents = runs
        .where((r) => r.status != PayrollStatus.paid)
        .fold<int>(0, (a, r) => a + (r.totalNet * 100).round());
    final paidThisMonth = _paidThisMonthCents(runs);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YColor.brandDeep.withValues(alpha: 0.92),
            const Color(0xFF7C8F65).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: YColor.brandDeep.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PAYROLL SNAPSHOT',
                  style: YFont.caption().copyWith(
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.85),
                  )),
              const SizedBox(height: 6),
              Text(
                Money(unpaidCents).formatted,
                style: YFont.titleLG().copyWith(
                  fontSize: 36,
                  letterSpacing: -1.0,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                runs.isEmpty
                    ? 'No payroll runs yet. Open the Payroll page to '
                        'generate your first one.'
                    : 'Unpaid liability across ${runs.length} run'
                        '${runs.length == 1 ? "" : "s"} · '
                        'paid this month: ${Money(paidThisMonth).formatted}.',
                style: YFont.body().copyWith(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  int _paidThisMonthCents(List<PayrollRun> runs) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    return runs
        .where((r) =>
            r.status == PayrollStatus.paid &&
            r.paidAt != null &&
            !r.paidAt!.isBefore(monthStart))
        .fold<int>(0, (a, r) => a + (r.totalNet * 100).round());
  }
}

class _PayrollKpiStrip extends StatelessWidget {
  const _PayrollKpiStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final runs = state.payrollRuns;
    final draftCount = runs
        .where((r) => r.status == PayrollStatus.draft)
        .length;
    final paidCount =
        runs.where((r) => r.status == PayrollStatus.paid).length;
    final totalGross =
        runs.fold<int>(0, (a, r) => a + (r.totalGross * 100).round());
    final totalDeductions = runs.fold<int>(
        0, (a, r) => a + (r.totalDeductions * 100).round());

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.payments_outlined,
              tone: YColor.brand,
              label: 'Total gross',
              value: Money(totalGross).formatted,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.remove_circle_outline,
              tone: YColor.danger,
              label: 'Total deductions',
              value: Money(totalDeductions).formatted,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.edit_note,
              tone: Colors.orange,
              label: 'Draft runs',
              value: '$draftCount',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.check_circle_outline,
              tone: YColor.success,
              label: 'Paid runs',
              value: '$paidCount',
            ),
          ),
        ],
      );
    });
  }
}

class _PayrollRunsListSection extends StatelessWidget {
  const _PayrollRunsListSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final runs = state.payrollRuns;
    return _SectionCard(
      title: 'Recent payroll runs',
      subtitle: runs.isEmpty
          ? 'Nothing to show yet'
          : '${runs.length} run${runs.length == 1 ? "" : "s"} on record',
      onExportCsv: () {
        final buf = StringBuffer(
            'Period start,Period end,Kind,Status,Gross (PHP),'
            'Deductions (PHP),Net (PHP),Paid at\n');
        for (final r in runs) {
          buf.writeln(
              '${_toDate(r.periodStart)},${_toDate(r.periodEnd)},'
              '${r.kind.label},${r.status.label},'
              '${r.totalGross.toStringAsFixed(2)},'
              '${r.totalDeductions.toStringAsFixed(2)},'
              '${r.totalNet.toStringAsFixed(2)},'
              '${r.paidAt == null ? "" : r.paidAt!.toIso8601String()}');
        }
        return buf.toString();
      },
      child: runs.isEmpty
          ? _empty('Generate a payroll run from the Payroll page.')
          : Column(
              children: [
                for (final r in runs.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusTone(r.status)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          r.status.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: _statusTone(r.status),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_toDate(r.periodStart)} → '
                              '${_toDate(r.periodEnd)}',
                              style: YFont.bodyStrong()
                                  .copyWith(fontSize: 13),
                            ),
                            Text(
                              '${r.kind.label} · ${r.slips.length} '
                              'employee${r.slips.length == 1 ? "" : "s"}',
                              style: YFont.caption()
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Money((r.totalNet * 100).round()).formatted,
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 13,
                          color: YColor.brand,
                        ),
                      ),
                    ]),
                  ),
                if (runs.length > 8) ...[
                  const SizedBox(height: 6),
                  Text('+ ${runs.length - 8} more',
                      style: YFont.caption()),
                ],
              ],
            ),
    );
  }

  Color _statusTone(PayrollStatus s) => switch (s) {
        PayrollStatus.draft => Colors.orange,
        PayrollStatus.finalized => YColor.brandDeep,
        PayrollStatus.paid => YColor.success,
      };

  String _toDate(DateTime d) =>
      '${_fmtShort(d)}, ${d.year}';
}

class _PayrollByEmployeeSection extends StatelessWidget {
  const _PayrollByEmployeeSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Aggregate net pay per employee across every run.
    final agg = <String, ({int cents, int slips})>{};
    for (final r in state.payrollRuns) {
      for (final s in r.slips) {
        final name = s.employeeName;
        final net = (s.netFor(r.kind) * 100).round();
        final cur = agg[name];
        agg[name] = cur == null
            ? (cents: net, slips: 1)
            : (cents: cur.cents + net, slips: cur.slips + 1);
      }
    }
    final rows = agg.entries.toList()
      ..sort((a, b) => b.value.cents.compareTo(a.value.cents));
    final top = rows.take(8).toList();
    final maxValue = top.isEmpty ? 1 : top.first.value.cents;
    return _SectionCard(
      title: 'Net pay by employee',
      subtitle: 'All payroll runs combined',
      onExportCsv: () {
        final buf = StringBuffer('Employee,Slips,Total net (PHP)\n');
        for (final r in rows) {
          final clean = r.key.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${r.value.slips},'
              '${(r.value.cents / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: top.isEmpty
          ? _empty('No payslips yet.')
          : Column(
              children: [
                for (final r in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: r.value.cents / maxValue,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: const AlwaysStoppedAnimation(
                                    YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 86,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Money(r.value.cents).formatted,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text('${r.value.slips} slip(s)',
                                style: YFont.caption()
                                    .copyWith(fontSize: 11)),
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

class _PayrollDeductionsSection extends StatelessWidget {
  const _PayrollDeductionsSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Per-employee total deductions across all runs.
    final agg = <String, int>{};
    for (final r in state.payrollRuns) {
      for (final s in r.slips) {
        if (s.deductions <= 0) continue;
        agg[s.employeeName] =
            (agg[s.employeeName] ?? 0) + (s.deductions * 100).round();
      }
    }
    final rows = agg.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<int>(0, (a, e) => a + e.value);
    return _SectionCard(
      title: 'Deductions hotspot',
      subtitle: total == 0
          ? 'No deductions recorded'
          : 'Where the deductions stack up',
      onExportCsv: () {
        final buf = StringBuffer('Employee,Total deductions (PHP)\n');
        for (final r in rows) {
          final clean = r.key.replaceAll('"', '""');
          buf.writeln(
              '"$clean",${(r.value / 100).toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? _empty('Clean sheet — no deductions taken.')
          : Column(
              children: [
                for (final r in rows.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      const Icon(Icons.remove_circle_outline,
                          size: 14, color: YColor.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(r.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.bodyStrong()
                                .copyWith(fontSize: 13)),
                      ),
                      Text(Money(r.value).formatted,
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 13,
                            color: YColor.danger,
                          )),
                    ]),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────── Staff lens sections ──────────────────────

class _StaffHeadline extends StatelessWidget {
  const _StaffHeadline({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final emps = state.employees;
    final active = emps.where((e) => e.status == EmployeeStatus.active).length;
    final onLeave =
        emps.where((e) => e.status == EmployeeStatus.onLeave).length;
    final terminated =
        emps.where((e) => e.status == EmployeeStatus.terminated).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            YColor.brand.withValues(alpha: 0.92),
            const Color(0xFF8A5A8A).withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: YColor.brand.withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR TEAM',
              style: YFont.caption().copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.85),
              )),
          const SizedBox(height: 6),
          Text(
            '${emps.length} '
            'staff member${emps.length == 1 ? "" : "s"}',
            style: YFont.titleLG().copyWith(
              fontSize: 32,
              letterSpacing: -1.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$active active · $onLeave on leave · $terminated archived',
            style: YFont.body().copyWith(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffKpiStrip extends StatelessWidget {
  const _StaffKpiStrip({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final emps = state.employees;
    final hourly = emps
        .where((e) => e.compensationType == CompensationType.hourly)
        .length;
    final daily = emps
        .where((e) => e.compensationType == CompensationType.daily)
        .length;
    final salaried = emps
        .where((e) => e.compensationType == CompensationType.salaried)
        .length;
    final monthlyPayrollEstimate = emps
        .where((e) => e.status == EmployeeStatus.active)
        .fold<double>(0, (a, e) => a + _monthlyEstimate(e));
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.account_balance_wallet_outlined,
              tone: YColor.brand,
              label: 'Est. monthly payroll',
              value:
                  Money((monthlyPayrollEstimate * 100).round()).formatted,
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.schedule,
              tone: YColor.brandDeep,
              label: 'Hourly',
              value: '$hourly',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.today,
              tone: Colors.teal,
              label: 'Daily',
              value: '$daily',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.calendar_month_outlined,
              tone: Colors.indigo,
              label: 'Salaried',
              value: '$salaried',
            ),
          ),
        ],
      );
    });
  }

  /// Rough monthly cost per employee — assumes 22 working days @ 8h
  /// for hourly / daily so the owner gets a usable estimate even
  /// before any actual hours are logged.
  double _monthlyEstimate(Employee e) => switch (e.compensationType) {
        CompensationType.hourly => e.hourlyRate * 8 * 22,
        CompensationType.daily => e.dailyRate * 22,
        CompensationType.salaried => e.monthlySalary,
      };
}

class _StaffRosterSection extends StatelessWidget {
  const _StaffRosterSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final emps = state.employees.toList()
      ..sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return _SectionCard(
      title: 'Roster',
      subtitle:
          '${emps.length} member${emps.length == 1 ? "" : "s"} · sorted A→Z',
      onExportCsv: () {
        final buf = StringBuffer(
            'Name,Role,Status,Compensation,Rate,Hire date,Phone,Email\n');
        for (final e in emps) {
          final clean = e.name.replaceAll('"', '""');
          final role = e.role.replaceAll('"', '""');
          final rate = switch (e.compensationType) {
            CompensationType.hourly => e.hourlyRate.toStringAsFixed(2),
            CompensationType.daily => e.dailyRate.toStringAsFixed(2),
            CompensationType.salaried =>
              e.monthlySalary.toStringAsFixed(2),
          };
          buf.writeln(
              '"$clean","$role",${e.status.label},'
              '${e.compensationType.label},$rate,'
              '${e.hireDate.toIso8601String().substring(0, 10)},'
              '${e.phone},${e.email}');
        }
        return buf.toString();
      },
      child: emps.isEmpty
          ? _empty('No employees yet — add staff in Maintenance → Staff.')
          : Column(
              children: [
                for (final e in emps.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: YColor.brandTint.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          e.name.isEmpty
                              ? '·'
                              : e.name[0].toUpperCase(),
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 12,
                            color: YColor.brandDeep,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text(
                              '${e.role.isEmpty ? "Staff" : e.role} · '
                              '${e.compensationType.label}',
                              style: YFont.caption()
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      _statusPill(e.status),
                    ]),
                  ),
                if (emps.length > 10) ...[
                  const SizedBox(height: 6),
                  Text('+ ${emps.length - 10} more',
                      style: YFont.caption()),
                ],
              ],
            ),
    );
  }

  Widget _statusPill(EmployeeStatus s) {
    final tone = switch (s) {
      EmployeeStatus.active => YColor.success,
      EmployeeStatus.onLeave => Colors.orange,
      EmployeeStatus.terminated => YColor.inkMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: tone,
        ),
      ),
    );
  }
}

/// Lightweight placeholder shown when the staff lens is open but
/// orders haven't been loaded — points the owner at the Sales lens
/// for the cashier leaderboard without leaving the page.
class _StaffComingSoonCard extends StatelessWidget {
  const _StaffComingSoonCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Cashier leaderboard',
      subtitle: 'Best seller this period',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const Icon(Icons.info_outline,
              color: YColor.inkMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: YFont.caption())),
        ]),
      ),
    );
  }
}

// ─────────────────────── Attendance lens sections ─────────────────

class _AttendanceHeadline extends StatelessWidget {
  const _AttendanceHeadline({required this.state, required this.range});
  final AppState state;
  final _DateRange range;

  @override
  Widget build(BuildContext context) {
    final totalHours = _hoursIn(state, range);
    final activeStaff = state.employees
        .where((e) => e.status == EmployeeStatus.active)
        .length;
    final daysInRange = range.span.inDays;
    final perDay =
        daysInRange == 0 ? 0.0 : totalHours / daysInRange;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF3D5A7A).withValues(alpha: 0.92),
            YColor.brandDeep.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3D5A7A).withValues(alpha: 0.25),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ATTENDANCE · ${range.label.toUpperCase()}',
              style: YFont.caption().copyWith(
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.85),
              )),
          const SizedBox(height: 6),
          Text(
            '${totalHours.toStringAsFixed(1)} hrs',
            style: YFont.titleLG().copyWith(
              fontSize: 36,
              letterSpacing: -1.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            totalHours == 0
                ? 'No hours logged yet in this range.'
                : '$activeStaff active staff · '
                    '${perDay.toStringAsFixed(1)} hrs/day average.',
            style: YFont.body().copyWith(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceKpiStrip extends StatelessWidget {
  const _AttendanceKpiStrip(
      {required this.state, required this.range});
  final AppState state;
  final _DateRange range;

  @override
  Widget build(BuildContext context) {
    final entries = _entriesIn(state, range);
    final totalHours =
        entries.fold<double>(0, (a, e) => a + e.hours);
    final shifts = entries.length;
    final uniqueStaff =
        entries.map((e) => e.employeeId).toSet().length;
    final avgPerShift =
        shifts == 0 ? 0.0 : totalHours / shifts;
    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 760 ? 4 : (c.maxWidth > 480 ? 2 : 1);
      const gap = 12.0;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.schedule,
              tone: YColor.brand,
              label: 'Total hours',
              value: totalHours.toStringAsFixed(1),
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.event_note,
              tone: YColor.brandDeep,
              label: 'Shifts logged',
              value: '$shifts',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.people_outline,
              tone: Colors.teal,
              label: 'Staff worked',
              value: '$uniqueStaff',
            ),
          ),
          SizedBox(
            width: w,
            child: _KpiBox(
              icon: Icons.timelapse,
              tone: Colors.indigo,
              label: 'Avg shift',
              value: '${avgPerShift.toStringAsFixed(1)} h',
            ),
          ),
        ],
      );
    });
  }
}

class _AttendanceLeaderboardSection extends StatelessWidget {
  const _AttendanceLeaderboardSection(
      {required this.state, required this.range});
  final AppState state;
  final _DateRange range;

  @override
  Widget build(BuildContext context) {
    final entries = _entriesIn(state, range);
    final agg = <String, double>{};
    for (final e in entries) {
      agg[e.employeeId] = (agg[e.employeeId] ?? 0) + e.hours;
    }
    final empById = {for (final e in state.employees) e.id: e};
    final rows = agg.entries
        .map((e) => (
              name: empById[e.key]?.name ?? 'Unknown',
              hours: e.value,
            ))
        .toList()
      ..sort((a, b) => b.hours.compareTo(a.hours));
    final maxHours = rows.isEmpty ? 1.0 : rows.first.hours;
    return _SectionCard(
      title: 'Hours by employee',
      subtitle: 'Within ${range.label}',
      onExportCsv: () {
        final buf = StringBuffer('Employee,Hours\n');
        for (final r in rows) {
          final clean = r.name.replaceAll('"', '""');
          buf.writeln('"$clean",${r.hours.toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: rows.isEmpty
          ? _empty('No hours logged in this period yet.')
          : Column(
              children: [
                for (var i = 0; i < rows.take(8).length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? YColor.brand
                              : YColor.brandTint,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 11,
                            color: i == 0
                                ? Colors.white
                                : YColor.brandDeep,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rows[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: rows[i].hours / maxHours,
                                minHeight: 5,
                                backgroundColor: YColor.surface3,
                                valueColor: const AlwaysStoppedAnimation(
                                    YColor.brand),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${rows[i].hours.toStringAsFixed(1)} h',
                          textAlign: TextAlign.end,
                          style:
                              YFont.bodyStrong().copyWith(fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class _AttendanceByDaySection extends StatelessWidget {
  const _AttendanceByDaySection(
      {required this.state, required this.range});
  final AppState state;
  final _DateRange range;

  @override
  Widget build(BuildContext context) {
    final entries = _entriesIn(state, range);
    final buckets = <DateTime, double>{};
    DateTime cursor = range.start;
    while (cursor.isBefore(range.end)) {
      buckets[DateTime(cursor.year, cursor.month, cursor.day)] = 0;
      cursor = cursor.add(const Duration(days: 1));
    }
    for (final e in entries) {
      final key = DateTime(e.date.year, e.date.month, e.date.day);
      buckets[key] = (buckets[key] ?? 0) + e.hours;
    }
    final rows = buckets.entries.toList();
    final maxHours =
        rows.fold<double>(0, (a, e) => e.value > a ? e.value : a);
    return _SectionCard(
      title: 'Hours by day',
      subtitle: 'Spot the heavy days',
      onExportCsv: () {
        final buf = StringBuffer('Date,Hours\n');
        for (final r in rows) {
          buf.writeln(
              '${r.key.toIso8601String().substring(0, 10)},'
              '${r.value.toStringAsFixed(2)}');
        }
        return buf.toString();
      },
      child: SizedBox(
        height: 160,
        child: maxHours == 0
            ? _empty('No hours yet — log shifts on the Payroll page.')
            : BarChart(
                BarChartData(
                  maxY: maxHours * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval:
                            (rows.length / 6).clamp(1, 10).toDouble(),
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= rows.length) {
                            return const SizedBox.shrink();
                          }
                          final d = rows[i].key;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              rows.length <= 7
                                  ? const [
                                      'M', 'T', 'W', 'T', 'F', 'S', 'S'
                                    ][d.weekday - 1]
                                  : '${d.day}',
                              style: YFont.caption()
                                  .copyWith(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < rows.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: rows[i].value,
                          width: rows.length <= 14 ? 14 : 8,
                          color: YColor.brand,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            topRight: Radius.circular(3),
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Returns every time entry whose date falls inside [range], inclusive
/// of `start` and exclusive of `end` (same semantics as the rest of
/// the report).
List<TimeEntry> _entriesIn(AppState state, _DateRange range) {
  return state.timeEntries
      .where((e) =>
          !e.date.isBefore(range.start) && e.date.isBefore(range.end))
      .toList();
}

double _hoursIn(AppState state, _DateRange range) =>
    _entriesIn(state, range).fold(0.0, (a, e) => a + e.hours);

/// Top items by on-hand value — a quick "where's most of my money
/// sitting in stock?" view, useful for spotting overstocks.
class _InventoryValueListSection extends StatelessWidget {
  const _InventoryValueListSection({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final rows = state.inventory.toList()
      ..sort((a, b) {
        final av = a.currentStock * a.costPerUnit;
        final bv = b.currentStock * b.costPerUnit;
        return bv.compareTo(av);
      });
    final top = rows.take(10).toList();
    return _SectionCard(
      title: 'Most stock value',
      subtitle: 'Items tying up the most working capital',
      onExportCsv: () {
        final buf = StringBuffer(
            'Item,On hand,Unit,Cost per unit (PHP),Value (PHP),Supplier\n');
        for (final i in rows) {
          final clean = i.name.replaceAll('"', '""');
          final supplier = i.supplier.replaceAll('"', '""');
          final value = i.currentStock * i.costPerUnit;
          buf.writeln(
              '"$clean",${i.currentStock.toStringAsFixed(2)},'
              '${i.displayUnit},${i.costPerUnit.toStringAsFixed(2)},'
              '${value.toStringAsFixed(2)},"$supplier"');
        }
        return buf.toString();
      },
      child: top.isEmpty
          ? _empty('No inventory tracked yet.')
          : Column(
              children: [
                for (final i in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: YColor.brandTint.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.inventory_2_outlined,
                            size: 14, color: YColor.brandDeep),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                            Text(
                              '${i.currentStock.toStringAsFixed(0)}${i.displayUnit} '
                              '@ ₱${i.costPerUnit.toStringAsFixed(2)}/${i.displayUnit}',
                              style: YFont.caption()
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Money(((i.currentStock * i.costPerUnit) * 100).round())
                            .formatted,
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 13,
                          color: YColor.brand,
                        ),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}
