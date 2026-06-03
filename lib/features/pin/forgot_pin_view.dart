import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../auth/otp_entry_view.dart';

/// "Forgot PIN" recovery — issues a fresh email OTP to the verified address
/// on file, then routes the user through the existing [OtpEntryView]. After
/// the OTP is verified the user is signed in; on next launch the routing
/// drops to [SetPinView] (because the PIN row is being reset).
///
/// Security note: we do NOT actually reset the stored PIN here. We sign the
/// user in via Supabase Auth (OTP), then in the SetPinView they choose a new
/// PIN — at which point the bcrypt hash is overwritten via the
/// `set_owner_pin` RPC.
class ForgotPinView extends StatefulWidget {
  const ForgotPinView({super.key});

  @override
  State<ForgotPinView> createState() => _ForgotPinViewState();
}

class _ForgotPinViewState extends State<ForgotPinView> {
  bool _busy = false;
  String? _error;

  Future<void> _sendRecoveryOtp() async {
    final state = context.read<AppState>();
    final email = state.currentOwner?.email;
    if (email == null || email.isEmpty) {
      setState(() => _error = 'No email on file. Please contact support.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await state.sendLoginOtp(email: email);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    // Push the OTP entry screen on top. Once verified, the auth listener
    // updates currentOwner and we pop back; main.dart's routing then sends
    // the user to SetPinView (because _ownerPinSet is being reset there too).
    setState(() => _busy = false);
    state.markOwnerPinReset();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OtpEntryView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final email = state.currentOwner?.email ?? '';

    return Scaffold(
      backgroundColor: YColor.surface1,
      appBar: AppBar(
        backgroundColor: YColor.surface1,
        elevation: 0,
        foregroundColor: YColor.ink,
        title: Text('Forgot PIN', style: YFont.titleMD()),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: YColor.brandTint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.lock_reset,
                      size: 30, color: YColor.brandDeep),
                ),
                const SizedBox(height: 18),
                Text(
                  'Reset your PIN',
                  style: YFont.titleLG().copyWith(fontSize: 26),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: YFont.body().copyWith(
                      color: YColor.inkMuted,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    children: [
                      const TextSpan(
                          text: "We'll email a verification code to "),
                      TextSpan(
                        text: email,
                        style: const TextStyle(
                            color: YColor.ink,
                            fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(
                          text:
                              ". Enter the code to set a new PIN."),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
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
                  onPressed: _busy ? null : _sendRecoveryOtp,
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
                      : Text('Send code to my email',
                          style: YFont.bodyStrong()
                              .copyWith(color: Colors.white)),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text("Never mind, I remember it",
                      style: YFont.body().copyWith(color: YColor.inkMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
