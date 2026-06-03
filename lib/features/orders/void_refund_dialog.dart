import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import '../../models/money.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// Whether the cashier is cancelling the sale (void) or returning the
/// customer's money (refund). Both restore the recipe's ingredients to
/// inventory and need an Owner/Manager PIN to approve.
enum ReverseKind { voidOrder, refund }

extension _ReverseKindX on ReverseKind {
  String get verb => this == ReverseKind.refund ? 'Refund' : 'Void';
  String get pastTense => this == ReverseKind.refund ? 'refunded' : 'voided';
  Color get tone => this == ReverseKind.refund ? YColor.danger : YColor.inkMuted;
  List<String> get reasons => this == ReverseKind.refund
      ? const [
          'Wrong item',
          'Customer changed mind',
          'Damaged / spoiled',
          'Overcharged',
          'Other',
        ]
      : const [
          'Wrong item',
          'Wrong quantity',
          'Double charge',
          'Cancelled by customer',
          'Test / training',
          'Other',
        ];
}

/// Shows the void/refund authorization dialog. Returns true when the order
/// (or a single line, if [orderLineId] is given) was reversed. Collects a
/// reason + an Owner/Manager PIN, then calls the matching [AppState] method
/// (which restocks ingredients server-side).
Future<bool> showReverseOrderDialog(
  BuildContext context, {
  required ReverseKind kind,
  required String orderId,
  required String orderLabel,
  required Money total,
  String? orderLineId,
  String? itemName,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    // Strip the keyboard inset so the dialog stays fixed (doesn't shrink or
    // jump up) when the soft keyboard appears. The PIN field's accessory
    // card already floats the typed value above the keyboard.
    builder: (ctx) => MediaQuery.removeViewInsets(
      context: ctx,
      removeBottom: true,
      child: _ReverseOrderDialog(
        kind: kind,
        orderId: orderId,
        orderLabel: orderLabel,
        total: total,
        orderLineId: orderLineId,
        itemName: itemName,
      ),
    ),
  );
  return ok ?? false;
}

class _ReverseOrderDialog extends StatefulWidget {
  const _ReverseOrderDialog({
    required this.kind,
    required this.orderId,
    required this.orderLabel,
    required this.total,
    this.orderLineId,
    this.itemName,
  });

  final ReverseKind kind;
  final String orderId;
  final String orderLabel;
  final Money total;

  /// When set, the dialog reverses just this one line instead of the whole
  /// order. [itemName] is shown in the title.
  final String? orderLineId;
  final String? itemName;

  @override
  State<_ReverseOrderDialog> createState() => _ReverseOrderDialogState();
}

class _ReverseOrderDialogState extends State<_ReverseOrderDialog> {
  final _pin = TextEditingController();
  final _note = TextEditingController();
  String? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isOther => _reason == 'Other';

  Future<void> _confirm() async {
    final pin = _pin.text.trim();
    if (_reason == null) {
      setState(() => _error = 'Pick a reason first.');
      return;
    }
    final reason = _isOther
        ? (_note.text.trim().isEmpty ? 'Other' : _note.text.trim())
        : _reason!;
    if (pin.length < 4) {
      setState(() => _error = 'Enter the Owner or Manager PIN.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final state = context.read<AppState>();
    final String? err;
    if (widget.orderLineId != null) {
      err = await state.reverseOrderLine(
        orderLineId: widget.orderLineId!,
        kind: widget.kind == ReverseKind.refund ? 'refund' : 'void',
        reason: reason,
        authorizerPin: pin,
      );
    } else if (widget.kind == ReverseKind.refund) {
      err = await state.refundOrder(
          orderId: widget.orderId, reason: reason, authorizerPin: pin);
    } else {
      err = await state.voidOrder(
          orderId: widget.orderId, reason: reason, authorizerPin: pin);
    }

    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }

    Navigator.of(context).pop(true);
    PushToast.show(
      context,
      title: widget.orderLineId != null
          ? '${widget.itemName ?? 'Item'} ${widget.kind.pastTense}'
          : 'Order ${widget.orderLabel} ${widget.kind.pastTense}',
      subtitle: 'Stock returned to inventory.',
      leadingIcon: Icons.check_circle_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind;
    final screen = MediaQuery.sizeOf(context);
    // Responsive: fit comfortably on an iPad mini and cap on a Pro. The
    // body scrolls so it can never overflow when the keyboard is up.
    final dialogWidth = math.min(380.0, screen.width - 64);
    final maxBodyHeight = screen.height * 0.6;

    return AlertDialog(
      backgroundColor: YColor.surface1,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: k.tone.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            k == ReverseKind.refund ? Icons.undo_outlined : Icons.block_outlined,
            color: k.tone,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.orderLineId != null
                    ? '${k.verb} "${widget.itemName ?? 'item'}"'
                    : '${k.verb} order ${widget.orderLabel}',
                style: YFont.titleMD(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(widget.total.formatted,
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ),
        ),
      ]),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxBodyHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reason', style: YFont.caption()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in k.reasons) _reasonChip(r, k.tone),
                  ],
                ),
                if (_isOther) ...[
                  const SizedBox(height: 12),
                  KeyboardAccessoryField(
                    controller: _note,
                    accessoryLabel: 'Reason note',
                    hint: 'Describe what happened',
                  ),
                ],
                const SizedBox(height: 18),
                KeyboardAccessoryField(
                  controller: _pin,
                  accessoryLabel: 'Owner / Manager PIN',
                  label: 'Owner or Manager PIN',
                  hint: '••••',
                  obscure: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  textStyle: YFont.body().copyWith(letterSpacing: 6),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: YColor.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style:
                              YFont.caption().copyWith(color: YColor.danger)),
                    ),
                  ]),
                ],
                const SizedBox(height: 10),
                Text(
                  'A manager or owner must approve. The ingredients in this '
                  'order go back into stock.',
                  style: YFont.caption().copyWith(color: YColor.inkMuted),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _confirm,
          style: ElevatedButton.styleFrom(
            backgroundColor: k.tone,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text('${k.verb} order'),
        ),
      ],
    );
  }

  Widget _reasonChip(String label, Color tone) {
    final selected = _reason == label;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _reason = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? tone.withValues(alpha: 0.14) : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? tone : YColor.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(
            fontSize: 13,
            color: selected ? tone : YColor.ink,
          ),
        ),
      ),
    );
  }
}
