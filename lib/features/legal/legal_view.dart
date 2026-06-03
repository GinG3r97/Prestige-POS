import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import 'legal_documents.dart';

/// Generic scrollable viewer used for both Terms & Conditions and Privacy
/// Policy. Pass the document via [doc].
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({super.key, required this.doc});
  final LegalDocument doc;

  /// Open this doc as a full-screen route.
  static Future<void> open(BuildContext context, LegalDocument doc) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentView(doc: doc)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YColor.surface1,
      appBar: AppBar(
        backgroundColor: YColor.surface1,
        elevation: 0,
        foregroundColor: YColor.ink,
        title: Text(doc.shortName, style: YFont.titleMD()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Brand strip
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: [
                        YColor.brandSoft,
                        YColor.brand,
                        YColor.brandDeep,
                      ],
                    ),
                  ),
                ),
                Text(
                  doc.title,
                  style: YFont.titleLG().copyWith(
                    fontSize: 32,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Effective ${doc.effectiveDate} · Prestige POS by Prestige IT Solutions',
                  style: YFont.caption().copyWith(color: YColor.inkMuted),
                ),
                const SizedBox(height: 20),
                _DisclaimerBanner(),
                const SizedBox(height: 20),
                Text(
                  doc.intro,
                  style: YFont.body().copyWith(
                    color: YColor.ink,
                    height: 1.6,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 28),
                for (final section in doc.sections) ...[
                  Text(
                    section.heading,
                    style: YFont.titleMD().copyWith(
                      fontSize: 17,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < section.paragraphs.length; i++) ...[
                    Text(
                      section.paragraphs[i],
                      style: YFont.body().copyWith(
                        height: 1.6,
                        fontSize: 14.5,
                        color: YColor.ink,
                      ),
                    ),
                    if (i != section.paragraphs.length - 1)
                      const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 24),
                ],
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: YColor.brandTint,
                    borderRadius: BorderRadius.circular(YRadius.md),
                    border: Border.all(color: YColor.brandSoft),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.mail_outline,
                          size: 18, color: YColor.brandDeep),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          doc.contactNote,
                          style: YFont.body().copyWith(
                            fontSize: 13.5,
                            color: YColor.brandDeep,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.warningSoft,
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: YColor.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Starter template — please have a licensed lawyer review and '
              'tailor this to your business before going to production.',
              style: YFont.caption()
                  .copyWith(color: YColor.warning, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
