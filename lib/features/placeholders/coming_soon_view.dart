import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// Reusable placeholder view for nav tabs whose feature flag is enabled but
/// whose backing module hasn't been implemented yet. Honest "coming soon"
/// state — better than a blank screen or, worse, a missing nav tab.
class ComingSoonView extends StatelessWidget {
  const ComingSoonView({
    super.key,
    required this.icon,
    required this.title,
    required this.tagline,
    required this.featureBullets,
    this.estimatedTurn,
  });

  /// Big icon for the hero area.
  final IconData icon;

  /// Section title, e.g. "Bookings".
  final String title;

  /// One-line description of what this screen will be.
  final String tagline;

  /// 3-5 bullet points describing what users will be able to do.
  final List<String> featureBullets;

  /// Optional internal label like "Turn 4" — only shown in debug-y badge.
  final String? estimatedTurn;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: YColor.surface2,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: YColor.brandTint,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(icon, size: 48, color: YColor.brandDeep),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: YFont.titleLG().copyWith(
                        fontSize: 32, letterSpacing: -0.6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tagline,
                    textAlign: TextAlign.center,
                    style: YFont.body().copyWith(
                      color: YColor.inkMuted,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    decoration: BoxDecoration(
                      color: YColor.surface1,
                      borderRadius: BorderRadius.circular(YRadius.lg),
                      border: Border.all(
                          color: YColor.hairline.withValues(alpha: 0.6)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: YColor.brandTint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'COMING SOON',
                                style: YFont.caption().copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                  color: YColor.brandDeep,
                                ),
                              ),
                            ),
                            if (estimatedTurn != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                estimatedTurn!,
                                style: YFont.caption().copyWith(
                                  color: YColor.inkSubtle,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ]),
                        ),
                        for (var i = 0; i < featureBullets.length; i++)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(
                                    Icons.check_circle_outline,
                                    size: 14,
                                    color: YColor.brand,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    featureBullets[i],
                                    style: YFont.body().copyWith(
                                      color: YColor.ink,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'This tab is visible because you enabled it during '
                    'onboarding. You can hide it in Settings any time.',
                    textAlign: TextAlign.center,
                    style: YFont.caption().copyWith(
                      color: YColor.inkSubtle,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
