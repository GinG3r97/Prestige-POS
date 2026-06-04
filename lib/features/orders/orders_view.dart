import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../printing/print_jobs.dart';
import '../sell/shift_bar.dart';
import '../widgets/push_toast.dart';
import '../../design_system/responsive.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/mock_history.dart';
import '../../models/money.dart';
import '../../models/order.dart' as db;
import 'date_range_sheet.dart';
import 'void_refund_dialog.dart';

enum _DateFilter { today, week, all, day }

class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  String _query = '';
  _DateFilter _date = _DateFilter.today;
  DateTimeRange? _pickedRange;
  String? _selectedId;
  PaymentMethod? _method;

  // Cache the DB->MockOrder adaptation so it only re-runs when the underlying
  // order list changes — not on every keystroke / filter rebuild.
  List<db.Order>? _adaptedSource;
  List<MockOrder> _adaptedCache = const [];

  @override
  void initState() {
    super.initState();
    // Pull the latest week of orders from Supabase on first open. Each
    // checkout also calls refreshOrders, so this just covers the
    // session-restored case where we haven't fetched yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Real DB-backed orders, adapted to the UI's existing MockOrder shape so
    // the 700-line layout doesn't need to be rewritten this turn. Re-adapt
    // only when the source list actually changes (not per keystroke).
    if (!identical(state.recentOrders, _adaptedSource)) {
      _adaptedSource = state.recentOrders;
      _adaptedCache = state.recentOrders.map(_adaptToMock).toList();
    }
    final allOrders = _adaptedCache;
    // Cashier scoping: a non-owner sees ONLY the orders they rang up. The
    // owner (or any owner-session) sees everything.
    final myName = state.currentStaff?.name;
    final all = state.isOwnerSession
        ? allOrders
        : allOrders.where((o) => o.employeeName == myName).toList();

    final filtered = _filter(all);
    final selected = _selectedId == null
        ? (filtered.isNotEmpty ? filtered.first : null)
        : filtered.where((o) => o.id == _selectedId).firstOrNull;

    return Container(
      color: YColor.surface2,
      child: Row(
        children: [
          // Left pane — list
          SizedBox(
            width: panelWidth(context, fraction: 0.36, min: 320, max: 460),
            child: Container(
              color: YColor.surface1,
              child: Column(
                children: [
                  _header(filtered, all),
                  _filterRow(),
                  _summaryBar(filtered),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(36),
                              child: Text('No orders match.',
                                  style: YFont.caption()),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Container(
                                height: 0.5,
                                color: YColor.hairline),
                            itemBuilder: (_, i) {
                              final o = filtered[i];
                              return _OrderListRow(
                                order: o,
                                selected: selected?.id == o.id,
                                onTap: () =>
                                    setState(() => _selectedId = o.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 0.5, color: YColor.hairline),
          // Right pane — detail
          Expanded(
            child: selected == null
                ? _empty()
                : _OrderDetail(order: selected),
          ),
        ],
      ),
    );
  }

  List<MockOrder> _filter(List<MockOrder> all) {
    final now = DateTime.now();
    var list = all;
    switch (_date) {
      case _DateFilter.today:
        list = list
            .where((o) =>
                o.placedAt.year == now.year &&
                o.placedAt.month == now.month &&
                o.placedAt.day == now.day)
            .toList();
        break;
      case _DateFilter.week:
        final start = now.subtract(const Duration(days: 6));
        list = list
            .where((o) => o.placedAt.isAfter(
                DateTime(start.year, start.month, start.day)))
            .toList();
        break;
      case _DateFilter.all:
        break;
      case _DateFilter.day:
        final r = _pickedRange;
        if (r != null) {
          final start = DateTime(r.start.year, r.start.month, r.start.day);
          // End is inclusive — extend to the end of that day.
          final end = DateTime(r.end.year, r.end.month, r.end.day)
              .add(const Duration(days: 1));
          list = list
              .where((o) =>
                  !o.placedAt.isBefore(start) && o.placedAt.isBefore(end))
              .toList();
        }
        break;
    }
    if (_method != null) {
      list = list.where((o) => o.method == _method).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((o) =>
              o.id.toLowerCase().contains(q) ||
              o.employeeName.toLowerCase().contains(q) ||
              o.lines.any((l) => l.name.toLowerCase().contains(q)))
          .toList();
    }
    return list;
  }

  Widget _header(List<MockOrder> filtered, List<MockOrder> all) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Orders',
                style: YFont.titleLG().copyWith(fontSize: 22)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => showShiftsSheet(context),
              icon: const Icon(Icons.summarize_outlined, size: 16),
              label: const Text('Shifts'),
              style: OutlinedButton.styleFrom(
                foregroundColor: YColor.brandDeep,
                side: const BorderSide(color: YColor.hairline),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: 'Search order #, item, staff…',
              hintStyle: YFont.body().copyWith(color: YColor.inkSubtle),
              filled: true,
              fillColor: YColor.surface2,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(List<MockOrder> filtered) {
    final total =
        filtered.fold(Money.zero, (acc, o) => acc + o.total);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: YColor.brandTint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline),
      ),
      child: Row(
        children: [
          // Left — order count
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Orders: ',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              TextSpan(
                  text: '${filtered.length}',
                  style: YFont.bodyStrong().copyWith(fontSize: 14)),
            ]),
          ),
          const Spacer(),
          // Right — total sales
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'Total Sales: ',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              TextSpan(
                  text: total.formatted,
                  style: YFont.bodyStrong()
                      .copyWith(fontSize: 14, color: YColor.brandDeep)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        children: [
          _dateChip('Today', _DateFilter.today),
          _pickDateChip(),
          Container(
            width: 1,
            height: 22,
            color: YColor.hairline,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          _methodDropdown(),
        ],
      ),
    );
  }

  Widget _pickDateChip() {
    final selected = _date == _DateFilter.day && _pickedRange != null;
    final label = selected
        ? _fmtRangeLabel(_pickedRange!)
        : 'Pick a date';
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined,
                size: 13, color: selected ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 6),
            Text(label,
                style: YFont.bodyStrong().copyWith(
                    fontSize: 12,
                    color: selected ? Colors.white : YColor.ink)),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDateRangeSheet(context, initial: _pickedRange);
    if (picked != null) {
      setState(() {
        _pickedRange = picked;
        _date = _DateFilter.day;
      });
    }
  }

  Widget _methodDropdown() {
    final label = _method?.label ?? 'Any method';
    return PopupMenuButton<PaymentMethod?>(
      position: PopupMenuPosition.under,
      color: YColor.surface1,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: YColor.hairline),
      ),
      onSelected: (m) => setState(() => _method = m),
      itemBuilder: (_) => [
        _methodItem(null, 'Any method'),
        for (final m in PaymentMethod.values) _methodItem(m, m.label),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _method != null ? YColor.brandDeep : YColor.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.payments_outlined,
              size: 13,
              color: _method != null ? Colors.white : YColor.brandDeep),
          const SizedBox(width: 6),
          Text(label,
              style: YFont.bodyStrong().copyWith(
                  fontSize: 12,
                  color: _method != null ? Colors.white : YColor.ink)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more,
              size: 14,
              color: _method != null ? Colors.white : YColor.inkMuted),
        ]),
      ),
    );
  }

  PopupMenuItem<PaymentMethod?> _methodItem(PaymentMethod? m, String label) {
    final selected = _method == m;
    return PopupMenuItem<PaymentMethod?>(
      value: m,
      height: 42,
      child: Row(children: [
        Text(label,
            style: YFont.bodyStrong().copyWith(
                color: selected ? YColor.brandDeep : YColor.ink)),
        const Spacer(),
        if (selected)
          const Icon(Icons.check, size: 16, color: YColor.brand),
      ]),
    );
  }

  String _fmtDayLabel(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtRangeLabel(DateTimeRange r) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final s = r.start, e = r.end;
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) return _fmtDayLabel(s);
    // "Jun 1 – Jun 7" (drop the year unless the span crosses years).
    final sameYear = s.year == e.year;
    final left = '${m[s.month - 1]} ${s.day}${sameYear ? '' : ', ${s.year}'}';
    final right = '${m[e.month - 1]} ${e.day}, ${e.year}';
    return '$left – $right';
  }

  Widget _dateChip(String label, _DateFilter value) {
    final selected = _date == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _date = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 12,
              color: selected ? Colors.white : YColor.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: YColor.surface3,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 38, color: YColor.inkMuted),
          ),
          const SizedBox(height: 14),
          Text('Pick an order',
              style: YFont.titleMD().copyWith(color: YColor.inkMuted)),
          const SizedBox(height: 4),
          Text('Select one on the left to see the receipt.',
              style: YFont.caption()),
        ],
      ),
    );
  }
}

