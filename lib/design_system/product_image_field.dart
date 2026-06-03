import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'colors.dart';
import 'spacing.dart';
import 'typography.dart';

/// Tap-to-pick image tile used in product / add-on forms. Replaces the
/// emoji input. Owners pick a photo from gallery (or camera on mobile);
/// the image is downsampled to a 1024px max-edge JPEG@85 in the
/// background so uploads are crisp but small (~80–200 KB). The compressed
/// bytes are handed back via [onPicked] — the parent form decides when to
/// actually upload them (typically right before saving the product row).
///
/// While no image is chosen, [fallback] renders inside the tile (Material
/// icon, brand-tinted square) so the experience matches the rest of the
/// theme.
class ProductImageField extends StatefulWidget {
  const ProductImageField({
    super.key,
    required this.existingUrl,
    required this.onPicked,
    required this.fallback,
    this.size = 120,
    this.maxEdge = 1024,
    this.jpegQuality = 85,
    this.label = 'Image',
  });

  /// Existing public URL on the product row. Rendered inside the tile when
  /// no fresh local pick has been made yet. Null/empty = show fallback.
  final String? existingUrl;

  /// Called whenever the user picks (and we successfully compress) a new
  /// image. Bytes are JPEG-encoded and ready to upload. Pass null in to
  /// clear (we trigger this on the "Remove image" action below).
  final ValueChanged<Uint8List?> onPicked;

  /// Renders inside the empty/idle tile — typically a `NameIconOrEmoji`
  /// instance so callers stay consistent with the rest of the icon system.
  final Widget fallback;

  final double size;
  final int maxEdge;
  final int jpegQuality;
  final String label;

  @override
  State<ProductImageField> createState() => _ProductImageFieldState();
}

class _ProductImageFieldState extends State<ProductImageField> {
  Uint8List? _localBytes;
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final raw = await picked.readAsBytes();
      final compressed = await _compress(raw);
      if (!mounted) return;
      setState(() {
        _localBytes = compressed;
        _busy = false;
      });
      widget.onPicked(compressed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not load image: $e';
      });
      debugPrint('ProductImageField pick failed: $e');
    }
  }

  Future<Uint8List> _compress(Uint8List raw) async {
    return await compute(_compressInIsolate, {
      'bytes': raw,
      'maxEdge': widget.maxEdge,
      'quality': widget.jpegQuality,
    });
  }

  void _clear() {
    setState(() => _localBytes = null);
    widget.onPicked(null);
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = _localBytes != null;
    final hasRemote =
        widget.existingUrl != null && widget.existingUrl!.isNotEmpty;
    final hasImage = hasLocal || hasRemote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(widget.label, style: YFont.caption()),
        ),
        GestureDetector(
          onTap: _pick,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: YColor.surface1,
              borderRadius: BorderRadius.circular(YRadius.md),
              border: Border.all(
                color: hasImage ? YColor.brand : YColor.hairline,
                width: hasImage ? 1.2 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _busy
                      ? const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : hasLocal
                          ? Image.memory(_localBytes!, fit: BoxFit.cover)
                          : hasRemote
                              ? Image.network(
                                  widget.existingUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Center(child: widget.fallback),
                                )
                              : Center(child: widget.fallback),
                ),
                if (!_busy)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasImage
                                ? Icons.refresh
                                : Icons.add_photo_alternate_outlined,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasImage ? 'Change' : 'Upload',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: GestureDetector(
              onTap: _clear,
              child: Text(
                'Remove image',
                style: YFont.caption().copyWith(
                  color: YColor.danger,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              _error!,
              style: YFont.caption().copyWith(color: YColor.danger),
            ),
          ),
      ],
    );
  }
}

/// Top-level so it can run inside [compute]. Downsamples [bytes] so the
/// longest edge is no more than [maxEdge] pixels (preserving aspect ratio)
/// then JPEG-encodes at [quality]. Uses average resampling — slightly
/// slower than nearest but avoids the soft / pixelated look you get with
/// naive 1-px sampling on phone photos.
Uint8List _compressInIsolate(Map<String, dynamic> args) {
  final raw = args['bytes'] as Uint8List;
  final maxEdge = args['maxEdge'] as int;
  final quality = args['quality'] as int;

  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    return raw; // give up — let the upload reject if it's truly bad
  }
  img.Image resized = decoded;
  final longestEdge =
      decoded.width >= decoded.height ? decoded.width : decoded.height;
  if (longestEdge > maxEdge) {
    if (decoded.width >= decoded.height) {
      resized = img.copyResize(
        decoded,
        width: maxEdge,
        interpolation: img.Interpolation.average,
      );
    } else {
      resized = img.copyResize(
        decoded,
        height: maxEdge,
        interpolation: img.Interpolation.average,
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}
