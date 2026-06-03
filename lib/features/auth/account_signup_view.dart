import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../legal/legal_documents.dart';
import '../legal/legal_view.dart';
import 'auth_form_field.dart';
import 'otp_entry_view.dart';

/// Step 1 of signup — collects name + email and sends a 6-digit OTP. No
/// password fields: this app is fully passwordless. The OTP screen handles
/// the actual account creation upon successful verification.
class AccountSignupView extends StatefulWidget {
  const AccountSignupView({super.key});

  @override
  State<AccountSignupView> createState() => _AccountSignupViewState();
}

class _AccountSignupViewState extends State<AccountSignupView> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;
  /// User must tick this before we'll send the OTP. Required by the Terms.
  bool _agreedToLegal = false;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToLegal) {
      setState(() => _error =
          'Please accept the Terms & Conditions and Privacy Policy to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().sendSignupOtp(
          email: _email.text.trim(),
          displayName: _displayName.text.trim(),
        );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    // OTP sent — push the verification screen.
    setState(() => _busy = false);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OtpEntryView()),
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
        title: Text('Create account', style: YFont.titleMD()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Create your account',
                      style: YFont.titleLG().copyWith(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    "We'll email you a 6-digit code to verify. No password "
                    "to remember.",
                    style: YFont.body().copyWith(color: YColor.inkMuted),
                  ),
                  const SizedBox(height: 28),
                  AuthField(
                    controller: _displayName,
                    label: 'Your name',
                    hint: 'Full name',
                    validator: _required,
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: YColor.brandTint,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'OWNER',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: YColor.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AuthField(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@business.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 18),
                  _LegalConsentRow(
                    checked: _agreedToLegal,
                    onChanged: (v) => setState(() {
                      _agreedToLegal = v;
                      if (v) _error = null;
                    }),
                    onOpenTerms: () => LegalDocumentView.open(
                        context, termsAndConditions),
                    onOpenPrivacy: () =>
                        LegalDocumentView.open(context, privacyPolicy),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed:
                        (_busy || !_agreedToLegal) ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          YColor.brand.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Send verification code',
                            style: YFont.bodyStrong()
                                .copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : 'Enter a valid email';
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.dangerSoft,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 16, color: YColor.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: YFont.caption().copyWith(color: YColor.danger)),
        ),
      ]),
    );
  }
}

/// Mandatory consent checkbox with inline tappable links to the full T&C and
/// Privacy Policy. The "Send verification code" button is disabled until this
/// box is ticked, and the signup is blocked at submit time as a backstop.
class _LegalConsentRow extends StatelessWidget {
  const _LegalConsentRow({
    required this.checked,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final linkStyle = YFont.body().copyWith(
      fontSize: 13,
      color: YColor.brandDeep,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: YColor.brandDeep,
    );
    final bodyStyle = YFont.body().copyWith(
      fontSize: 13,
      color: YColor.inkMuted,
      height: 1.4,
    );
    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(YRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Custom checkbox so we can theme the colours and avoid Material
            // ripple bleeding outside the row.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: checked ? YColor.brand : Colors.transparent,
                  border: Border.all(
                    color: checked ? YColor.brand : YColor.inkMuted,
                    width: 1.6,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: checked
                    ? const Icon(Icons.check,
                        size: 16, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: bodyStyle,
                  children: [
                    const TextSpan(text: 'I have read and agree to the '),
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: linkStyle,
                      recognizer: _tap(onOpenTerms),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: linkStyle,
                      recognizer: _tap(onOpenPrivacy),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to build a TapGestureRecognizer for inline link spans.
  TapGestureRecognizer _tap(VoidCallback cb) =>
      TapGestureRecognizer()..onTap = cb;
}
