import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import 'account_signup_view.dart';
import 'auth_form_field.dart';
import 'otp_entry_view.dart';

/// Step 1 of login — collects email and sends a 6-digit OTP. The next screen
/// verifies the code. Same passwordless flow as signup, by design.
class AccountLoginView extends StatefulWidget {
  const AccountLoginView({super.key});

  @override
  State<AccountLoginView> createState() => _AccountLoginViewState();
}

class _AccountLoginViewState extends State<AccountLoginView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().sendLoginOtp(
          email: _email.text.trim(),
        );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
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
        title: Text('Sign in', style: YFont.titleMD()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Welcome back',
                      style: YFont.titleLG().copyWith(fontSize: 28)),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your email and we\'ll send you a verification code.',
                    style: YFont.body().copyWith(color: YColor.inkMuted),
                  ),
                  const SizedBox(height: 28),
                  AuthField(
                    controller: _email,
                    label: 'Email',
                    hint: 'you@business.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: YColor.dangerSoft,
                        borderRadius: BorderRadius.circular(YRadius.md),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: YColor.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: YFont.caption()
                                  .copyWith(color: YColor.danger)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
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
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const AccountSignupView()),
                    ),
                    child: Text("Don't have an account? Create one",
                        style: YFont.bodyStrong()
                            .copyWith(color: YColor.brand)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email required';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : 'Enter a valid email';
  }
}
