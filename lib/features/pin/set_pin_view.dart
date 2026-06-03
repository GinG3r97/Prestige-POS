import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// Two-step screen that registers a 4-digit owner PIN.
///   Step 1: enter the new PIN.
///   Step 2: confirm by entering it again.
/// Mismatch → shake + reset to step 1. Match → calls `setOwnerPin` RPC.
class SetPinView extends StatefulWidget {
  const SetPinView({super.key});

  @override
  State<SetPinView> createState() => _SetPinViewState();
}

class _SetPinViewState extends State<SetPinView>
    with SingleTickerProviderStateMixin {
  String _firstPin = '';
  String _currentPin = '';
  bool _confirmStep = false;
  bool _busy = false;
  String? _error;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_busy) return;
    if (_currentPin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      _currentPin += d;
      _error = null;
    });
    if (_currentPin.length == 4) _onPinComplete();
  }

  void _onDelete() {
    if (_busy) return;
    if (_currentPin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _currentPin = _currentPin.substring(0, _currentPin.length - 1));
  }

  Future<void> _onPinComplete() async {
    if (!_confirmStep) {
      // First entry — advance to confirm step.
      setState(() {
        _firstPin = _currentPin;
        _currentPin = '';
        _confirmStep = true;
      });
      return;
    }
    // Confirm step — must match the first entry.
    if (_currentPin != _firstPin) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      setState(() {
        _firstPin = '';
        _currentPin = '';
        _confirmStep = false;
        _error = "PINs didn't match. Try again.";
      });
      return;
    }
    // Match — persist via RPC.
    setState(() => _busy = true);
    final err = await context.read<AppState>().setOwnerPin(_firstPin);
    if (!mounted) return;
    if (err != null) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      setState(() {
        _busy = false;
        _error = err;
        _firstPin = '';
        _currentPin = '';
        _confirmStep = false;
      });
      return;
    }
    // Success — the root Consumer reroutes to LoginView / ShellView via
    // hasOwnerPin flipping true.
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final businessName = state.tenant?.businessName.trim().isNotEmpty == true
        ? state.tenant!.businessName
        : 'your business';

    return Scaffold(
      backgroundColor: YColor.surface1,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                        color: YColor.brandTint, shape: BoxShape.circle),
                    child: const Icon(Icons.lock_outline,
                        size: 32, color: YColor.brandDeep),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _confirmStep ? 'Confirm your PIN' : 'Create your owner PIN',
                    style: YFont.titleLG().copyWith(fontSize: 26),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _confirmStep
                        ? 'Enter the same 4-digit code again.'
                        : 'You\'ll use this PIN to sign in to $businessName on this device.',
                    style: YFont.body().copyWith(
                      color: YColor.inkMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  AnimatedBuilder(
                    animation: _shake,
                    builder: (_, child) {
                      final dx = sin(_shake.value * pi * 6) * 8;
                      return Transform.translate(
                          offset: Offset(dx, 0), child: child);
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          4, (i) => _Dot(filled: i < _currentPin.length)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: YColor.dangerSoft,
                        borderRadius: BorderRadius.circular(YRadius.md),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 14, color: YColor.danger),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: YFont.caption()
                                  .copyWith(color: YColor.danger),
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _PinPad(onDigit: _onDigit, onDelete: _onDelete),
                  const SizedBox(height: 20),
                  Text(
                    _busy
                        ? 'Saving…'
                        : 'Treat this PIN like a password. You can reset it any time via email.',
                    style: YFont.caption().copyWith(
                      color: _busy ? YColor.brandDeep : YColor.inkSubtle,
                    ),
                    textAlign: TextAlign.center,
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

class _Dot extends StatelessWidget {
  const _Dot({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? YColor.brand : YColor.surface4,
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onDelete});
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Column(
        children: _rows.map((row) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((key) {
                if (key.isEmpty) return const SizedBox(width: 78, height: 64);
                return _Key(
                  label: key,
                  onPressed: () =>
                      key == '⌫' ? onDelete() : onDigit(key),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Key extends StatefulWidget {
  const _Key({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: 78,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.md),
            border: Border.all(color: YColor.hairline, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(widget.label,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