class _OrderListRow extends StatelessWidget {
  const _OrderListRow({
    required this.order,
    required this.selected,
    required this.onTap,
  });
  final MockOrder order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (order.status) {
      OrderStatus.completed => YColor.success,
      OrderStatus.refunded => YColor.danger,
      OrderStatus.voided => YColor.inkMuted,
    };
    return Material(
      color: selected
          ? YColor.brandTint.withValues(alpha: 0.4)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: tone,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        _shortOrderId(order.id),
                        style: YFont.bodyStrong(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (order.status != OrderStatus.completed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          order.status.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: tone,
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${order.itemCount} items · ${order.method.label} · ${_fmtDateTime(order.placedAt)}',
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            Text(order.total.formatted, style: YFont.bodyStrong()),
          ]),
        ),
      ),
    );
  }
}

class _OrderDetail extends StatelessWidget {
  const _OrderDetail({required this.order});
  final MockOrder order;

  @override
  Widget build(BuildContext context) {
    // Three-band layout: pinned hero at top, scrollable line items in the
    // middle, pinned actions at the bottom. The whole pane is centred to
    // the same 720px column the SingleChildScrollView used to use.
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero — sticky top
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [YColor.brandTint, YColor.surface1],
                  ),
                  borderRadius: BorderRadius.circular(YRadius.lg),
                  border: Border.all(
                      color: YColor.hairline.withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(
                                _shortOrderId(order.id),
                                style: YFont.titleLG().copyWith(
                                    fontSize: 26, letterSpacing: -0.4),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _statusPill(order.status),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            '${_fmtFullDate(order.placedAt)} · ${order.branchName}',
                            style: YFont.body()
                                .copyWith(color: YColor.inkMuted),
                          ),
                          const SizedBox(height: 10),
                          Row(children: [
                            Container(
                              width: 30,
                              height: 30,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: YColor.brandTint,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person_outline,
                                  size: 17, color: YColor.brandDeep),
                            ),
                            const SizedBox(width: 8),
                            Text(order.employeeName,
                                style: YFont.bodyStrong()
                                    .copyWith(fontSize: 13)),
                          ]),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Total',
                            style: YFont.caption().copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: YColor.brandDeep,
                            )),
                        Text(
                          order.total.formatted,
                          style: YFont.titleLG().copyWith(
                            fontSize: 32,
                            color: YColor.brand,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(order.method.label,
                            style: YFont.caption()),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // Actions. Corrections (Void / Refund) get their own row so
              // labels never crowd; receipt actions sit below. Equal-width
              // Expanded buttons keep every size consistent and fit an
              // iPad-mini-width detail pane without overflow.
              if (order.status == OrderStatus.completed) ...[
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        onPressed: () => showReverseOrderDialog(
                          context,
                          kind: ReverseKind.voidOrder,
                          orderId: order.id,
                          orderLabel: _shortOrderId(order.id),
                          total: order.total,
                        ),
                        icon: Icons.block_outlined,
                        label: 'Void',
                        foreground: YColor.inkMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionButton(
                        onPressed: () => showReverseOrderDialog(
                          context,
                          kind: ReverseKind.refund,
                          orderId: order.id,
                          orderLabel: _shortOrderId(order.id),
                          total: order.total,
                        ),
                        icon: Icons.undo_outlined,
                        label: 'Refund',
                        foreground: YColor.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      onPressed: () => _reprintReceipt(context, order.id),
                      icon: Icons.print_outlined,
                      label: 'Reprint receipt',
                      foreground: YColor.ink,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.email_outlined, size: 16),
                      label: const Text('Email receipt',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YColor.brand,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Lines — scrollable middle band fills remaining space.
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                decoration: BoxDecoration(
                  color: YColor.surface1,
                  borderRadius: BorderRadius.circular(YRadius.lg),
                  border: Border.all(
                      color: YColor.hairline.withValues(alpha: 0.6)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                      child: Row(children: [
                        const Icon(Icons.receipt_long_outlined,
                            size: 14, color: YColor.brandDeep),
                        const SizedBox(width: 8),
                        Text('LINE ITEMS',
                            style: YFont.caption().copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: YColor.brandDeep,
                            )),
                      ]),
                    ),
                    Container(
                        height: 0.5,
                        color: YColor.hairline,
                        margin: const EdgeInsets.symmetric(horizontal: 16)),
                    for (var i = 0; i < order.lines.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Builder(builder: (context) {
                          final line = order.lines[i];
                          final dim = line.reversed;
                          final canReverse = order.status ==
                                  OrderStatus.completed &&
                              line.lineId != null &&
                              !line.reversed;
                          final strike = dim
                              ? TextDecoration.lineThrough
                              : null;
                          return Row(children: [
                            Opacity(
                              opacity: dim ? 0.5 : 1,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: YColor.brandTint
                                      .withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _lineCategoryIcon(context, line),
                                  size: 20,
                                  color: YColor.brandDeep,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Flexible(
                                      child: Text(line.name,
                                          style: YFont.bodyStrong().copyWith(
                                            decoration: strike,
                                            color: dim
                                                ? YColor.inkMuted
                                                : null,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                    if (line.reversed) ...[
                                      const SizedBox(width: 6),
                                      _lineReversedBadge(
                                          line.reversedLabel ?? 'Voided'),
                                    ],
                                  ]),
                                  if (line.subtitle != null)
                                    Text(line.subtitle!,
                                        style: YFont.caption()),
                                ],
                              ),
                            ),
                            Text('×${line.quantity}',
                                style: YFont.caption()),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 80,
                              child: Text(
                                line.lineTotal.formatted,
                                textAlign: TextAlign.right,
                                style: YFont.bodyStrong().copyWith(
                                  decoration: strike,
                                  color: dim ? YColor.inkMuted : null,
                                ),
                              ),
                            ),
                            if (canReverse)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_horiz,
                                    size: 18, color: YColor.inkMuted),
                                padding: EdgeInsets.zero,
                                tooltip: 'Fix this item',
                                color: YColor.surface1,
                                elevation: 10,
                                position: PopupMenuPosition.under,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: const BorderSide(
                                      color: YColor.hairline),
                                ),
                                onSelected: (v) => showReverseOrderDialog(
                                  context,
                                  kind: v == 'refund'
                                      ? ReverseKind.refund
                                      : ReverseKind.voidOrder,
                                  orderId: order.id,
                                  orderLabel: _shortOrderId(order.id),
                                  total: line.lineTotal,
                                  orderLineId: line.lineId,
                                  itemName: line.name,
                                ),
                                itemBuilder: (_) => [
                                  _lineMenuItem(
                                    value: 'void',
                                    icon: Icons.block_outlined,
                                    tone: YColor.inkMuted,
                                    title: 'Void item',
                                    subtitle: 'Cancel — treat as not sold',
                                  ),
                                  const PopupMenuDivider(height: 1),
                                  _lineMenuItem(
                                    value: 'refund',
                                    icon: Icons.undo_outlined,
                                    tone: YColor.danger,
                                    title: 'Refund item',
                                    subtitle: 'Return the money',
                                  ),
                                ],
                              )
                            else
                              const SizedBox(width: 8),
                          ]);
                        }),
                      ),
                      if (i != order.lines.length - 1)
                        Container(
                            height: 0.5,
                            color: YColor.hairline,
                            margin:
                                const EdgeInsets.symmetric(horizontal: 16)),
                    ],
                    Container(
                        height: 0.5,
                        color: YColor.hairline,
                        margin: const EdgeInsets.symmetric(horizontal: 16)),
                    // Totals breakdown
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(children: [
                        _totalRow('Subtotal', order.subtotal.formatted),
                        if (order.discount.centavos > 0)
                          _totalRow(
                              'Discount', '−${order.discount.formatted}',
                              tone: YColor.success),
                        _totalRow('VAT (incl.)', order.vat.formatted,
                            faded: true),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text('Total',
                              style: YFont.titleMD()
                                  .copyWith(fontSize: 16)),
                          const Spacer(),
                          Text(order.total.formatted,
                              style: YFont.titleMD().copyWith(
                                  fontSize: 18, color: YColor.brand)),
                        ]),
                      ]),
                    ),
                  ],
                ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(OrderStatus s) {
    final (color, label) = switch (s) {
      OrderStatus.completed => (YColor.success, 'Completed'),
      OrderStatus.refunded => (YColor.danger, 'Refunded'),
      OrderStatus.voided => (YColor.inkMuted, 'Voided'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value,
      {bool faded = false, Color? tone}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label,
            style: YFont.body().copyWith(
              color: faded ? YColor.inkMuted : YColor.ink,
            )),
        const Spacer(),
        Text(value,
            style: YFont.bodyStrong().copyWith(
              color: tone ?? (faded ? YColor.inkMuted : YColor.ink),
            )),
      ]),
    );
  }

  String _fmtFullDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} $period';
  }
}

