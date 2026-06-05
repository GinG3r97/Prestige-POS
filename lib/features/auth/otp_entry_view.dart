import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/supabase_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import 'otp_numpad.dart';

/// OTP verification screen. Single hidden text field drives a row of visual
/// chip boxes — gives us paste support + system password autofill without the
/// focus-management headache of N separate fields. Length is read from
/// `.env` (`SUPABASE_OTP_LENGTH`) so it stays in sync with Supabase config.
///
/// Security choices:
/// • Auto-verify on full entry (less time on screen)
/// • 60s resend cooldown enforced client-side (server also rate-limits)
/// • Numeric-only input via inputFormatters
/// • OTP cleared from the field after a failed attempt
class OtpEntryView extends StatefulWidget {
  const OtpEntryView({super.key});

  @override
  State<OtpEntryView> createState() => _OtpEntryViewState();
}

class _OtpEntryViewState extends State<OtpEntryView> {
  static const _resendCooldownSeconds = 60;

  int get _digits => SupabaseBootstrap.otpLength;

  String _code = '';
  String? _error;
  bool _busy = false;

  int _resendIn = _resendCooldownSeconds;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_busy || _code.length >= _digits) return;
    setState(() {
      _code += d;
      _error = null;
    });
    if (_code.length == _digits) _verify();
  }

  void _onBackspace() {
    if (_busy || _code.isEmpty) return;
    setState(() {
      _code = _code.substring(0, _code.length - 1);
      _error = null;
    });
  }

  void _startResendTimer() {
    _resendIn = _resendCooldownSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendIn -= 1;
        if (_resendIn <= 0) t.cancel();
      });
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    if (_code.length != _digits) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().verifyOtp(_code);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
        _code = '';
      });
      return;
    }
    // Success — pop back to the root so the Consumer<AppState> in main.dart
    // can route the user forward (OnboardingView, LoginView, or ShellView)
    // based on the freshly restored session.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().resendOtp();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      _startResendTimer();
    }
  }

  Future<void> _cancel() async {
    context.read<AppState>().cancelOtpVerification();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.watch<AppState>().pendingOtpEmail ?? '';

    final info = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _busy ? null : _cancel,
          icon: const Icon(Icons.arrow_back, size: 16),
          label: const Text('Back'),
          style: TextButton.styleFrom(foregroundColor: YColor.inkMuted),
        ),
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.brandTint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.mark_email_read_outlined,
              color: YColor.brandDeep, size: 28),
        ),
        const SizedBox(height: 16),
        Text('Check your email', style: YFont.titleLG().copyWith(fontSize: 26)),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: YFont.body()
                .copyWith(color: YColor.inkMuted, fontSize: 14, height: 1.4),
            children: [
              TextSpan(text: 'We sent a $_digits-digit code to '),
              TextSpan(
                text: email,
                style: const TextStyle(
                    color: YColor.ink, fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: '. Tap it in with the keypad.'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _OtpBoxes(code: _code, digits: _digits, hasError: _error != null),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.error_outline, size: 16, color: YColor.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_error!,
                  style: YFont.caption().copyWith(color: YColor.danger)),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        _resendIn > 0
            ? Text("Didn't get the code? Resend in ${_resendIn}s",
                style: YFont.caption())
            : TextButton(
                onPressed: _busy ? null : _resend,
                style: TextButton.styleFrom(
                  foregroundColor: YColor.brand,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Resend code'),
              ),
        const SizedBox(height: 6),
        Text("Check spam if you don't see it within a minute.",
            style:
                YFont.caption().copyWith(color: YColor.inkSubtle, fontSize: 11)),
      ],
    );

    final pad = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OtpNumpad(
            onDigit: _onDigit, onBackspace: _onBackspace, enabled: !_busy),
        const SizedBox(height: 16),
        SizedBox(
          width: 264,
          child: ElevatedButton(
            onPressed: (_busy || _code.length != _digits) ? null : _verify,
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor: YColor.brand.withValues(alpha: 0.4),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text('Verify',
                    style: YFont.bodyStrong()
                        .copyWith(color: Colors.white, fontSize: 15)),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: YColor.surface1,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: info),
                  const SizedBox(width: 36),
                  pad,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visual row of OTP digit boxes. Reads the currently entered code and
/// renders each digit in its own chip; focused chip is the next empty slot.
/// Boxes flex-fill the available width so 6, 7, or 8 digits all fit cleanly.
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({
    required this.code,
    required this.digits,
    required this.hasError,
  });
  final String code;
  final int digits;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final activeIdx = code.length.clamp(0, digits - 1);
    const gap = 6.0;
    return Row(
      children: [
        for (var i = 0; i < digits; i++) ...[
          Expanded(
            child: _OtpBox(
              digit: i < code.length ? code[i] : '',
              focused: i == activeIdx && code.length < digits,
              filled: i < code.length,
              hasError: hasError,
            ),
          ),
          if (i < digits - 1) const SizedBox(width: gap),
        ],
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.digit,
    required this.focused,
    required this.filled,
    required this.hasError,
  });
  final String digit;
  final bool focused;
  final bool filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? YColor.danger
        : focused
            ? YColor.brand
            : YColor.hairline;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? YColor.brandTint.withValues(alpha: 0.45)
            : YColor.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: focused || hasError ? 1.6 : 1,
        ),
      ),
      child: Text(
        digit,
        style: YFont.titleLG().copyWith(
          fontSize: 22,
          color: YColor.ink,
          fontFamily: 'Menlo',
          letterSpacing: 0,
        ),
      ),
    );
  }
}
