import 'package:flutter/material.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// App-theme dropdown that matches the look of [KeyboardAccessoryField] —
/// same 48px height, surface1 fill, hairline border, brandDeep all-caps
/// label.
///
/// Implementation note: we don't use [DropdownButton]. Its open menu width
/// is locked to the button width, so a full-width field opens an obnoxiously
/// wide popup with empty space on the right. Instead the field is a
/// tap-target that opens a [showMenu] popup anchored to the field's
/// left edge — the menu auto-sizes to the longest item's content.
class ThemedDropdown<T> extends StatelessWidget {
  const ThemedDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.hint,
    this.iconOf,
    this.enabled = true,
  });

  /// All-caps label rendered above the field.
  final String label;

  /// Currently-selected option, or null when nothing is picked yet.
  final T? value;

  /// Available options. Order is preserved in the menu.
  final List<T> items;

  /// Renders the visible text for an option both in the field and the menu.
  final String Function(T) labelOf;

  /// Optional leading Material icon per option.
  final IconData? Function(T)? iconOf;

  /// Hint text rendered when [value] is null.
  final String? hint;

  final ValueChanged<T?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: YFont.caption().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: YColor.brandDeep,
            )),
        const SizedBox(height: 6),
        _ThemedDropdownField<T>(
          value: value,
          items: items,
          labelOf: labelOf,
          iconOf: iconOf,
          hint: hint,
          enabled: enabled,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ThemedDropdownField<T> extends StatefulWidget {
  const _ThemedDropdownField({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.iconOf,
    required this.hint,
    required this.enabled,
    required this.onChanged,
  });

  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;
  final String? hint;
  final bool enabled;
  final ValueChanged<T?> onChanged;

  @override
  State<_ThemedDropdownField<T>> createState() =>
      _ThemedDropdownFieldState<T>();
}

class _ThemedDropdownFieldState<T> extends State<_ThemedDropdownField<T>> {
  /// Opens a [showMenu] popup anchored to the field's bottom-left. The menu
  /// auto-sizes to the longest item's content, unlike DropdownButton which
  /// would inflate to the button width.
  Future<void> _open() async {
    if (!widget.enabled || widget.items.isEmpty) return;
    // Drop any field focus first so the popup route has nothing to restore on
    // close — otherwise it would re-focus the last text field and re-pop its
    // KeyboardAccessoryField card (looked like "the search opening").
    FocusManager.instance.primaryFocus?.unfocus();
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (renderBox == null || overlay == null) return;

    final fieldTopLeft = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    final fieldSize = renderBox.size;

    final picked = await showMenu<T>(
      context: context,
      color: YColor.surface1,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YRadius.md),
        side: const BorderSide(color: YColor.hairline),
      ),
      // Open just below the field, aligned to its left edge.
      position: RelativeRect.fromLTRB(
        fieldTopLeft.dx,
        fieldTopLeft.dy + fieldSize.height + 4,
        overlay.size.width - fieldTopLeft.dx - fieldSize.width,
        0,
      ),
      // Constrain so very long lists don't run off-screen.
      constraints: const BoxConstraints(
        minWidth: 160,
        maxHeight: 360,
      ),
      items: [
        for (final it in widget.items)
          PopupMenuItem<T>(
            value: it,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _ItemRow(
              icon: widget.iconOf?.call(it),
              label: widget.labelOf(it),
            ),
          ),
      ],
    );
    if (picked != null) widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.value != null && widget.items.contains(widget.value);
    final iconData = hasValue ? widget.iconOf?.call(widget.value as T) : null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(children: [
          if (iconData != null) ...[
            Icon(iconData, size: 16, color: YColor.brandDeep),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              hasValue
                  ? widget.labelOf(widget.value as T)
                  : (widget.hint ?? 'Pick'),
              style: YFont.bodyStrong().copyWith(
                fontSize: 13,
                color: hasValue ? YColor.ink : YColor.inkMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.expand_more, size: 18, color: YColor.inkMuted),
        ]),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({this.icon, required this.label});
  final IconData? icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(
        label,
        style: YFont.bodyStrong().copyWith(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: YColor.brandDeep),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: YFont.bodyStrong().copyWith(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
