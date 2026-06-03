import 'dart:io';
import 'package:image/image.dart';

void main() {
  // Always start from the pristine original.
  final src = decodePng(
      File('assets/brand/app_icon_original.png').readAsBytesSync())!;
  final p = src.getPixel(3, src.height ~/ 2);
  final bg = ColorRgb8(p.r.toInt(), p.g.toInt(), p.b.toInt());

  final base = src.width > src.height ? src.width : src.height;
  // Enlarge ~9% then center-crop so the transparent rounded corners fall
  // outside the frame — leaves a clean, fully-opaque square (no seam). iOS
  // applies its own corner rounding on top.
  final over = (base * 1.09).round();
  final big = copyResize(src, width: over, height: over,
      interpolation: Interpolation.cubic);
  final cx = (over - base) ~/ 2;
  final cropped = copyCrop(big, x: cx, y: cx, width: base, height: base);

  final canvas = Image(width: base, height: base, numChannels: 3);
  fill(canvas, color: bg);
  compositeImage(canvas, cropped); // flatten any residual edge alpha

  final out = copyResize(canvas, width: 1024, height: 1024,
      interpolation: Interpolation.average);
  File('assets/brand/app_icon.png').writeAsBytesSync(encodePng(out));
  stdout.writeln('Wrote ${out.width}x${out.height} opaque, no rounded corners');
}
