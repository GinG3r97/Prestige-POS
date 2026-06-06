// One-off: extract the cream cup/steam from the app-icon tile onto a
// TRANSPARENT background so the splash logo doesn't show a tile/white border
// floating on the brown splash. Also emits a padded variant that fits inside
// Android 12's circular splash mask (so the mug handle isn't clipped).
//
// Run:  dart run tool/make_splash.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodePng(
      File('assets/brand/splash_logo.png').readAsBytesSync())!;
  final w = src.width, h = src.height;

  // Recolour everything to a uniform cream and derive alpha from luminance:
  // the cup/steam are light (kept), the brown tile + transparent corners drop
  // out. Recolouring removes any white anti-alias fringe.
  const cream = [0xF3, 0xE6, 0xCE];
  final cup = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = src.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final srcA = p.a.toDouble() / 255.0;
      final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
      // 0 below 0.52, ramp to 1 by 0.72 → soft, anti-aliased edges.
      final t = ((lum - 0.52) / 0.20).clamp(0.0, 1.0);
      final a = (t * srcA * 255).round();
      cup.setPixelRgba(x, y, cream[0], cream[1], cream[2], a);
    }
  }
  File('assets/brand/splash_cup.png').writeAsBytesSync(img.encodePng(cup));

  // Android 12: the system shows the image inside a circle ~2/3 of the canvas.
  // Shrink the cup to ~60% and centre it on a transparent square so nothing is
  // clipped by the circular mask.
  final padded = img.Image(width: w, height: h, numChannels: 4);
  final scaled = img.copyResize(cup, width: (w * 0.60).round());
  img.compositeImage(padded, scaled,
      dstX: ((w - scaled.width) / 2).round(),
      dstY: ((h - scaled.height) / 2).round());
  File('assets/brand/splash_cup_android12.png')
      .writeAsBytesSync(img.encodePng(padded));

  // ignore: avoid_print
  print('Wrote splash_cup.png (${w}x$h) + splash_cup_android12.png');
}
