import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/responsive_scaler.dart';

/// The shared "glass card above the keyboard" used by the Sell / Employee /
/// Ingredient search fields. Owns the overlay entry, the pop animation, the
/// card focus node, and the keyboard-tracking layout — callers only supply the
/// trigger widget and the card's inner content.
///
/// Tapping the trigger's `open` callback raises the soft keyboard and floats a
/// rounded card just above it; the card hosts the one real editable field
/// (attach [cardFocus] to it). [dismiss] closes the card.
class KeyboardOverlay extends StatefulWidget {
  const KeyboardOverlay({
    super.key,
    required this.triggerBuilder,
    required this.cardBuilder,
    this.blur = false,
    this.onOpen,
  });

  /// The always-visible trigger. Call [open] to pop the card.
  final Widget Function(BuildContext context, VoidCallback open) triggerBuilder;

  /// The card's inner content. Attach [cardFocus] to the real TextField and
  /// call [dismiss] to close.
  final Widget Function(
      BuildContext context, FocusNode cardFocus, VoidCallback dismiss) cardBuilder;

  /// Frost the backdrop + card (heavier GPU). Off for low-lag pickers.
  final bool blur;

  /// Called right before the card opens (e.g. clear the query controller).
  final VoidCallback? onOpen;

  @override
  State<KeyboardOverlay> createState() => _KeyboardOverlayState();
}

class _KeyboardOverlayState extends State<KeyboardOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _cardFocus = FocusNode();
  late final AnimationController _anim;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _cardFocus.addListener(_onFocusChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cardFocus.removeListener(_onFocusChange);
    _cardFocus.dispose();
    _entry?.remove();
    _entry = null;
    _anim.dispose();
    super.dispose();
  }

  // The soft keyboard animates up over ~250ms; rebuild the overlay as its
  // height changes so the card tracks it with a consistent gap above it.
  @override
  void didChangeMetrics() => _entry?.markNeedsBuild();

  void _onFocusChange() {
    if (_cardFocus.hasFocus) {
      _show();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_cardFocus.hasFocus) _hide();
      });
    }
  }

  void _open() {
    widget.onOpen?.call();
    _show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _entry != null) _cardFocus.requestFocus();
    });
  }

  void _show() {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _anim.forward(from: 0);
  }

  Future<void> _hide() async {
    if (_entry == null) return;
    await _anim.reverse();
    _entry?.remove();
    _entry = null;
  }

  void _dismiss() => _cardFocus.unfocus();

  Widget _buildOverlay(BuildContext ctx) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final progress = _anim.value.clamp(0.0, 1.0);
        final t = Curves.easeOutBack.transform(progress);
        // Real keyboard height from the platform view (MediaQuery insets are
        // zeroed app-wide); convert device px into the scaler's design space.
        final view = View.of(ctx);
        final keyboardHeight = view.viewInsets.bottom /
            view.devicePixelRatio /
            ResponsiveScaler.currentScale;

        Widget dim = Container(
            color: Colors.black
                .withValues(alpha: (widget.blur ? 0.18 : 0.3) * progress));
        if (widget.blur) {
          dim = BackdropFilter(
            filter:
                ImageFilter.blur(sigmaX: 12 * progress, sigmaY: 12 * progress),
            child: dim,
          );
        }

        return Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: progress < 0.5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: dim,
              ),
            ),
          ),
          Positioned(
            bottom: keyboardHeight + 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: progress < 0.5,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 60),
                  child: Transform.scale(
                    scale: 0.85 + (t * 0.15),
                    child: Opacity(opacity: progress, child: child),
                  ),
                ),
              ),
            ),
          ),
        ]);
      },
      child: _frame(),
    );
  }

  Widget _frame() {
    final inner = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      constraints: const BoxConstraints(maxWidth: 580, minWidth: 380),
      decoration: BoxDecoration(
        color: widget.blur
            ? YColor.surface1.withValues(alpha: 0.85)
            : YColor.surface1,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: widget.blur
                ? Colors.white.withValues(alpha: 0.5)
                : YColor.hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: widget.cardBuilder(context, _cardFocus, _dismiss),
    );
    final card = Material(color: Colors.transparent, child: inner);
    if (!widget.blur) return card;
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: inner,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.triggerBuilder(context, _open);
}
