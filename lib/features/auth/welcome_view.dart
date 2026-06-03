import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../legal/legal_documents.dart';
import '../legal/legal_view.dart';
import 'account_login_view.dart';
import 'account_signup_view.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YColor.surface1,
      body: Row(
        children: [
          Expanded(
            flex: 50,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF7EDDF),
                    YColor.brandTint,
                    Color(0xFFE8D9C2),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
              padding: const EdgeInsets.all(56),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Prestige',
                    style: YFont.titleLG().copyWith(
                      fontSize: 56,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -1.6,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'POS',
                    style: YFont.titleLG().copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 6.0,
                      color: YColor.brandDeep,
                    ),
                  ),
                  const SizedBox(height: 24),
                  RichText(
                    text: TextSpan(
                      style: YFont.titleMD().copyWith(
                        fontSize: 22,
                        color: YColor.ink,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.4,
                      ),
                      children: [
                        const TextSpan(text: 'The art of service, '),
                        TextSpan(
                          text: 'perfected.',
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontStyle: FontStyle.italic,
                            color: YColor.brandDeep,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'A premium point-of-sale built for\ncoffee shops and cafés.',
                    style: YFont.body().copyWith(
                      fontSize: 14,
                      color: YColor.brandDeep,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 36),
                  const _PillCloud(),
                  const SizedBox(height: 32),
                  Row(children: [
                    Text(
                      'PRESTIGE',
                      style: YFont.caption().copyWith(
                        color: YColor.brandDeep,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.0,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 24, height: 1, color: YColor.brandDeep),
                    const SizedBox(width: 10),
                    Text(
                      'The premium edition',
                      style: YFont.caption().copyWith(
                        color: YColor.brandDeep,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        fontSize: 11,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 50,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome',
                        textAlign: TextAlign.start,
                        style: GoogleFonts.dancingScript(
                          fontSize: 88,
                          fontWeight: FontWeight.w500,
                          color: YColor.ink,
                          height: 1.0,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Set up your business or sign in to continue.',
                        textAlign: TextAlign.start,
                        style: YFont.body().copyWith(
                          color: YColor.inkMuted,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 36),
                      _PrimaryButton(
                        label: 'Create a business account',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AccountSignupView()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _SecondaryButton(
                        label: 'I already have an account',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const AccountLoginView()),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _legalFooter(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legalFooter(BuildContext context) {
    final baseStyle = YFont.caption().copyWith(
      color: YColor.inkSubtle,
      height: 1.4,
    );
    final linkStyle = baseStyle.copyWith(
      color: YColor.brandDeep,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: YColor.brandDeep,
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          const TextSpan(text: 'By continuing you agree to our '),
          TextSpan(
            text: 'Terms & Conditions',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  LegalDocumentView.open(context, termsAndConditions),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () =>
                  LegalDocumentView.open(context, privacyPolicy),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _PillCloud extends StatelessWidget {
  const _PillCloud();

  static const _items = [
    (Icons.point_of_sale, 'Sales'),
    (Icons.inventory_2_outlined, 'Inventory'),
    (Icons.local_cafe_outlined, 'Products'),
    (Icons.badge_outlined, 'Staff'),
    (Icons.payments_outlined, 'Payroll'),
    (Icons.bar_chart, 'Reports'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _items
          .map((it) => _Pill(icon: it.$1, label: it.$2))
          .toList(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: YColor.brandDeep),
        const SizedBox(width: 7),
        Text(
          label,
          style: YFont.caption().copyWith(
            color: YColor.brandDeep,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ]),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YRadius.md),
        boxShadow: [
          BoxShadow(
            color: YColor.brand.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: YColor.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(YRadius.md)),
        ),
        child: Text(
          label,
          style: YFont.bodyStrong().copyWith(
            color: Colors.white,
            fontSize: 15,
            letterSpacing: -0.1,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: YColor.ink,
        side: const BorderSide(color: YColor.hairline, width: 1.2),
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(YRadius.md)),
      ),
      child: Text(
        label,
        style: YFont.bodyStrong().copyWith(fontSize: 15, letterSpacing: -0.1),
      ),
    );
  }
}
