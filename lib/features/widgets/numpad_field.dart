import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../auth/otp_numpad.dart';

/// A numeric input that opens a bottom-sheet NUMPAD instead of the OS keyboard.
///
/// The field looks like the app's other inputs (a caption label over a 48px
/// box) and, when tapped, pops a modal with a live value display sitting over
/// an on-screen number pad. Built for amounts/quantities (rates, salary,
/// statutory, hours, cash) so number entry is fast and identical on iOS and
/// Android. The parent owns a [TextEditingController]; this writes the result
/// back to it on Done.
class NumpadField extends StatelessWidget {
  const NumpadField({
    super.key,
    required this.controller,
    required this.label,
    this.title,
    this.hint,
    this.prefix,
    this.suffix,
    this.decimal = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;

  /// Header shown on the numpad sheet. Defaults to [label] (or 'Enter value'
  /// when the field has no inline label).
  final String? title;
  final String? hint;

  /// Small leading unit, e.g. '₱'.
  final String? prefix;

  /// Small trailing unit badge, e.g. '×', 'hr', 'min'.
  final String? suffix;

  /// Allow a decimal point (money/rates). Off for whole-number fields.
  final bool decimal;

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label.toUpperCase(),
              style: YFont.caption().copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: YColor.brandDeep,
              )),
          const SizedBox(height: 6),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(YRadius.md),
          onTap: () => _open(context),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              final has = value.text.trim().isNotEmpty;
              return Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: YColor.surface1,
                  borderRadius: BorderRadius.circular(YRadius.md),
                  border: Border.all(color: YColor.hairline),
                ),
                child: Row(children: [
                  if (prefix != null) ...[
                    Text(prefix!,
                        style: YFont.bodyStrong().copyWith(
                            fontSize: 14, color: YColor.inkMuted)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      has ? value.text : (hint ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: YFont.bodyStrong().copyWith(
                        fontSize: 14,
                        fontFamily: 'Menlo',
                        color: has ? YColor.ink : YColor.inkSubtle,
                      ),
                    ),
                  ),
                  if (suffix != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: YColor.surface3,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(suffix!.toUpperCase(),
                          style: YFont.caption().copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: YColor.inkMuted)),
                    ),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.dialpad, size: 16, color: YColor.inkMuted),
                ]),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    final result = await showNumpadSheet(
      context,
      title: title ?? (label.isEmpty ? 'Enter value' : label),
      initial: controller.text,
      decimal: decimal,
      prefix: prefix,
      suffix: suffix,
    );
    if (result != null) {
      controller.text = result;
      onChanged?.call(result);
    }
  }
}

/// Opens the numpad sheet on its own — for custom triggers (e.g. a tight grid
/// cell) that can't host a full [NumpadField] box. Returns the entered string,
/// or null if the sheet was dismissed without Done.
Future<String?> showNumpadSheet(
  BuildContext context, {
  required String title,
  String initial = '',
  bool decimal = true,
  String? prefix,
  String? suffix,
}) {
  // Never raise the OS keyboard — drop focus first so a focused text field
  // can't pop its keyboard accessory behind the sheet.
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: YColor.surface1,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _NumpadSheet(
      label: title,
      initial: initial,
      prefix: prefix,
      suffix: suffix,
      decimal: decimal,
    ),
  );
}

class _NumpadSheet extends StatefulWidget {
  const _NumpadSheet({
    required this.label,
    required this.initial,
    required this.decimal,
    this.prefix,
    this.suffix,
  });

  final String label;
  final String initial;
  final bool decimal;
  final String? prefix;
  final String? suffix;

  @override
  State<_NumpadSheet> createState() => _NumpadSheetState();
}

class _NumpadSheetState extends State<_NumpadSheet> {
  late String _v;

  @override
  void initState() {
    super.initState();
    _v = widget.initial.trim();
  }

  void _digit(String d) {
    setState(() {
      if (d == '.') {
        if (!widget.decimal || _v.contains('.')) return;
        _v = _v.isEmpty ? '0.' : '$_v.';
        return;
      }
      // Cap to 2 decimal places.
      if (_v.contains('.') && _v.split('.')[1].length >= 2) return;
      if (_v == '0') {
        _v = d; // no leading zeros
        return;
      }
      if (_v.length >= 12) return;
      _v = '$_v$d';
    });
  }

  void _back() {
    if (_v.isEmpty) return;
    setState(() => _v = _v.substring(0, _v.length - 1));
  }

  void _done() => Navigator.pop(context, _v.trim());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // grabber
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: YColor.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // header
            Row(children: [
              Text(widget.label,
                  style: YFont.titleMD().copyWith(fontSize: 16)),
              const Spacer(),
              if (_v.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _v = ''),
                  style: TextButton.styleFrom(
                    foregroundColor: YColor.inkMuted,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Clear'),
                ),
            ]),
            const SizedBox(height: 6),
            // live value display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(YRadius.lg),
                border: Border.all(color: YColor.hairline),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (widget.prefix != null) ...[
                    Text(widget.prefix!,
                        style: YFont.titleLG().copyWith(
                            fontSize: 22, color: YColor.inkMuted)),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _v.isEmpty ? '0' : _v,
                        maxLines: 1,
                        style: YFont.titleLG().copyWith(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: _v.isEmpty ? YColor.inkSubtle : YColor.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...[
                    const SizedBox(width: 6),
                    Text(widget.suffix!,
                        style: YFont.titleMD().copyWith(
                            fontSize: 18, color: YColor.inkMuted)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            // the pad
            OtpNumpad(
              onDigit: _digit,
              onBackspace: _back,
              decimalKey: widget.decimal,
              keyWidth: 96,
              keyHeight: 54,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _done,
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  textStyle: YFont.bodyStrong().copyWith(fontSize: 15),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
