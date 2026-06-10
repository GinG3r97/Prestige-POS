import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/typography.dart';
import '../../models/inventory.dart';
import '../widgets/keyboard_overlay.dart';

/// Recipe ingredient picker — taps the row to pop a [KeyboardOverlay] glass card
/// with a live search; matching inventory items list ABOVE the input.
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

class _IngredientSearchFieldState extends State<IngredientSearchField> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<InventoryItem> _matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return widget.items;
    return widget.items
        .where((it) =>
            it.name.toLowerCase().contains(s) ||
            it.category.toLowerCase().contains(s))
        .toList();
  }

  void _select(InventoryItem it, VoidCallback dismiss) {
    FocusManager.instance.primaryFocus?.unfocus();
    dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelect(it.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item =
        widget.items.where((i) => i.id == widget.selectedId).firstOrNull;
    return KeyboardOverlay(
      onOpen: () => _ctrl.clear(),
      triggerBuilder: (ctx, open) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
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
      ),
      cardBuilder: (ctx, cardFocus, dismiss) =>
          ValueListenableBuilder<TextEditingValue>(
        valueListenable: _ctrl,
        builder: (_, value, __) {
          final q = value.text.trim();
          // Don't render the whole list on open — only once they type, so the
          // card pops up instantly with the keyboard.
          final matches =
              q.isEmpty ? const <InventoryItem>[] : _matches(value.text);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (q.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  child: Text('Type to search ingredients',
                      style: YFont.body().copyWith(color: YColor.inkMuted)),
                )
              else if (matches.isEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                  child: Text('No ingredients match',
                      style: YFont.body().copyWith(color: YColor.inkMuted)),
                )
              else if (matches.length <= 4)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final it in matches) _resultCell(it, dismiss),
                  ],
                )
              else
                SizedBox(
                  height: 216,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: matches.length,
                    itemBuilder: (_, i) => _resultCell(matches[i], dismiss),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                  height: 1, color: YColor.hairline.withValues(alpha: 0.6)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.search, size: 22, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: cardFocus,
                    autofocus: false,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.search,
                    cursorColor: YColor.brand,
                    onSubmitted: (v) {
                      final m = _matches(v);
                      if (m.isNotEmpty) {
                        _select(m.first, dismiss);
                      } else {
                        dismiss();
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
                  onTap: dismiss,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: YColor.brand,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('Done',
                        style: YFont.bodyStrong()
                            .copyWith(color: Colors.white, fontSize: 13)),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _resultCell(InventoryItem it, VoidCallback dismiss) {
    final selected = it.id == widget.selectedId;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _select(it, dismiss),
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
}
