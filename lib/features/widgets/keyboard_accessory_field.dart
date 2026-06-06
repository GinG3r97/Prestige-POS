import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/colors.dart';
import '../../design_system/responsive_scaler.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// A quick-action chip shown inside the floating accessory.
class KeyboardQuickAction {
  final String label;
  final String value;
  const KeyboardQuickAction(this.label, this.value);
}

/// Standard formatter list for money / hours fields — allows digits
/// and at most one decimal point. Rejects letters, symbols, and a
/// second `.` at the keystroke level so a user with a hardware
/// keyboard (or autofill) can't sneak garbage past the soft
/// number-keyboard.
final List<TextInputFormatter> moneyInputFormatters = [
  TextInputFormatter.withFunction((oldValue, newValue) {
    final t = newValue.text;
    if (t.isEmpty) return newValue;
    return RegExp(r'^\d*\.?\d*$').hasMatch(t) ? newValue : oldValue;
  }),
];

/// Same as [moneyInputFormatters] but disallows the decimal point —
/// for "whole units only" fields (e.g. a count of passes).
final List<TextInputFormatter> wholeNumberInputFormatters = [
  FilteringTextInputFormatter.digitsOnly,
];

/// A TextField wrapper that pops a glass card above the keyboard when focused —
/// shows the field's eyebrow label and a live preview of what the user types.
///
/// Drop-in replacement for `TextField` / `TextFormField` plus a label.
class KeyboardAccessoryField extends StatefulWidget {
  const KeyboardAccessoryField({
    super.key,
    required this.controller,
    required this.accessoryLabel,
    this.label,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.onChanged,
    this.formatPreview,
    this.quickActions,
    this.maxLines = 1,
    this.trailing,
    this.fillColor,
    this.borderColor,
    this.maxLength,
    this.textStyle,
    this.suffix,
    this.contentPadding,
    this.textAlign = TextAlign.start,
    this.onFocusLost,
    this.isDense = false,
    this.inputFormatters,
  });

  final TextEditingController controller;

  /// Eyebrow label shown in the accessory card (e.g., "EMAIL", "BUSINESS NAME").
  /// Will be auto-uppercased.
  final String accessoryLabel;

  /// Optional inline label rendered above the field.
  final String? label;

  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;

  /// Optional formatter for the preview value (e.g., format raw "500" → "₱500.00").
  final String Function(String value)? formatPreview;

  /// Optional quick-action chips rendered inside the accessory.
  final List<KeyboardQuickAction>? quickActions;

  final int maxLines;

  /// Optional widget rendered next to the inline label (e.g., a "REQUIRED" badge).
  final Widget? trailing;

  /// Override the field's fill colour. Defaults to [YColor.surface3].
  final Color? fillColor;

  /// Override the field's border colour. If null, the field has no border.
  final Color? borderColor;

  /// Optional max-length cap (counter is hidden).
  final int? maxLength;

  /// Optional text style override (e.g., monospace for PIN entry).
  final TextStyle? textStyle;

  /// Optional widget shown inside the field on the right (e.g., visibility toggle).
  final Widget? suffix;

  /// Optional content padding override.
  final EdgeInsetsGeometry? contentPadding;

  /// Horizontal alignment of the typed text inside the field. Defaults
  /// to start; pass [TextAlign.center] for grid cells where the value
  /// is short and should be centred (e.g. daily-hours timesheet).
  final TextAlign textAlign;

  /// Optional callback fired when the field loses focus (user taps
  /// outside, dismisses keyboard, etc). Useful for committing edits
  /// once instead of on every keystroke — avoids a network round-trip
  /// per character typed.
  final VoidCallback? onFocusLost;

  /// Collapse the field's vertical padding so it fits inside tight
  /// grid cells (e.g. daily-hours timesheet). Mirrors the standard
  /// Material `InputDecoration.isDense` flag.
  final bool isDense;

  /// Optional list of input formatters applied before the keystroke
  /// reaches the controller. Use [moneyInputFormatters] for digits-
  /// only-with-decimal fields like payroll bonuses & hours.
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<KeyboardAccessoryField> createState() => _KeyboardAccessoryFieldState();
}

