import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/cart.dart';
import '../../models/money.dart';
import '../../models/order.dart' as o;
import '../auth/otp_numpad.dart';
import '../printing/drawer_prefs.dart';
import '../printing/print_jobs.dart';
import '../printing/receipt_builder.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

enum TenderMethod { cash, gcash, bank, qrph }

extension on TenderMethod {
  String get title => switch (this) {
        TenderMethod.cash => 'Cash',
        TenderMethod.gcash => 'GCash',
        TenderMethod.bank => 'Bank',
        TenderMethod.qrph => 'QR Ph',
      };

  IconData get icon => switch (this) {
        TenderMethod.cash => Icons.payments,
        TenderMethod.gcash => Icons.qr_code_2,
        TenderMethod.bank => Icons.account_balance,
        TenderMethod.qrph => Icons.qr_code,
      };

  /// QR / e-wallet methods settle outside the POS (into the owner's wallet or
  /// bank), so they need a reference number for end-of-day reconciliation.
  bool get needsReference => this != TenderMethod.cash;
}

class TenderSheet extends StatefulWidget {
  const TenderSheet({super.key});

  @override
  State<TenderSheet> createState() => _TenderSheetState();
}

class _TenderSheetState extends State<TenderSheet> {
  TenderMethod? method;
  String cashReceived = '';
  // Cash tendered + change for the completed sale (null for non-cash) — shown
  // on the success screen so the cashier can make change at the open drawer.
  int? _paidTenderedCents;
  int? _paidChangeCents;
  // Reference / transaction number for QR / e-wallet payments. Required
  // before a non-cash sale can be charged (used to reconcile against the
  // GCash / bank statement later).
  String _reference = '';
  final TextEditingController _refController = TextEditingController();

  // Senior Citizen / PWD discount (whole-order). type: 'senior' | 'pwd'.
  String? _scType;
  String _scName = '';
  String _scId = '';

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  /// Total discount for an SC/PWD sale vs the VAT-inclusive sticker price:
  /// strip the 12% VAT (VAT-registered only), then take 20% off the net.
  int _scDiscountCents(AppState state) {
    if (_scType == null) return 0;
    final s = state.cart.total.centavos;
    final vatReg = state.tenant?.vatRegistered ?? false;
    final net = vatReg ? (s / 1.12).round() : s;
    final disc = (net * 0.20).round();
    return s - (net - disc);
  }

  /// What the customer actually pays after any SC/PWD discount.
  Money _amountDue(AppState state) =>
      Money(state.cart.total.centavos - _scDiscountCents(state));

  Future<void> _applyScPwd(AppState state) async {
    final result = await showDialog<({String type, String name, String id})>(
      context: context,
      builder: (_) => const _ScPwdDialog(),
    );
    if (result != null) {
      setState(() {
        _scType = result.type;
        _scName = result.name;
        _scId = result.id;
      });
    }
  }

