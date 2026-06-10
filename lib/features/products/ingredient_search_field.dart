import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/responsive_scaler.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';

/// Recipe ingredient picker that uses the Sell-page search technique: tapping
/// the row pops a glass card above the keyboard with a live search and matching
/// inventory items listed ABOVE the input. Tapping a result selects it.
class IngredientSearchField extends StatefulWidget {
  const IngredientSearchField({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final List<InventoryItem> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  State<IngredientSearchField> createState() => _IngredientSearchFieldState();
}

class _IngredientSearchFieldState extends State<IngredientSearchField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _cardFocus = FocusNode();
  final TextEditingController _ctrl = TextEditingController();
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
    _ctrl.dispose();
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

  void _open() {
    _ctrl.clear();
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

  List<InventoryItem> _matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return widget.items;
    return widget.items
        .where((it) =>
            it.name.toLowerCase().contains(s) ||
            it.category.toLowerCase().contains(s))
        .toList();
  }

  void _select(InventoryItem it) {
    FocusManager.instance.primaryFocus?.unfocus();
    _dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelect(it.id);
    });
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
                onTap: _dismiss,
                // Plain dim (no BackdropFilter) — blur was the source of the
                // open lag while the keyboard animates up.
                child: Container(
                    color: Colors.black.withValues(alpha: 0.3 * progress)),
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
      child: _card(),
    );
  }

  Widget _card() {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        constraints: const BoxConstraints(maxWidth: 580, minWidth: 380),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: YColor.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (_, value, __) {
                final q = value.text.trim();
                // Don't render the whole list on open — only once they type,
                // so the card pops up instantly with the keyboard.
                final matches =
                    q.isEmpty ? const <InventoryItem>[] : _matches(value.text);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (q.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 4),
                        child: Text('Type to search ingredients',
                            style:
                                YFont.body().copyWith(color: YColor.inkMuted)),
                      )
                    else if (matches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 4),
                        child: Text('No ingredients match',
                            style:
                                YFont.body().copyWith(color: YColor.inkMuted)),
                      )
                    else if (matches.length <= 4)
                      // Few results — size exactly to the rows (no gap).
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final it in matches) _resultCell(it),
                        ],
                      )
                    else
                      // Many — cap the height and scroll.
                      SizedBox(
                        height: 216,
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: matches.length,
                          itemBuilder: (_, i) => _resultCell(matches[i]),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                        height: 1,
                        color: YColor.hairline.withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.search,
                          size: 22, color: YColor.brandDeep),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          focusNode: _cardFocus,
                          autofocus: false,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.search,
                          cursorColor: YColor.brand,
                          onSubmitted: (v) {
                            final m = _matches(v);
                            if (m.isNotEmpty) {
                              _select(m.first);
                            } else {
                              _dismiss();
                            }
                          },
                          style: YFont.titleMD().copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: YColor.brand,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'Search ingredients',
                            hintStyle: YFont.titleMD().copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: YColor.inkSubtle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _dismiss,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: YColor.brand,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('Done',
                              style: YFont.bodyStrong().copyWith(
                                  color: Colors.white, fontSize: 13)),
                        ),
                      ),
                    ]),
                  ],
                );
              },
            ),
      ),
    );
  }

  Widget _resultCell(InventoryItem it) {
    final selected = it.id == widget.selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _select(it),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                materialIconForName(it.name) ?? Icons.inventory_2_outlined,
                size: 19,
                color: YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.bodyStrong().copyWith(fontSize: 14)),
                Text(
                    '${it.category} · ${it.currentStock.toStringAsFixed(0)} ${it.displayUnit} in stock',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.caption()),
              ],
            ),
          ),
          if (selected)
            const Icon(Icons.check_circle, size: 18, color: YColor.brand),
        ]),
      ),
    );
  }

  // ── Trigger row (icon · name · chevron) ──────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final item =
        widget.items.where((i) => i.id == widget.selectedId).firstOrNull;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
              materialIconForName(item?.name ?? '') ??
                  Icons.inventory_2_outlined,
              size: 18,
              color: YColor.brandDeep),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item?.name ?? 'Click to add ingredient',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: YFont.bodyStrong().copyWith(
                fontSize: 13.5,
                color: item == null ? YColor.inkSubtle : YColor.ink),
          ),
        ),
      ]),
    );
  }
}