class _KeyboardAccessoryFieldState extends State<KeyboardAccessoryField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  // Plain text fields hand editing to a real field inside the accessory card
  // (so the cursor, selection, copy/paste + multi-line scroll all work up
  // there). Money/preview fields keep the read-only formatted preview instead.
  final FocusNode _cardFocus = FocusNode();
  bool get _cardEditable => widget.formatPreview == null && !widget.obscure;
  late final AnimationController _anim;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
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
  // height changes so the card tracks it and lands with a consistent gap above
  // it (instead of occasionally sitting right on the keyboard).
  @override
  void didChangeMetrics() => _entry?.markNeedsBuild();

  void _onFocusChange() {
    if (_focusNode.hasFocus || _cardFocus.hasFocus) {
      _show();
      // Hand editing to the card's field (above the keyboard) once shown.
      if (_cardEditable && _focusNode.hasFocus && !_cardFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _entry != null && _focusNode.hasFocus) {
            _cardFocus.requestFocus();
          }
        });
      }
    } else {
      // Defer — focus may just be transferring between the field and the card
      // this frame. Only commit/hide once both are genuinely unfocused.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_focusNode.hasFocus && !_cardFocus.hasFocus) {
          _hide();
          widget.onFocusLost?.call();
        }
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

  Widget _buildOverlay(BuildContext ctx) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final progress = _anim.value.clamp(0.0, 1.0);
        final t = Curves.easeOutBack.transform(progress);
        // Read the REAL keyboard height from the platform view, not from
        // MediaQuery — the app zeroes MediaQuery.viewInsets globally so nothing
        // shrinks for the keyboard. The card renders inside the responsive
        // scaler's transformed overlay, so convert the device-pixel height into
        // that design space (÷ currentScale) to land exactly on the keyboard.
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
                onTap: () => _focusNode.unfocus(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 12 * progress,
                    sigmaY: 12 * progress,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.18 * progress),
                  ),
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
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
            constraints: const BoxConstraints(maxWidth: 520, minWidth: 320),
            decoration: BoxDecoration(
              color: YColor.surface1.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 36,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Label on the left, a Done button top-right — the natural,
                // always-visible spot to dismiss/commit above the keyboard.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.accessoryLabel.toUpperCase(),
                        style: YFont.caption().copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                          color: YColor.brandDeep,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _cardFocus.unfocus();
                        _focusNode.unfocus();
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
                          style: YFont.bodyStrong().copyWith(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_cardEditable)
                  // The live, editable field — cursor, tap-to-move-caret,
                  // long-press select/copy/paste, and multi-line scroll all
                  // work here, above the keyboard.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _cardFocus,
                      autofocus: false,
                      minLines: 1,
                      maxLines: widget.maxLines == 1 ? 1 : widget.maxLines,
                      keyboardType: widget.maxLines == 1
                          ? widget.keyboardType
                          : TextInputType.multiline,
                      textInputAction: widget.maxLines == 1
                          ? null
                          : TextInputAction.newline,
                      inputFormatters: widget.inputFormatters,
                      autocorrect: false,
                      enableSuggestions: false,
                      cursorColor: YColor.brand,
                      // Single-line cards stay centred for the big-value look;
                      // multi-line follows the field's textAlign (so the receipt
                      // header/footer match their centred/left setting).
                      textAlign: widget.maxLines == 1
                          ? TextAlign.center
                          : widget.textAlign,
                      onChanged: widget.onChanged,
                      style: YFont.titleLG().copyWith(
                        fontSize: widget.maxLines == 1 ? 30 : 19,
                        fontWeight: FontWeight.w700,
                        color: YColor.brand,
                        height: 1.3,
                        letterSpacing: -0.4,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: widget.hint ?? '—',
                        hintStyle: YFont.titleLG().copyWith(
                          fontSize: widget.maxLines == 1 ? 30 : 19,
                          fontWeight: FontWeight.w700,
                          color: YColor.inkSubtle,
                        ),
                      ),
                    ),
                  )
                else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder: (_, value, __) {
                      final raw = value.text;
                      final preview = widget.formatPreview?.call(raw) ??
                          (widget.obscure
                              ? (raw.isEmpty ? '—' : '•' * raw.length)
                              : (raw.isEmpty ? '—' : raw));
                      final size = preview.length > 28
                          ? 20.0
                          : preview.length > 18
                              ? 26.0
                              : 36.0;
                      return Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: YFont.titleLG().copyWith(
                          fontSize: size,
                          fontWeight: FontWeight.w700,
                          color: raw.isEmpty ? YColor.inkSubtle : YColor.brand,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      );
                    },
                  ),
                if (widget.quickActions != null &&
                    widget.quickActions!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: widget.quickActions!
                        .map((qa) => _quickActionChip(qa))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActionChip(KeyboardQuickAction qa) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () {
        widget.controller.text = qa.value;
        widget.controller.selection =
            TextSelection.collapsed(offset: qa.value.length);
        widget.onChanged?.call(qa.value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: YColor.surface2.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: YColor.hairline.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          qa.label,
          style: YFont.bodyStrong().copyWith(
            color: YColor.brandDeep,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Row(children: [
            Text(widget.label!, style: YFont.bodyStrong()),
            if (widget.trailing != null) ...[
              const SizedBox(width: 8),
              widget.trailing!,
            ],
          ]),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          textAlign: widget.textAlign,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          style: widget.textStyle,
          autocorrect: false,
          enableSuggestions: false,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isDense: widget.isDense,
            hintText: widget.hint,
            hintStyle: YFont.body().copyWith(color: YColor.inkSubtle),
            counterText: widget.maxLength != null ? '' : null,
            filled: true,
            fillColor: widget.fillColor ?? YColor.surface3,
            suffixIcon: widget.suffix,
            suffixIconConstraints: widget.suffix == null
                ? null
                : const BoxConstraints(minWidth: 40, minHeight: 40),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.md),
              borderSide: widget.borderColor != null
                  ? BorderSide(color: widget.borderColor!)
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.md),
              borderSide: widget.borderColor != null
                  ? BorderSide(color: widget.borderColor!)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.md),
              borderSide: BorderSide(
                color: widget.borderColor != null
                    ? YColor.brand
                    : Colors.transparent,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.md),
              borderSide: const BorderSide(color: YColor.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(YRadius.md),
              borderSide: const BorderSide(color: YColor.danger),
            ),
            contentPadding: widget.contentPadding ??
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }
}
