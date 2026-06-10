import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/keyboard_overlay.dart';

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

class _EmployeeSearchFieldState extends State<EmployeeSearchField> {
  void _showMore(String q, VoidCallback dismiss) {
    dismiss();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShowMore(q.trim());
    });
  }

  void _cancel(VoidCallback dismiss) {
    widget.controller.clear();
    widget.onClear();
    dismiss();
  }

  // ── Square header button (sits beside the role dropdown + Add) ───────────
  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.activeQuery.trim().isNotEmpty;
    return KeyboardOverlay(
      blur: true,
      triggerBuilder: (ctx, open) => GestureDetector(
        onTap: hasQuery
            ? () {
                widget.controller.clear();
                widget.onClear();
              }
            : open,
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
      ),
      cardBuilder: (ctx, cardFocus, dismiss) => Row(children: [
        const Icon(Icons.search, size: 22, color: YColor.brandDeep),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: widget.controller,
            focusNode: cardFocus,
            autofocus: false,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            cursorColor: YColor.brand,
            onSubmitted: (v) {
              final qq = v.trim();
              if (qq.isEmpty) {
                _cancel(dismiss);
              } else {
                _showMore(qq, dismiss);
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
              _cancel(dismiss);
            } else {
              _showMore(qq, dismiss);
            }
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
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
    );
  }
}