  Widget _scPwdControl(AppState state) {
    if (_scType != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: YColor.brandTint.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(children: [
          Icon(_scType == 'senior' ? Icons.elderly : Icons.accessible,
              size: 18, color: YColor.brandDeep),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_scType == 'senior' ? 'Senior Citizen' : 'PWD',
                    style: YFont.bodyStrong().copyWith(fontSize: 13)),
                Text('$_scName · ID $_scId',
                    style: YFont.caption(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _scType = null;
              _scName = '';
              _scId = '';
            }),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ]),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () => _applyScPwd(state),
        child: CustomPaint(
          painter: _DashedRRectPainter(
              color: YColor.brandDeep.withValues(alpha: 0.6),
              radius: YRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.badge_outlined,
                    size: 18, color: YColor.brandDeep),
                const SizedBox(width: 8),
                Text('Senior / PWD discount',
                    style: YFont.bodyStrong()
                        .copyWith(color: YColor.brandDeep, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
  bool completed = false;
  bool _busy = false;
  String? _error;
  int? _orderNumber;
  o.Order? _completedOrder;
  bool _printBusy = false;
  String? _printStatus;
  // What's been printed for this order — gates "New Order" so nothing is
  // missed. _skipPrinting is the escape hatch when the printer is down.
  bool _receiptPrinted = false;
  bool _baristaPrinted = false;
  bool _kitchenPrinted = false;
  bool _skipPrinting = false;
  // Optional buzzer / table number the cashier hands the customer — printed
  // big on the barista + kitchen tickets so they can call it out.
  String _buzzer = '';

  void _onBuzzerDigit(String d) {
    if (_buzzer.length >= 4) return;
    setState(() => _buzzer += d);
  }

  void _onBuzzerBackspace() {
    if (_buzzer.isEmpty) return;
    setState(() => _buzzer = _buzzer.substring(0, _buzzer.length - 1));
  }

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
          constraints: const BoxConstraints(maxWidth: 760),
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
                Text('Payment', style: YFont.titleMD()),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final line = cart.lines[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: YColor.surface1,
                          borderRadius: BorderRadius.circular(YRadius.md),
                          border: Border.all(color: YColor.brand, width: 1),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.title, style: YFont.bodyStrong()),
                                if (line.subtitle != null &&
                                    line.subtitle!.trim().isNotEmpty)
                                  Text(line.subtitle!,
                                      style: YFont.caption()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(line.lineTotal.formatted,
                                  style: YFont.bodyStrong()),
                              Text('×${line.quantity}',
                                  style: YFont.caption()),
                            ],
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                const Divider(),
                _totalRow('Subtotal', cart.subtotal.formatted),
                if (_scType == null)
                  _totalRow('VAT (incl.)', cart.vat.formatted, faded: true)
                else
                  _totalRow(
                      _scType == 'senior'
                          ? 'Senior disc (20% + VAT-exempt)'
                          : 'PWD disc (20% + VAT-exempt)',
                      '-${Money(_scDiscountCents(state)).formatted}'),
                const SizedBox(height: 6),
                Row(children: [
                  Text(_scType == null ? 'Total to pay' : 'Amount due',
                      style: YFont.titleMD()),
                  const Spacer(),
                  Text(_amountDue(state).formatted,
                      style: YFont.titleMD()
                          .copyWith(color: YColor.brand, fontSize: 22)),
                ]),
                const SizedBox(height: 12),
                _scPwdControl(state),
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
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: TenderMethod.values.map(_methodTile).toList(),
          ),
          const Spacer(),
          Row(
            children: [
              // Info (left)
              Expanded(
                child: Container(
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
                          style: YFont.caption()
                              .copyWith(color: YColor.brandDeep),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Close payment (right) — same footprint as the info box.
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: YColor.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(YRadius.md),
                      border: Border.all(
                          color: YColor.danger.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.close_rounded,
                            size: 16, color: YColor.danger),
                        const SizedBox(width: 8),
                        Text(
                          'Close payment',
                          style: YFont.caption().copyWith(
                              color: YColor.danger,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodTile(TenderMethod m) {
    // All four methods (Cash, GCash, Bank, QR Ph) are live. Non-cash ones
    // settle outside the POS and just get recorded with a reference number.
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _refController.clear();
        setState(() {
          method = m;
          cashReceived = '';
          _reference = '';
        });
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
          // Soft floating shadow so the tiles read as tappable cards
          // instead of flat outlined boxes.
          boxShadow: [
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
          ],
        ),
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
    );
  }

  // ── Step 1a: cash amount entry with on-screen numpad ──
  Widget _cashEntry(AppState state, {Key? key}) {
    final total = _amountDue(state);
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
              _amountDue(state).formatted,
              style: YFont.titleLG()
                  .copyWith(fontSize: 36, color: YColor.brand),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _hintFor(m),
              textAlign: TextAlign.center,
              style: YFont.body().copyWith(color: YColor.inkMuted),
            ),
          ),
          const SizedBox(height: 18),
          // Required reference number — settles outside the POS, so this is
          // the only thread that lets the owner reconcile with the wallet/bank.
          // Uses the floating accessory card above the keyboard for clarity.
          KeyboardAccessoryField(
            controller: _refController,
            accessoryLabel: 'REFERENCE NUMBER',
            label: 'Reference number',
            hint: 'From the customer\'s payment confirmation',
            keyboardType: TextInputType.text,
            fillColor: YColor.surface1,
            borderColor: YColor.hairline,
            onChanged: (v) => setState(() => _reference = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(
              _reference.trim().isEmpty
                  ? Icons.info_outline
                  : Icons.check_circle_outline,
              size: 14,
              color: _reference.trim().isEmpty
                  ? YColor.inkSubtle
                  : YColor.success,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _reference.trim().isEmpty
                    ? 'Required before charging — ask the customer to show their reference no.'
                    : 'Reference recorded — you can charge now.',
                style: YFont.caption().copyWith(color: YColor.inkSubtle),
              ),
            ),
          ]),
          const Spacer(),
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_busy || _reference.trim().isEmpty)
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
                  : Text('Charge ${_amountDue(state).formatted}',
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
        TenderMethod.gcash =>
          'Show the store GCash QR. Customer pays, then enter their reference no.',
        TenderMethod.bank =>
          'Show the bank QR / details. Customer pays, then enter the reference no.',
        TenderMethod.qrph =>
          'Show the QR Ph code. Customer pays, then enter their reference no.',
      };

  Widget _backRow() {
    return Row(children: [
      InkWell(
        borderRadius: BorderRadius.circular(YRadius.md),
        onTap: () {
          HapticFeedback.lightImpact();
          _refController.clear();
          setState(() {
            method = null;
            cashReceived = '';
            _reference = '';
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
    final scDiscountCents = _scDiscountCents(state);
    final totalCents = cart.total.centavos - scDiscountCents; // amount due

    // The server rejects a ₱0 payment (amount_cents > 0 CHECK). Catch it here
    // with a clear message instead of a cryptic save error.
    if (totalCents <= 0) {
      setState(() {
        _busy = false;
        _error = 'This order totals ₱0. Add a priced item before charging.';
      });
      return;
    }

    // Map the chosen tender into the DB-compatible enum.
    final dbMethod = switch (m) {
      TenderMethod.cash => o.OrderPaymentMethod.cash,
      TenderMethod.gcash => o.OrderPaymentMethod.gcash,
      TenderMethod.bank => o.OrderPaymentMethod.bankTransfer,
      TenderMethod.qrph => o.OrderPaymentMethod.qrPh,
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
        // Real DB category (Coffee / Books / Food …) so barista/kitchen
        // routing works. Falls back to the legacy enum for in-memory items.
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
        // Snapshot this line's ingredient usage so a later per-item
        // void/refund can restock exactly what it consumed.
        recipeDeductions: state.recipeDeductionsForCartLine(line),
      );
    }).toList();

    final payments = [
      (
        method: dbMethod,
        amountCents: totalCents, // single-tender, exact total
        tenderedCents: tenderedCents,
        changeCents: changeCents,
        reference: m.needsReference ? _reference.trim() : null,
      ),
    ];

    final result = await state.createPaidOrder(
      lines: lines,
      payments: payments,
      customerName: cart.customer?.name,
      discountCents: scDiscountCents,
      scPwdType: _scType,
      scPwdName: _scType == null ? null : _scName,
      scPwdId: _scType == null ? null : _scId,
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
      _paidTenderedCents = tenderedCents;
      _paidChangeCents = changeCents;
      completed = true;
    });

    // Cash sale → pop the cash drawer wired to the receipt printer so the
    // cashier can make change. Fires before the receipt so the drawer opens
    // the instant the sale is charged. Best-effort and harmless if no drawer
    // is connected (the printer just ignores the pulse).
    final printer = state.printerConfig;
    if (m == TenderMethod.cash && printer != null) {
      await PrintJobs.openDrawer(printer, pin5: await DrawerPrefs.usesPin5());
    }

    // Auto-print the customer receipt to the configured printer (best-effort,
    // serialized so it can't collide with a tapped prep ticket).
    final order = _completedOrder;
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

  Widget _payRow(String label, String value, {bool big = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: (big ? YFont.bodyStrong() : YFont.body())
                .copyWith(color: big ? YColor.brandDeep : YColor.inkMuted)),
        Text(value,
            style: (big ? YFont.titleMD() : YFont.bodyStrong()).copyWith(
                color: big ? YColor.brand : YColor.ink,
                fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _completed(AppState state) {
    final pending = _printsPending(state);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: YColor.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                size: 40, color: YColor.success),
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 20),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT — buzzer / table number input above the number pad.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('BUZZER / TABLE NO. (optional)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: YColor.brandDeep)),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: 190, child: _buzzerDisplay()),
                    const SizedBox(height: 12),
                    OtpNumpad(
                      onDigit: _onBuzzerDigit,
                      onBackspace: _onBuzzerBackspace,
                      keyWidth: 58,
                      keyHeight: 44,
                    ),
                  ],
                ),
                const SizedBox(width: 28),
                // RIGHT — totals + prints on top; finish + printer-down pinned
                // to the bottom so the column matches the numpad's height.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: YColor.surface2,
                          borderRadius: BorderRadius.circular(YRadius.md),
                          border: Border.all(color: YColor.hairline),
                        ),
                        child: Column(
                          children: [
                            _payRow('Total', _amountDue(state).formatted),
                            if (_paidTenderedCents != null) ...[
                              const SizedBox(height: 10),
                              _payRow('Amount received',
                                  Money(_paidTenderedCents!).formatted),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: _DashLine(),
                              ),
                              _payRow('Change',
                                  Money(_paidChangeCents ?? 0).formatted,
                                  big: true),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _printActions(state),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: pending
                            ? null
                            : () {
                                state.cart.clear();
                                Navigator.of(context).pop();
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: YColor.brand,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: YColor.surface3,
                          disabledForegroundColor: YColor.inkMuted,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(YRadius.md)),
                        ),
                        child:
                            Text(pending ? 'Print to continue' : 'New Order'),
                      ),
                      if (pending)
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _skipPrinting = true),
                            child: Text(
                                'Printer down? Finish without printing',
                                style: YFont.caption()
                                    .copyWith(color: YColor.inkMuted)),
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

  Widget _buzzerDisplay() {
    final empty = _buzzer.isEmpty;
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(
            color: empty ? YColor.hairline : YColor.brand, width: 1.4),
      ),
      child: Text(empty ? '—' : _buzzer,
          style: YFont.titleLG().copyWith(
              fontSize: 30,
              color: empty ? YColor.inkSubtle : YColor.brand,
              fontWeight: FontWeight.w800,
              letterSpacing: 4)),
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
            _prepBtn(
                _receiptPrinted ? 'Reprint receipt' : 'Print receipt',
                Icons.receipt_long_outlined,
                () => _doPrint(
                      () => PrintJobs.receipt(
                          order: order, tenant: tenant, config: printer),
                      what: 'Receipt',
                    ),
                done: _receiptPrinted),
          // Always shown; greyed out + non-tappable when the order has no
          // drinks (barista) / no food (kitchen).
          if (tenant != null)
            _prepBtn(
                _baristaPrinted ? 'Reprint barista' : 'Print barista',
                Icons.local_cafe_outlined,
                () => _doPrint(
                      () => PrintJobs.barista(
                          order: order,
                          tenant: tenant,
                          config: printer,
                          number: _buzzer),
                      what: 'Barista ticket',
                    ),
                done: _baristaPrinted,
                disabled: !drinks),
          if (tenant != null)
            _prepBtn(
                _kitchenPrinted ? 'Reprint kitchen' : 'Print kitchen',
                Icons.restaurant_outlined,
                () => _doPrint(
                      () => PrintJobs.kitchen(
                          order: order,
                          tenant: tenant,
                          config: printer,
                          number: _buzzer),
                      what: 'Kitchen ticket',
                    ),
                done: _kitchenPrinted,
                disabled: !food),
        ],
      ),
      const SizedBox(height: 16),
    ]);
  }

  /// True when a printer is set and something still needs printing (and the
  /// cashier hasn't chosen to skip). Drives the "New Order" gate.
  bool _printsPending(AppState state) {
    final order = _completedOrder;
    final printer = state.printerConfig;
    if (order == null || printer == null || _skipPrinting) return false;
    final needBarista = ReceiptBuilder.hasDrinks(order);
    final needKitchen = ReceiptBuilder.hasFood(order);
    return !_receiptPrinted ||
        (needBarista && !_baristaPrinted) ||
        (needKitchen && !_kitchenPrinted);
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
      if (ok) {
        if (what == 'Receipt') _receiptPrinted = true;
        if (what == 'Barista ticket') _baristaPrinted = true;
        if (what == 'Kitchen ticket') _kitchenPrinted = true;
      }
    });
    PushToast.show(context,
        title: ok ? '$what printed' : '$what didn\'t print',
        subtitle: ok ? null : 'Check the printer is on and nearby.',
        leadingIcon:
            ok ? Icons.check_circle_outline : Icons.print_disabled_outlined);
  }