/// Compact display of a mock-order UUID. Real DB orders show a tidy
/// "Order #0042" via the `order_number` column; until those replace the
/// mock list, we render the last 6 hex characters as a short tag
/// (e.g. `b3d316` → `#B3D316`) so the row doesn't overflow.
/// Consistent outlined action button for the order detail pane. Single
/// line with ellipsis so long labels never overflow a narrow pane.
Widget _actionButton({
  required VoidCallback onPressed,
  required IconData icon,
  required String label,
  required Color foreground,
}) {
  return OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      foregroundColor: foreground,
      side: const BorderSide(color: YColor.hairline),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(YRadius.md)),
    ),
  );
}

/// Reprints the receipt for [orderId] on the configured printer. Looks the
/// full order up from the cached list (it's always one that's displayed).
Future<void> _reprintReceipt(BuildContext context, String orderId) async {
  final state = context.read<AppState>();
  final order =
      state.recentOrders.where((o) => o.id == orderId).firstOrNull;
  final tenant = state.tenant;
  final printer = state.printerConfig;
  if (order == null) return;
  if (printer == null) {
    PushToast.show(context,
        title: 'No printer connected',
        subtitle: 'Connect one in Settings → Hardware → Receipt printer.',
        leadingIcon: Icons.print_disabled_outlined);
    return;
  }
  if (tenant == null) return;
  PushToast.show(context,
      title: 'Printing receipt…', leadingIcon: Icons.print_outlined);
  final ok = await PrintJobs.receipt(
      order: order, tenant: tenant, config: printer, reprint: true);
  if (!context.mounted) return;
  PushToast.show(context,
      title: ok ? 'Receipt printed' : 'Receipt didn\'t print',
      subtitle: ok ? null : 'Check the printer is on and nearby.',
      leadingIcon:
          ok ? Icons.check_circle_outline : Icons.print_disabled_outlined);
}

