import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/responsive_scaler.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// Staff-page search — the same technique as the Sell page's [SellSearchField].
/// A small square button; when tapped it pops a glass card above the keyboard
/// with the live, editable query. Submitting / "Done" applies the query to the
/// staff list; the backdrop / × cancels. (No results inside the card.)
class EmployeeSearchField extends StatefulWidget {
  const EmployeeSearchField({
    super.key,
    required this.controller,
    required this.onShowMore,
    required this.onClear,
    this.activeQuery = '',
  });

  final TextEditingController controller;
  final ValueChanged<String> onShowMore;
  final VoidCallback onClear;
  final String activeQuery;

  @override
  State<EmployeeSearchField> createState() => _EmployeeSearchFieldState();
}

class _EmployeeSearchFieldState extends State<EmployeeSearchField>
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

  void _openSearch() {
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

  void _showMore(String q) {
    _dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShowMore(q.trim());
    });
  }

  void _cancel() {
    widget.controller.clear();
    widget.onClear();
    _dismiss();
  }

  // ── Overlay ────────────────────────────────────────────────────────────
  Widget _buildOverlay(BuildContext ctx) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final progress = _anim.value.clamp(0.0, 1.0);
        final t = Curves.easeOutBack.transform(progress);
        final view = View.of(ctx);
        final keyboardHeight = view.viewInsets.bottom /
            view.devicePixelRatio /
            ResponsiveScaler.currentScale;

        return Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: progress < 0.5,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancel,
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                      sigmaX: 12 * progress, sigmaY: 12 * progress),
                  child: Container(
                      color: Colors.black.withValues(alpha: 0.18 * progress)),
                ),
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
      child: _accessoryCard(),
    );
  }

  Widget _accessoryCard() {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            constraints: const BoxConstraints(maxWidth: 540, minWidth: 360),
            decoration: BoxDecoration(
              color: YColor.surface1.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 22, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _cardFocus,
                  autofocus: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.search,
                  cursorColor: YColor.brand,
                  onSubmitted: (v) {
                    final qq = v.trim();
                    if (qq.isEmpty) {
                      _cancel();
                    } else {
                      _showMore(qq);
                    }
                  },
                  style: YFont.titleMD().copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: YColor.brand,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search staff',
                    hintStyle: YFont.titleMD().copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: YColor.inkSubtle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final qq = widget.controller.text.trim();
                  if (qq.isEmpty) {
                    _cancel();
                  } else {
                    _showMore(qq);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 7),
                  decoration: BoxDecoration(
                    color: YColor.brand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Done',
                    style: YFont.bodyStrong()
                        .copyWith(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Square header button (sits beside the role dropdown + Add) ───────────
  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.activeQuery.trim().isNotEmpty;
    return GestureDetector(
      onTap: hasQuery
          ? () {
              widget.controller.clear();
              widget.onClear();
            }
          : _openSearch,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hasQuery ? YColor.brand : YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(
              color: hasQuery ? YColor.brand : YColor.hairline),
        ),
        child: Icon(
          hasQuery ? Icons.close_rounded : Icons.search,
          size: 20,
          color: hasQuery ? Colors.white : YColor.brandDeep,
        ),
      ),
    );
  }
}
