import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/cart.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../printing/print_jobs.dart';
import '../printing/receipt_builder.dart';
import '../widgets/push_toast.dart';

enum TenderMethod { cash, card, gcash, paymaya, points, account }

extension on TenderMethod {
  String get title => switch (this) {
        TenderMethod.cash => 'Cash',
        TenderMethod.card => 'Card',
        TenderMethod.gcash => 'GCash',
        TenderMethod.paymaya => 'PayMaya',
        TenderMethod.points => 'Points',
        TenderMethod.account => 'On Account',
      };

  IconData get icon => switch (this) {
        TenderMethod.cash => Icons.payments,
        TenderMethod.card => Icons.credit_card,
        TenderMethod.gcash => Icons.qr_code_2,
        TenderMethod.paymaya => Icons.qr_code,
        TenderMethod.points => Icons.star,
        TenderMethod.account => Icons.account_circle,
      };
}

class TenderSheet extends StatefulWidget {
  const TenderSheet({super.key});

  @override
  State<TenderSheet> createState() => _TenderSheetState();
}

class _TenderSheetState extends State<TenderSheet> {
  TenderMethod? method;
  String cashReceived = '';
  bool completed = false;
  bool _busy = false;
  String? _error;
  int? _orderNumber;
  o.Order? _completedOrder;
  bool _printBusy = false;
  String? _printStatus;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final size = MediaQuery.sizeOf(context);
    final card = Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: completed ? _completed(state) : _form(state),
    );
    // Form needs the wide layout (cart preview + tender keypad side-by-side).
    // Success screen only has a checkmark + amount + button — shrink to fit
    // so the modal doesn't look like a sparse hangar over the receipt.
    if (completed) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: IntrinsicHeight(child: card),
        ),
      );
    }
    // Sweet spot: ~1000px on a 1366 iPad Pro, ~820 on a smaller iPad. The
    // earlier `size.width − 560` was too narrow; full-bleed (40px margins)
    // was too wide. Cap at 1100px so massive monitors don't render a
    // mile-wide sheet.
    final width = (size.width - 240).clamp(720.0, 1100.0);
    return Center(
      child: SizedBox(
        width: width,
        height: size.height * 0.9,
        child: card,
      ),
    );
  }

  Widget _form(AppState state) {
    final cart = state.cart;
    return Row(
      children: [
        // Cart preview (left) — slightly narrower so the payment pane on
        // the right has room for the 3-column method grid.
        Expanded(
          flex: 45,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: YColor.brand)),
                  ),
                  const Spacer(),
                  Text('Payment', style: YFont.titleMD()),
                  const Spacer(),
                  const SizedBox(width: 80),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final line = cart.lines[i];
                      return Row(children: [
                        ProductVisual(
                          imageUrl: line.imageUrl,
                          name: line.title,
                          iconName: line.iconName,
                          size: 40,
                          iconSize: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.title, style: YFont.bodyStrong()),
                              if (line.subtitle != null)
                                Text(line.subtitle!, style: YFont.caption()),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(line.lineTotal.formatted,
                                style: YFont.bodyStrong()),
                            Text('×${line.quantity}', style: YFont.caption()),
                          ],
                        ),
                      ]);
                    },
                  ),
                ),
                const Divider(),
                _totalRow('Subtotal', cart.subtotal.formatted),
                _totalRow('VAT (incl.)', cart.vat.formatted, faded: true),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Total to pay', style: YFont.titleMD()),
                  const Spacer(),
                  Text(cart.total.formatted,
                      style: YFont.titleMD()
                          .copyWith(color: YColor.brand, fontSize: 22)),
                ]),
              ],
            ),
          ),
        ),
        Container(width: 0.5, color: YColor.hairline),
        // Right column — animated step switcher
        // Right column wider (was flex:45) so the 3-column payment method
        // grid + the cash keypad have room to breathe — they were getting
        // cramped against the cart preview on the left.
        Expanded(
          flex: 55,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: method == null
                ? _methodPicker(state, key: const ValueKey('picker'))
                : method == TenderMethod.cash
                    ? _cashEntry(state, key: const ValueKey('cash'))
                    : _otherMethodConfirm(state,
                        key: const ValueKey('other')),
          ),
        ),
      ],
    );
  }

  // ── Step 0: pick payment method ──
  Widget _methodPicker(AppState state, {Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Choose payment method',
            textAlign: TextAlign.center,
            style: YFont.titleLG(),
          ),
          const SizedBox(height: 8),
          Text(
            'Select how the customer will pay',
            textAlign: TextAlign.center,
            style: YFont.body().copyWith(color: YColor.inkMuted),
          ),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
            children: TenderMethod.values.map(_methodTile).toList(),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: YColor.brandTint.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(YRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tap a method to continue',
                    style: YFont.caption().copyWith(color: YColor.brandDeep),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodTile(TenderMethod m) {
    // Cash is the only payment we actually process today. Lock the rest
    // visually + behaviourally so cashiers don't pick a half-built flow.
    // When we wire GCash / Card / etc. in a later sprint, swap this to
    // a per-tenant feature flag instead of a hardcoded set.
    final enabled = m == TenderMethod.cash;
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              setState(() {
                method = m;
                cashReceived = '';
              });
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline),
            // Soft floating shadow so the tiles read as tappable cards
            // instead of flat outlined boxes. Skipped when disabled so
            // locked tiles also visually recede.
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                      spreadRadius: -6,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // Fills the tile so the column actually centers vertically
              // + horizontally inside the box (was only horizontal before
              // because the Column was sized to its content at top-left).
              Positioned.fill(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(m.icon, color: YColor.brand, size: 32),
                    const SizedBox(height: 10),
                    Flexible(
                      child: Text(
                        m.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.bodyStrong().copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              if (!enabled)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: YColor.surface3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.lock_outline,
                        size: 10, color: YColor.inkMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1a: cash amount entry with on-screen numpad ──
  Widget _cashEntry(AppState state, {Key? key}) {
    final total = state.cart.total;
    final entered = double.tryParse(cashReceived) ?? 0;
    final receivedMoney = Money.pesos(entered);
    final isEnough = receivedMoney.centavos >= total.centavos;
    final diff = isEnough
        ? receivedMoney - total
        : Money(total.centavos - receivedMoney.centavos);

    return Padding(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _backRow(),
          const SizedBox(height: 12),
          // Amount display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: YColor.brandTint.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(YRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CASH RECEIVED',
                  style: YFont.caption().copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: YColor.brandDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₱${entered.toStringAsFixed(2)}',
                  style: YFont.titleLG().copyWith(
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                    color: cashReceived.isEmpty
                        ? YColor.inkSubtle
                        : YColor.brand,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text(
                    isEnough ? 'Change' : 'Short',
                    style: YFont.caption().copyWith(
                      color:
                          isEnough ? YColor.success : YColor.danger,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    diff.formatted,
                    style: YFont.bodyStrong().copyWith(
                      color: isEnough ? YColor.success : YColor.danger,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Quick fill chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [160, 200, 500, 1000].map((amt) {
              return InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => cashReceived = amt.toString());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: YColor.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: YColor.hairline),
                  ),
                  child: Text(
                    '₱$amt',
                    style: YFont.bodyStrong().copyWith(
                      color: YColor.brandDeep,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // Numpad
          Expanded(child: _numpad()),
          const SizedBox(height: 16),
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_busy || !isEnough || entered <= 0)
                  ? null
                  : () { _complete(state); },
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YColor.surface3,
                disabledForegroundColor: YColor.inkSubtle,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isEnough
                          ? 'Complete'
                          : 'Enter at least ${total.formatted}',
                      style:
                          YFont.bodyStrong().copyWith(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 1b: non-cash confirmation ──
  Widget _otherMethodConfirm(AppState state, {Key? key}) {
    final m = method!;
    return Padding(
      key: key,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _backRow(),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(m.icon, size: 44, color: YColor.brand),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Charge with ${m.title}',
              style: YFont.titleLG().copyWith(fontSize: 22),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              state.cart.total.formatted,
              style: YFont.titleLG()
                  .copyWith(fontSize: 36, color: YColor.brand),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              _hintFor(m),
              textAlign: TextAlign.center,
              style: YFont.body().copyWith(color: YColor.inkMuted),
            ),
          ),
          const Spacer(),
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy ? null : () { _complete(state); },
              style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: YColor.surface3,
                disabledForegroundColor: YColor.inkSubtle,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Charge ${state.cart.total.formatted}',
                      style:
                          YFont.bodyStrong().copyWith(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  String _hintFor(TenderMethod m) => switch (m) {
        TenderMethod.cash => '',
        TenderMethod.card => 'Tap, insert, or swipe the card on the terminal.',
        TenderMethod.gcash => 'Show the GCash QR for the customer to scan.',
        TenderMethod.paymaya => 'Show the PayMaya QR for the customer to scan.',
        TenderMethod.points => 'Look up the member to redeem loyalty points.',
        TenderMethod.account => 'Bill to the member\'s on-account balance.',
      };

  Widget _backRow() {
    return Row(children: [
      InkWell(
        borderRadius: BorderRadius.circular(YRadius.md),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            method = null;
            cashReceived = '';
          });
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 18, color: YColor.brand),
            const SizedBox(width: 6),
            Text('Back',
                style: YFont.bodyStrong().copyWith(color: YColor.brand)),
          ]),
        ),
      ),
      const Spacer(),
      Text(method!.title,
          style: YFont.caption().copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: YColor.inkMuted,
          )),
    ]);
  }

  // ── On-screen numpad ──
  Widget _numpad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];
    return Column(
      children: rows.map((row) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: row.map((k) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _numKey(k),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _numKey(String key) {
    final isDelete = key == '⌫';
    return Material(
      color: YColor.surface1,
      borderRadius: BorderRadius.circular(YRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(YRadius.md),
        onTap: () => _onKey(key),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: YColor.hairline),
            borderRadius: BorderRadius.circular(YRadius.md),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isDelete
              ? const Icon(Icons.backspace_outlined, size: 22)
              : Text(
                  key,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  void _onKey(String k) {
    HapticFeedback.lightImpact();
    setState(() {
      if (k == '⌫') {
        if (cashReceived.isNotEmpty) {
          cashReceived = cashReceived.substring(0, cashReceived.length - 1);
        }
      } else if (k == '.') {
        if (!cashReceived.contains('.')) {
          cashReceived = cashReceived.isEmpty ? '0.' : '$cashReceived.';
        }
      } else {
        // limit to 2 decimal places
        if (cashReceived.contains('.') &&
            cashReceived.split('.').last.length >= 2) return;
        if (cashReceived == '0') {
          cashReceived = k;
        } else {
          cashReceived += k;
        }
      }
    });
  }

  /// Persists the cart as a paid order in Supabase, then deducts inventory
  /// and shows the success screen. The DB write is the source of truth —
  /// we don't claim "completed" until the RPC returns an order id.
  Future<void> _complete(AppState state) async {
    if (_busy) return;

    // Stock guard — refuses the sale up-front if any inventory item would
    // be pushed below zero by this cart (taking modifier multipliers +
    // add-on recipes into account). Plain-English error names the
    // offending item so the cashier can fix the cart or restock first.
    final stockError = state.validateCartStock();
    if (stockError != null) {
      setState(() => _error = stockError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final cart = state.cart;
    final m = method ?? TenderMethod.cash;
    final totalCents = cart.total.centavos;

    // Map the chosen tender into the DB-compatible enum. Loyalty / on-account
    // aren't real money methods yet — fall back to "other" so the audit row
    // is still complete.
    final dbMethod = switch (m) {
      TenderMethod.cash => o.OrderPaymentMethod.cash,
      TenderMethod.gcash => o.OrderPaymentMethod.gcash,
      TenderMethod.paymaya => o.OrderPaymentMethod.paymaya,
      TenderMethod.card => o.OrderPaymentMethod.card,
      _ => o.OrderPaymentMethod.other,
    };

    int? tenderedCents;
    int? changeCents;
    if (m == TenderMethod.cash) {
      final entered = double.tryParse(cashReceived) ?? 0;
      tenderedCents = Money.pesos(entered).centavos;
      changeCents = tenderedCents - totalCents;
      if (changeCents < 0) changeCents = 0;
    }

    // Build line snapshots from the in-memory cart. Sellable IDs are null
    // for now because products still live in-memory; turn 1b migrates them
    // to the `sellables` table and we start passing real ids here.
    final lines = cart.lines.map((line) {
      String? categoryName;
      if (line.kind case CartLineCafe(:final item)) {
        categoryName = item.category.title;
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
        // Snapshot this line's ingredient usage so a later per-item
        // void/refund can restock exactly what it consumed.
        recipeDeductions: state.recipeDeductionsForCartLine(line),
      );
    }).toList();

    final payments = [
      (
        method: dbMethod,
        amountCents:
            m == TenderMethod.cash ? totalCents : totalCents, // single-tender
        tenderedCents: tenderedCents,
        changeCents: changeCents,
        reference: null as String?,
      ),
    ];

    final result = await state.createPaidOrder(
      lines: lines,
      payments: payments,
      customerName: cart.customer?.name,
    );

    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }

    // Order persisted ✅. Now deduct in-memory inventory for the recipe-built
    // items so the local cache stays consistent. (Inventory itself migrates
    // to DB in turn 3 — until then this stays in-memory.)
    final summary = state.deductCartFromInventory();

    // Refresh the Orders cache so the new order appears in the Orders tab.
    // Best-effort — receipt # extracted from the freshly cached list.
    int? orderNumber;
    try {
      await state.refreshOrders();
      final fresh = state.recentOrders.where((o) => o.id == result.id);
      if (fresh.isNotEmpty) {
        orderNumber = fresh.first.orderNumber;
        _completedOrder = fresh.first;
      }
    } catch (_) {/* receipt # is best-effort */}

    if (!mounted) return;
    setState(() {
      _busy = false;
      _orderNumber = orderNumber;
      completed = true;
    });

    // Auto-print the customer receipt to the configured printer (best-effort,
    // serialized so it can't collide with a tapped prep ticket).
    final order = _completedOrder;
    final printer = state.printerConfig;
    final tenant = state.tenant;
    if (order != null && printer != null && tenant != null) {
      await _doPrint(
        () => PrintJobs.receipt(order: order, tenant: tenant, config: printer),
        what: 'Receipt',
      );
    }

    if (summary.isEmpty) return;
    final stockLines = <String>[];
    for (final entry in summary.entries) {
      final item = state.inventory
          .where((i) => i.id == entry.key)
          .firstOrNull;
      if (item == null) continue;
      stockLines.add(
          '−${entry.value.toStringAsFixed(0)}${item.displayUnit} ${item.name}');
      if (stockLines.length >= 3) break;
    }
    if (summary.length > 3) {
      stockLines.add('+${summary.length - 3} more');
    }
    if (!mounted) return;
    PushToast.show(
      context,
      title: 'Stock updated',
      subtitle: stockLines.join(' · '),
      leadingIcon: Icons.inventory_2_outlined,
    );
  }

  /// Compact JSON snapshot of a line's modifier selections + add-ons so the
  /// receipt history preserves what the customer ordered.
  Map<String, dynamic>? _modifiersSnapshot(CartLine line) {
    if (line.kind case CartLineCafe(:final item, :final selections, :final addOns)) {
      final mods = <String, String>{};
      for (final g in item.modifierGroups) {
        final optId = selections[g.id];
        if (optId == null) continue;
        final opt = g.options.where((o) => o.id == optId).firstOrNull;
        if (opt != null) mods[g.name] = opt.name;
      }
      final addOnList = addOns
          .where((a) => a.quantity > 0)
          .map((a) => {
                'name': a.addOn.name,
                'quantity': a.quantity,
              })
          .toList();
      if (mods.isEmpty && addOnList.isEmpty) return null;
      return {
        if (mods.isNotEmpty) 'options': mods,
        if (addOnList.isNotEmpty) 'add_ons': addOnList,
      };
    }
    return null;
  }

  Widget _completed(AppState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: YColor.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                size: 56, color: YColor.success),
          ),
          const SizedBox(height: 16),
          Text('Payment Complete', style: YFont.titleLG()),
          if (_orderNumber != null) ...[
            const SizedBox(height: 4),
            Text('Order #${_orderNumber.toString().padLeft(4, '0')}',
                style: YFont.caption().copyWith(
                  color: YColor.inkMuted,
                  fontSize: 13,
                  letterSpacing: 0.6,
                )),
          ],
          const SizedBox(height: 8),
          Text(state.cart.total.formatted,
              style: YFont.titleLG().copyWith(color: YColor.brand)),
          const SizedBox(height: 24),
          _printActions(state),
          ElevatedButton(
            onPressed: () {
              state.cart.clear();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
            child: const Text('New Order'),
          ),
        ],
      ),
    );
  }

  /// Print buttons on the success screen — reprint the receipt and route prep
  /// tickets (Barista for drinks, Kitchen for food). Hidden when no printer is
  /// configured.
  Widget _printActions(AppState state) {
    final order = _completedOrder;
    final printer = state.printerConfig;
    final tenant = state.tenant;
    if (order == null || printer == null) return const SizedBox.shrink();
    final drinks = ReceiptBuilder.hasDrinks(order);
    final food = ReceiptBuilder.hasFood(order);

    // While a job is in flight, show a lock so the printer can't be spammed.
    if (_printBusy) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(_printStatus ?? 'Printing…',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ]),
      );
    }

    return Column(children: [
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          if (tenant != null)
            _prepBtn('Reprint receipt', Icons.receipt_long_outlined,
                () => _doPrint(
                      () => PrintJobs.receipt(
                          order: order, tenant: tenant, config: printer),
                      what: 'Receipt',
                    )),
          if (drinks)
            _prepBtn('Barista ticket', Icons.local_cafe_outlined,
                () => _doPrint(
                      () => PrintJobs.barista(order: order, config: printer),
                      what: 'Barista ticket',
                    )),
          if (food)
            _prepBtn('Kitchen ticket', Icons.restaurant_outlined,
                () => _doPrint(
                      () => PrintJobs.kitchen(order: order, config: printer),
                      what: 'Kitchen ticket',
                    )),
        ],
      ),
      const SizedBox(height: 16),
    ]);
  }

  /// Runs a print job with a UI lock — ignores taps while one is in flight
  /// (anti-spam) and shows a "Printing…" status. Jobs are also serialized at
  /// the Bluetooth layer, so nothing collides.
  Future<void> _doPrint(Future<bool> Function() job,
      {String what = 'Document'}) async {
    if (_printBusy) return;
    setState(() {
      _printBusy = true;
      _printStatus = 'Printing $what…';
    });
    final ok = await job();
    if (!mounted) return;
    setState(() {
      _printBusy = false;
      _printStatus = null;
    });
    PushToast.show(context,
        title: ok ? '$what printed' : '$what didn\'t print',
        subtitle: ok ? null : 'Check the printer is on and nearby.',
        leadingIcon:
            ok ? Icons.check_circle_outline : Icons.print_disabled_outlined);
  }

  Widget _prepBtn(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: YColor.brandDeep,
        side: const BorderSide(color: YColor.hairline),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(YRadius.md)),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool faded = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Text(label,
            style: YFont.body()
                .copyWith(color: faded ? YColor.inkMuted : YColor.ink)),
        const Spacer(),
        Text(value,
            style: YFont.bodyStrong()
                .copyWith(color: faded ? YColor.inkMuted : YColor.ink)),
      ]),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.dangerSoft,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 16, color: YColor.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: YFont.caption().copyWith(color: YColor.danger)),
          ),
        ],
      ),
    );
  }
}