/// On-theme outlined icon for an order line, sourced from its category's
/// Maintenance icon (food → restaurant, books → book, coffee → cup). Falls
/// back to a name-keyword icon, then a generic bag — never a colourful emoji.
IconData _lineCategoryIcon(BuildContext context, MockOrderLine line) {
  final cats = context.read<AppState>().categories;
  final cat =
      cats.where((c) => c.name == line.categoryName).firstOrNull;
  return resolveIcon(
    iconName: cat?.iconName,
    name: line.categoryName ?? line.name,
    fallback: Icons.shopping_bag_outlined,
  );
}

/// A richer entry for the per-line ⋯ menu: outlined icon + title + a short
/// description, all on-theme.
PopupMenuItem<String> _lineMenuItem({
  required String value,
  required IconData icon,
  required Color tone,
  required String title,
  required String subtitle,
}) {
  return PopupMenuItem<String>(
    value: value,
    height: 56,
    child: Row(children: [
      Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: tone),
      ),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: YFont.bodyStrong().copyWith(fontSize: 14, color: tone)),
          Text(subtitle,
              style: YFont.caption().copyWith(color: YColor.inkMuted)),
        ],
      ),
    ]),
  );
}

/// Small pill shown next to a line that was voided/refunded individually.
Widget _lineReversedBadge(String label) {
  final tone = label == 'Refunded' ? YColor.danger : YColor.inkMuted;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: tone,
      ),
    ),
  );
}

