import 'dart:ui';
import 'package:flutter/material.dart';
import 'colors.dart';
import 'spacing.dart';

/// Bright white card with floating shadow — for browse grids.
class YBrightCard extends StatelessWidget {
  const YBrightCard({
    super.key,
    required this.child,
    this.corner = YRadius.lg,
    this.padding = const EdgeInsets.all(YSpacing.md),
  });

  final Widget child;
  final double corner;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(corner),
        border: Border.all(color: YColor.hairline, width: 0.5),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6)),
          BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: child,
    );
  }
}

/// Floating glass card — translucent shimmer over white base.
/// Cross-platform glass effect using BackdropFilter.
class YFloatingCard extends StatelessWidget {
  const YFloatingCard({
    super.key,
    required this.child,
    this.corner = YRadius.lg,
    this.padding = const EdgeInsets.all(YSpacing.md),
    this.tint,
  });

  final Widget child;
  final double corner;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? YColor.surface1.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(corner),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.6),
            boxShadow: const [
              BoxShadow(color: Color(0x1A000000), blurRadius: 18, offset: Offset(0, 10)),
              BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Glass-tinted capsule for selected pill backgrounds.
class YGlassPill extends StatelessWidget {
  const YGlassPill({
    super.key,
    required this.child,
    required this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.shape = BoxShape.rectangle,
  });

  final Widget child;
  final Color tint;
  final EdgeInsets padding;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
          ),
          child: child,
        ),
      ),
    );
  }
}
