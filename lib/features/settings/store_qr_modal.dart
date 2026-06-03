import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// Shows a centered, glass-blur modal containing a large mock QR code for the
/// store. The QR pattern is deterministic from [seed] (e.g. the business name).
Future<void> showStoreQrModal(
  BuildContext context, {
  required String businessName,
  String? subtitle,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (_, anim, __, ___) {
      final progress = Curves.easeOutCubic.transform(anim.value);
      final spring = Curves.easeOutBack.transform(anim.value);
      return Stack(children: [
        // Glass blur scrim
        BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 18 * progress,
            sigmaY: 18 * progress,
          ),
          child: Container(
            color: Colors.black.withValues(alpha: 0.32 * progress),
          ),
        ),
        Center(
          child: Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.9 + (spring * 0.1),
              child: _StoreQrCard(
                businessName: businessName,
                subtitle: subtitle ?? 'Scan to view store info',
              ),
            ),
          ),
        ),
      ]);
    },
  );
}

class _StoreQrCard extends StatelessWidget {
  const _StoreQrCard({
    required this.businessName,
    required this.subtitle,
  });

  final String businessName;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              decoration: BoxDecoration(
                color: YColor.surface1.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: YColor.hairline, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: YColor.brandTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'STORE QR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: YColor.brandDeep,
                        ),
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: YColor.surface2,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 16, color: YColor.inkMuted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 22),
                  // QR code in a soft tile
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: YColor.hairline),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: CustomPaint(
                        painter: _StoreQrPainter(seed: businessName),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    businessName.isEmpty ? 'Your Store' : businessName,
                    textAlign: TextAlign.center,
                    style: YFont.titleLG().copyWith(
                      fontSize: 22,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: YFont.caption(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _action(
                        icon: Icons.ios_share,
                        label: 'Share',
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      _action(
                        icon: Icons.download_outlined,
                        label: 'Save',
                        onTap: () {},
                      ),
                      const SizedBox(width: 10),
                      _action(
                        icon: Icons.print_outlined,
                        label: 'Print',
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(YRadius.md),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(color: YColor.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: YColor.brandDeep),
          const SizedBox(width: 6),
          Text(label,
              style: YFont.bodyStrong()
                  .copyWith(fontSize: 12, color: YColor.brandDeep)),
        ]),
      ),
    );
  }
}

class _StoreQrPainter extends CustomPainter {
  _StoreQrPainter({required this.seed});

  final String seed;
  static const _grid = 25;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _grid;
    final fill = Paint()..color = Colors.black;
    final white = Paint()..color = Colors.white;

    void rect(int x, int y, int w, int h, Paint p) {
      canvas.drawRect(
        Rect.fromLTWH(x * cell, y * cell, w * cell, h * cell),
        p,
      );
    }

    // Corner finder markers (top-left, top-right, bottom-left)
    void marker(int gx, int gy) {
      rect(gx, gy, 7, 7, fill);
      rect(gx + 1, gy + 1, 5, 5, white);
      rect(gx + 2, gy + 2, 3, 3, fill);
    }

    marker(0, 0);
    marker(_grid - 7, 0);
    marker(0, _grid - 7);

    // Pseudo-random data based on seed.
    final r = Random(seed.hashCode | 0x7e57);
    bool inMarker(int x, int y) =>
        (x < 8 && y < 8) ||
        (x > _grid - 9 && y < 8) ||
        (x < 8 && y > _grid - 9);

    for (var y = 0; y < _grid; y++) {
      for (var x = 0; x < _grid; x++) {
        if (inMarker(x, y)) continue;
        if (r.nextDouble() < 0.48) {
          rect(x, y, 1, 1, fill);
        }
      }
    }

    // Small "logo dot" in the middle (optional flair)
    final cx = (_grid / 2).floor();
    final logoSize = cell * 5;
    final logoRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: logoSize,
      height: logoSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(logoRect.inflate(2), const Radius.circular(8)),
      Paint()..color = Colors.white,
    );
    final brandPaint = Paint()..color = const Color(0xFFB69066); // YColor.brand approx
    canvas.drawRRect(
      RRect.fromRectAndRadius(logoRect, const Radius.circular(8)),
      brandPaint,
    );
    // tiny center hint
    final tinyText = TextPainter(
      text: TextSpan(
        text: seed.isEmpty ? 'P' : seed.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tinyText.paint(
      canvas,
      Offset(
        size.width / 2 - tinyText.width / 2,
        size.height / 2 - tinyText.height / 2,
      ),
    );
    // suppress unused-var warning for cx
    assert(cx >= 0);
  }

  @override
  bool shouldRepaint(covariant _StoreQrPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
