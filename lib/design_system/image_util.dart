
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Downscales [raw] so its longest edge is at most [maxEdge] px (preserving
/// aspect ratio), then JPEG-encodes at [quality]. Runs off the UI thread via
/// [compute] so large phone photos don't jank the UI. Returns the original
/// bytes unchanged if decoding fails.
Future<Uint8List> compressImage(
  Uint8List raw, {
  int maxEdge = 512,
  int quality = 82,
}) =>
    compute(_compressRun, {
      'bytes': raw,
      'maxEdge': maxEdge,
      'quality': quality,
    });

Uint8List _compressRun(Map<String, dynamic> args) {
  final raw = args['bytes'] as Uint8List;
  final maxEdge = args['maxEdge'] as int;
  final quality = args['quality'] as int;

  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;

  img.Image out = decoded;
  final longest =
      decoded.width >= decoded.height ? decoded.width : decoded.height;
  if (longest > maxEdge) {
    out = decoded.width >= decoded.height
        ? img.copyResize(decoded,
            width: maxEdge, interpolation: img.Interpolation.average)
        : img.copyResize(decoded,
            height: maxEdge, interpolation: img.Interpolation.average);
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}