  Widget _prepBtn(String label, IconData icon, VoidCallback onTap,
      {bool done = false, bool disabled = false}) {
    if (disabled) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon, size: 16, color: YColor.inkSubtle),
        label: Text(label, style: const TextStyle(color: YColor.inkSubtle)),
        style: OutlinedButton.styleFrom(
          disabledForegroundColor: YColor.inkSubtle,
          side: BorderSide(color: YColor.hairline.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.md)),
        ),
      );
    }
    final tone = done ? YColor.success : YColor.brandDeep;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(done ? Icons.check_circle : icon, size: 16, color: tone),
      label: Text(label, style: TextStyle(color: tone)),
      style: OutlinedButton.styleFrom(
        foregroundColor: tone,
        backgroundColor: done ? YColor.successSoft : null,
        side: BorderSide(color: done ? YColor.success : YColor.hairline),
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

/// Captures the Senior Citizen / PWD type + name + ID for a discounted sale.
/// Returns ({type, name, id}) or null if cancelled.
class _ScPwdDialog extends StatefulWidget {
  const _ScPwdDialog();
  @override
  State<_ScPwdDialog> createState() => _ScPwdDialogState();
}

class _ScPwdDialogState extends State<_ScPwdDialog> {
  String _type = 'senior';
  final _name = TextEditingController();
  final _id = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _name.text.trim().isNotEmpty && _id.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Senior / PWD discount', style: YFont.titleMD()),
            const SizedBox(height: 4),
            Text('20% off + VAT exemption. Verify and record the ID.',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 16),
            Row(children: [
              _typeChip('senior', 'Senior Citizen', Icons.elderly),
              const SizedBox(width: 10),
              _typeChip('pwd', 'PWD', Icons.accessible),
            ]),
            const SizedBox(height: 16),
            _field(_name, 'Full name', TextCapitalization.words),
            const SizedBox(height: 12),
            _field(_id, 'OSCA / PWD ID number', TextCapitalization.characters),
            const SizedBox(height: 20),
            Row(children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: YColor.inkMuted),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: ready
                    ? () => Navigator.of(context).pop((
                          type: _type,
                          name: _name.text.trim(),
                          id: _id.text.trim(),
                        ))
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: YColor.surface3,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: const Text('Apply discount'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _typeChip(String value, String label, IconData icon) {
    final on = _type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: on ? YColor.brand : YColor.surface2,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: on ? YColor.brand : YColor.hairline),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: on ? Colors.white : YColor.brandDeep),
            const SizedBox(width: 8),
            Text(label,
                style: YFont.bodyStrong()
                    .copyWith(color: on ? Colors.white : YColor.ink)),
          ]),
        ),
      ),
    );
  }

  Widget _field(
      TextEditingController c, String label, TextCapitalization caps) {
    return TextField(
      controller: c,
      textCapitalization: caps,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: YColor.surface2,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YRadius.md),
          borderSide: const BorderSide(color: YColor.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YRadius.md),
          borderSide: const BorderSide(color: YColor.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YRadius.md),
          borderSide: const BorderSide(color: YColor.brand, width: 1.5),
        ),
      ),
    );
  }
}

/// Thin horizontal dashed line — the receipt-style separator above Change.
class _DashLine extends StatelessWidget {
  const _DashLine();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 1,
        width: double.infinity,
        child: CustomPaint(painter: _DashLinePainter()),
      );
}

class _DashLinePainter extends CustomPainter {
  const _DashLinePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = YColor.hairline
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, 0), p);
      x += 8;
    }
  }

  @override
  bool shouldRepaint(_DashLinePainter old) => false;
}

/// Dashed rounded-rectangle border (used for the Senior/PWD discount button).
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, this.radius = 12});
  final Color color;
  final double radius;
  static const double dash = 5;
  static const double gap = 4;
  static const double strokeWidth = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(strokeWidth / 2),
        Radius.circular(radius));
    final dashed = Path();
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        dashed.addPath(metric.extractPath(dist, dist + dash), Offset.zero);
        dist += dash + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
