import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/typography.dart';

/// Visual code cells — one box per digit, the next-to-fill cell highlighted.
/// Pairs with [OtpNumpad] so the entered code reads clearly without a keyboard.
class OtpCells extends StatelessWidget {
  const OtpCells({
    super.key,
    required this.code,
    required this.length,
    this.hasError = false,
    this.cellWidth = 46,
    this.cellHeight = 56,
  });

  final String code;
  final int length;
  final bool hasError;
  final double cellWidth;
  final double cellHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Container(
              width: cellWidth,
              height: cellHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasError
                      ? YColor.danger
                      : (i == code.length ? YColor.brand : YColor.hairline),
                  width: (i == code.length && !hasError) ? 1.6 : 1,
                ),
              ),
              child: Text(
                i < code.length ? code[i] : '',
                style: YFont.titleLG().copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: YColor.ink),
              ),
            ),
          ),
      ],
    );
  }
}

/// A self-contained on-screen number pad for entering OTP / verification codes.
/// Used so we never raise the system keyboard (which is awkward on Android and
/// inconsistent across platforms) — the same pad shows on iOS and Android.
/// The parent owns the code string; this just reports key presses.
class OtpNumpad extends StatelessWidget {
  const OtpNumpad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.enabled = true,
    this.keyWidth = 78,
    this.keyHeight = 56,
    this.decimalKey = false,
  });

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final bool enabled;
  final double keyWidth;
  final double keyHeight;

  /// When true the empty bottom-left slot becomes a "." key (calls [onDigit]
  /// with '.') — used for money entry.
  final bool decimalKey;

  Widget _key(String label, {bool backspace = false}) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: YColor.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: YColor.hairline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !enabled
              ? null
              : (backspace ? onBackspace : () => onDigit(label)),
          child: SizedBox(
            width: keyWidth,
            height: keyHeight,
            child: Center(
              child: backspace
                  ? const Icon(Icons.backspace_outlined,
                      size: 22, color: YColor.brandDeep)
                  : Text(label,
                      style: YFont.titleLG()
                          .copyWith(fontSize: 24, color: YColor.ink)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final k in row) _key(k)],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            decimalKey
                ? _key('.')
                : SizedBox(width: keyWidth + 10), // empty bottom-left slot
            _key('0'),
            _key('', backspace: true),
          ],
        ),
      ],
    );
  }
}
