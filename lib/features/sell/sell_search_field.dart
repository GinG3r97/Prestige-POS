import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/responsive_scaler.dart';
import '../../design_system/typography.dart';
import '../../models/catalog.dart';

/// A small Sell-page search pill. When focused it pops a glass card above the
/// keyboard (same technique as `KeyboardAccessoryField`) that shows the live,
/// editable query plus up to [_kMaxInline] matching products ABOVE the input.
///
/// The twist over the plain accessory field:
///  - matches render in the card, above the field;
///  - tapping a match exits search and opens that product ([onSelect]);
///  - when there are more than [_kMaxInline] matches a "Show all" button (and
///    the "Done" pill) hide the keyboard and hand the whole result set to the
///    grid via [onShowMore];
///  - tapping the dimmed backdrop cancels and clears ([onClear]).
class SellSearchField extends StatefulWidget {
  const SellSearchField({
    super.key,
    required this.controller,
    required this.products,
    required this.onSelect,
    required this.onShowMore,
    required this.onClear,
    this.activeQuery = '',
  });

  final TextEditingController controller;

  /// All products the search may match (already filtered to "available").
  final List<CafeItem> products;

  /// Tapped a result → exit search and open its detail sheet.
  final ValueChanged<CafeItem> onSelect;

  /// "Show all" / "Done" → hide the keyboard and apply the query to the grid.
  final ValueChanged<String> onShowMore;

  /// Backdrop tap / clear (×) → drop the query, back to browsing.
  final VoidCallback onClear;

  /// The query currently applied to the grid (set after "Show all"). Drives the
  /// inline pill's clear (×) affordance.
  final String activeQuery;

  @override
  State<SellSearchField> createState() => _SellSearchFieldState();
}

class _SellSearchFieldState extends State<SellSearchField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _cardFocus = FocusNode();
  late final AnimationController _anim;
  OverlayEntry? _entry;

  static const int _kMaxInline = 3;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _focusNode.addListener(_onFocusChange);
    _cardFocus.addListener(_onFocusChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.removeListener(_onFocusChange);
    _cardFocus.removeListener(_onFocusChange);
    _focusNode.dispose();
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
    if (_focusNode.hasFocus || _cardFocus.hasFocus) {
      _show();
      // Hand editing to the card's field (above the keyboard) once shown.
      if (_focusNode.hasFocus && !_cardFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _entry != null && _focusNode.hasFocus) {
            _cardFocus.requestFocus();
          }
        });
      }
    } else {
      // Defer — focus may just be transferring between the pill and the card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_focusNode.hasFocus && !_cardFocus.hasFocus) _hide();
      });
    }
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

  void _dismiss() {
    _cardFocus.unfocus();
    _focusNode.unfocus();
  }

  List<CafeItem> _matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    return widget.products
        .where((p) =>
            p.name.toLowerCase().contains(s) ||
            p.subtitle.toLowerCase().contains(s) ||
            p.categoryName.toLowerCase().contains(s))
        .toList();
  }

  void _selectProduct(CafeItem item) {
    _dismiss();
    // Open the detail sheet once the overlay has begun tearing down.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelect(item);
    });
  }

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
        // Real keyboard height from the platform view (MediaQuery insets are
        // zeroed app-wide); convert device px into the scaler's design space.
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
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, value, _) {
                final q = value.text;
                final matches = _matches(q);
                final inline = matches.take(_kMaxInline).toList();
                final more = matches.length - inline.length;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Results live ABOVE the input ──
                    if (q.trim().isEmpty)
                      _hintRow('Type to search your menu')
                    else if (matches.isEmpty)
                      _hintRow('No products match "${q.trim()}"')
                    else ...[
                      for (final p in inline) _resultRow(p),
                      if (more > 0) _showAllButton(matches.length, q),
                    ],
                    const SizedBox(height: 8),
                    Container(height: 1, color: YColor.hairline.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    // ── The live, editable query field + Done ──
                    Row(children: [
                      const Icon(Icons.search,
                          size: 22, color: YColor.brandDeep),
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
                            final m = _matches(v);
                            if (m.length == 1) {
                              _selectProduct(m.first);
                            } else if (m.isNotEmpty) {
                              _showMore(v);
                            } else {
                              _cancel();
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
                            hintText: 'Search products',
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _hintRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Text(text,
          style: YFont.body().copyWith(color: YColor.inkMuted)),
    );
  }

  Widget _resultRow(CafeItem p) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _selectProduct(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: NameIconOrEmoji(
                  name: p.name, iconName: p.iconName, iconSize: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.bodyStrong().copyWith(fontSize: 14)),
                if (p.categoryName.trim().isNotEmpty)
                  Text(p.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YFont.caption()),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(p.basePrice.formatted,
              style: YFont.bodyStrong()
                  .copyWith(fontSize: 13.5, color: YColor.brandDeep)),
        ]),
      ),
    );
  }

  Widget _showAllButton(int total, String q) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showMore(q),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          child: Text('Show all $total results  →',
              style: YFont.bodyStrong()
                  .copyWith(color: YColor.brandDeep, fontSize: 13)),
        ),
      ),
    );
  }

  // ── Inline pill (lives in the Sell header) ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.activeQuery.trim().isNotEmpty;
    return SizedBox(
      height: 38,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autocorrect: false,
        enableSuggestions: false,
        textAlignVertical: TextAlignVertical.center,
        style: YFont.body().copyWith(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          hintStyle: YFont.body().copyWith(fontSize: 13, color: YColor.inkSubtle),
          prefixIcon:
              const Icon(Icons.search, size: 18, color: YColor.inkMuted),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          suffixIcon: hasQuery
              ? GestureDetector(
                  onTap: () {
                    widget.controller.clear();
                    widget.onClear();
                  },
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: YColor.inkMuted),
                )
              : null,
          suffixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 36),
          filled: true,
          fillColor: YColor.surface2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: YColor.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: YColor.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: YColor.brand),
          ),
        ),
      ),
    );
  }
}