String _shortOrderId(String fullId) {
  final clean = fullId.replaceAll('-', '');
  final tail = clean.length >= 6
      ? clean.substring(clean.length - 6)
      : clean;
  return '#${tail.toUpperCase()}';
}

String _fmtDateTime(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  final time = '$h:${d.minute.toString().padLeft(2, '0')} $period';
  return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year} · $time';
}

/// Bridge between Supabase-backed [db.Order] and the existing [MockOrder]
/// type that this screen's widgets were built against. Lets us switch the
/// data source without rewriting the (large) UI layer.
MockOrder _adaptToMock(db.Order o) {
  return MockOrder(
    id: o.id,
    // DB times are UTC — convert to the store's local timezone so "today"
    // filtering + display don't roll an early-morning order back to yesterday.
    placedAt: o.createdAt.toLocal(),
    lines: o.lines
        .map((l) => MockOrderLine(
              name: l.name,
              emoji: l.emoji.isEmpty ? '🛒' : l.emoji,
              quantity: l.quantity,
              lineTotal: Money(l.lineTotalCents),
              subtitle: _lineSubtitle(l),
              categoryName: l.categoryName,
              lineId: l.id,
              reversed: l.status.isReversed,
              reversedLabel: l.status.isReversed ? l.status.label : null,
            ))
        .toList(),
    subtotal: Money(o.subtotalCents),
    discount: Money(o.discountCents),
    vat: Money(o.vatCents),
    total: Money(o.totalCents),
    method: _adaptMethod(o.payments),
    status: _adaptStatus(o.status),
    // Show the real operator who rang it up (employee_name), not the shared
    // account holder (cashier_name, always the owner).
    employeeName: o.employeeName ?? o.cashierName ?? 'Cashier',
    employeeEmoji: '👤',
    branchName: 'Main Branch', // TODO: lookup once branches caching exists
  );
}

