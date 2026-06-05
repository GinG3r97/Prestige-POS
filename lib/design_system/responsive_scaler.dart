import 'package:flutter/material.dart';

/// Anchors the entire app to a fixed *design width* and uniformly scales it to
/// fit the real screen, so every tablet — iPad, Lenovo, budget Android — shows
/// the same proportional UI instead of looking bigger/smaller per device.
///
/// Why this exists: the design uses raw logical-pixel sizes (paddings, fonts,
/// fixed widths) tuned for an iPad's ~1194 dp landscape width. On a narrower
/// tablet (e.g. the Techlife TLPAD002 at ~961 dp) those fixed sizes occupy a
/// larger share of the screen, so everything feels enlarged and cramped. By
/// laying the app out in a constant 1194 dp design space and scaling the whole
/// subtree to fit, the proportions are identical everywhere.
///
/// We only ever scale **down** (`maxScale` capped at 1.0): a screen wider than
/// the design renders 1:1 with more breathing room, never blown up. Text is
/// normalised to the design sizes too (the device's system font-scale is
/// neutralised) so layout stays stable across devices.
class ResponsiveScaler extends StatelessWidget {
  const ResponsiveScaler({
    super.key,
    required this.child,
    this.designWidth = 1194, // iPad 11" landscape — the known-good baseline
    this.minScale = 0.78,
    this.maxScale = 1.0,
  });

  final Widget child;
  final double designWidth;
  final double minScale;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    if (size.width <= 0) return child;

    final scale = (size.width / designWidth).clamp(minScale, maxScale);

    // On a baseline-width device there's nothing to do — render untouched so
    // the iPad experience is byte-for-byte unchanged.
    if ((scale - 1.0).abs() < 0.001 &&
        mq.textScaler == TextScaler.noScaling) {
      return child;
    }

    // Lay the app out in "design space" = real pixels ÷ scale. Width lands on
    // exactly `designWidth`; height grows/shrinks with the device's aspect.
    final designSize = Size(size.width / scale, size.height / scale);

    EdgeInsets unscale(EdgeInsets e) => EdgeInsets.fromLTRB(
          e.left / scale,
          e.top / scale,
          e.right / scale,
          e.bottom / scale,
        );

    // FittedBox lays the child out at its natural (design) size, then scales
    // it to fill our box. Crucially it transforms HIT-TESTING too, so taps at
    // the edges (e.g. the bottom nav) land correctly — unlike a Transform over
    // an OverflowBox, whose box stays screen-sized and silently swallows taps
    // beyond it. `fill` is exact (no letterbox) because designSize keeps the
    // device's aspect ratio, so x and y scale by the same factor.
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: designSize.width,
        height: designSize.height,
        child: MediaQuery(
          data: mq.copyWith(
            size: designSize,
            padding: unscale(mq.padding),
            viewPadding: unscale(mq.viewPadding),
            viewInsets: unscale(mq.viewInsets),
            // Normalise text to design sizes — the device font-scale is
            // already reflected by the uniform scale above.
            textScaler: TextScaler.noScaling,
          ),
          child: child,
        ),
      ),
    );
  }
}
