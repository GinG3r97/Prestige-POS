import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

bool get _isApple =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// On Apple platforms (iOS/macOS), uses the system font (SF Pro) by leaving
/// fontFamily unset — Flutter resolves to `.SF UI Display/.SF UI Text` natively.
/// On other platforms, falls back to Inter (a free Apple-system-like UI font).
TextStyle _ts({
  required double fontSize,
  required FontWeight fontWeight,
  required Color color,
  double? letterSpacing,
}) {
  if (_isApple) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }
  return GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

class YFont {
  static TextStyle titleXL() =>
      _ts(fontSize: 32, fontWeight: FontWeight.w700, color: YColor.ink, letterSpacing: -0.5);
  static TextStyle titleLG() =>
      _ts(fontSize: 22, fontWeight: FontWeight.w700, color: YColor.ink, letterSpacing: -0.3);
  static TextStyle titleMD() =>
      _ts(fontSize: 18, fontWeight: FontWeight.w600, color: YColor.ink, letterSpacing: -0.2);

  static TextStyle body() =>
      _ts(fontSize: 14, fontWeight: FontWeight.w400, color: YColor.ink);
  static TextStyle bodyStrong() =>
      _ts(fontSize: 14, fontWeight: FontWeight.w600, color: YColor.ink);
  static TextStyle caption() =>
      _ts(fontSize: 12, fontWeight: FontWeight.w400, color: YColor.inkMuted);

  static TextStyle price() =>
      _ts(fontSize: 16, fontWeight: FontWeight.w700, color: YColor.ink);
  static TextStyle priceLG() =>
      _ts(fontSize: 22, fontWeight: FontWeight.w700, color: YColor.ink, letterSpacing: -0.3);
}