String? _lineSubtitle(db.OrderLine line) {
  final mods = line.modifiers;
  if (mods == null || mods.isEmpty) return null;
  final parts = <String>[];
  if (mods['options'] is Map) {
    final options = mods['options'] as Map<String, dynamic>;
    parts.addAll(options.values.whereType<String>());
  }
  if (mods['add_ons'] is List) {
    for (final a in mods['add_ons'] as List) {
      if (a is Map<String, dynamic>) {
        final name = a['name'];
        final qty = a['quantity'];
        if (name is String && qty is int && qty > 0) {
          parts.add(qty > 1 ? '+$name ×$qty' : '+$name');
        }
      }
    }
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

PaymentMethod _adaptMethod(List<db.OrderPayment> payments) {
  // First tender wins for the at-a-glance row badge. Split-tender details
  // still render in the detail pane via the full payments list.
  final m = payments.isEmpty
      ? db.OrderPaymentMethod.cash
      : payments.first.method;
  return switch (m) {
    db.OrderPaymentMethod.cash => PaymentMethod.cash,
    db.OrderPaymentMethod.gcash => PaymentMethod.gcash,
    db.OrderPaymentMethod.bankTransfer => PaymentMethod.bank,
    db.OrderPaymentMethod.qrPh => PaymentMethod.qrph,
    db.OrderPaymentMethod.paymaya => PaymentMethod.qrph,
    db.OrderPaymentMethod.card => PaymentMethod.other,
    db.OrderPaymentMethod.other => PaymentMethod.other,
  };
}

OrderStatus _adaptStatus(db.OrderStatus s) => switch (s) {
      db.OrderStatus.paid => OrderStatus.completed,
      db.OrderStatus.refunded => OrderStatus.refunded,
      db.OrderStatus.voided => OrderStatus.voided,
      db.OrderStatus.cancelled => OrderStatus.voided,
      db.OrderStatus.open => OrderStatus.completed,
    };
