import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../pin/forgot_pin_view.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _Quote {
  final String text;
  final String author;
  const _Quote(this.text, this.author);
}

const _quotes = <_Quote>[
  _Quote('A book is a dream that you hold in your hand.', 'Neil Gaiman'),
  _Quote('Coffee first. Schemes later.', 'Leanna Renee Hieber'),
  _Quote('A reader lives a thousand lives before he dies.', 'George R.R. Martin'),
  _Quote('Behind every great reader is a great cup of coffee.', 'Unknown'),
  _Quote('So many books, so little time.', 'Frank Zappa'),
  _Quote('I have measured out my life with coffee spoons.', 'T.S. Eliot'),
  _Quote('One can never read too many books, nor drink too much coffee.', 'Unknown'),
  _Quote('A good book and a cup of coffee make the perfect day.', 'Unknown'),
  _Quote('There is no friend as loyal as a book.', 'Ernest Hemingway'),
  _Quote("Rise and grind — the pages won't turn themselves.", "The Barista's Creed"),
];

class _LoginViewState extends State<LoginView> with SingleTickerProviderStateMixin {
  String pin = '';
  bool _busy = false;
  String? _error;
  late _Quote quote;
  late AnimationController _shake;

  @override
  void initState() {
    super.initState();
    quote = _quotes[Random().nextInt(_quotes.length)];
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _onDigit(String d) {
    if (_busy) return;
    if (pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() {
      pin += d;
      _error = null;
    });
    if (pin.length == 4) _attemptLogin();
  }

  void _onDelete() {
    if (_busy) return;
    if (pin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => pin = pin.substring(0, pin.length - 1));
  }

  Future<void> _attemptLogin() async {
    final state = context.read<AppState>();
    final attempted = pin;
    setState(() => _busy = true);

    // Unified PIN sign-in — verifyPin tries the owner PIN first, then
    // every cashier-role employee's bcrypt-hashed PIN. First match wins.
    final err = await state.verifyPin(attempted);
    if (!mounted) return;
    if (err == null) {
      HapticFeedback.mediumImpact();
      setState(() => _busy = false);
      return;
    }

    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    setState(() {
      _busy = false;
      _error = err;
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => pin = '');
    });
  }

  void _openForgotPin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPinView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YColor.surface1,
      body: Row(
        children: [
          // Brand pane
          Expanded(
            flex: 42,
            child: Container(
              color: YColor.brandTint,
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _logoBlock(),
                  const Spacer(),
                  Text('"${quote.text}"',
                      style: YFont.titleLG().copyWith(fontSize: 26)),
                  const SizedBox(height: 8),
                  Text('— ${quote.author}',
                      style: YFont.bodyStrong().copyWith(color: YColor.brandDeep)),
                  const Spacer(),
                  Wrap(spacing: 10, children: const [
                    _StatPill(icon: Icons.wifi, label: 'Online'),
                    _StatPill(icon: Icons.print, label: 'Printer ready'),
                    _StatPill(icon: Icons.credit_card, label: 'Terminal paired'),
                  ]),
                ],
              ),
            ),
          ),
          // Login pane
          Expanded(
            flex: 58,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80, height: 80,
                        decoration: const BoxDecoration(color: YColor.brandTint, shape: BoxShape.circle),
                        child: const Icon(Icons.lock, size: 36, color: YColor.brand),
                      ),
                      const SizedBox(height: 12),
                      Text('Enter your PIN', style: YFont.titleMD()),
                      const SizedBox(height: 4),
                      Text('Authorized staff only', style: YFont.caption()),
                      const SizedBox(height: 24),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (_, child) {
                          final dx = sin(_shake.value * pi * 6) * 8;
                          return Transform.translate(offset: Offset(dx, 0), child: child);
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (i) => _Dot(filled: i < pin.length)),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: YColor.dangerSoft,
                            borderRadius: BorderRadius.circular(YRadius.md),
                          ),
                          child: Text(_error!,
                              style: YFont.caption()
                                  .copyWith(color: YColor.danger)),
                        ),
                      ],
                      const SizedBox(height: 28),
                      _PinPad(onDigit: _onDigit, onDelete: _onDelete),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _busy ? null : _openForgotPin,
                        style: TextButton.styleFrom(
                          foregroundColor: YColor.brandDeep,
                        ),
                        child: const Text('Forgot PIN?'),
                      ),
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

  Widget _logoBlock() {
    final state = context.watch<AppState>();
    final businessName = state.tenant?.businessName.trim().isNotEmpty == true
        ? state.tenant!.businessName
        : 'Prestige';
    final branchName = state.selectedBranch.name;
    final logoUrl = state.tenant?.logoUrl;
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;

    return Row(children: [
      Container(
        width: 56,
        height: 56,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasLogo ? YColor.surface2 : YColor.brand,
          shape: BoxShape.circle,
        ),
        child: hasLogo
            ? Image.network(
                logoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.storefront,
                    color: Colors.white, size: 24),
              )
            : const Icon(Icons.storefront, color: Colors.white, size: 24),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              businessName,
              style: YFont.titleLG().copyWith(letterSpacing: -0.3),
              overflow: TextOverflow.ellipsis,
            ),
            Text(branchName, style: YFont.caption()),
          ],
        ),
      ),
    ]);
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: YColor.surface1, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: YColor.brandDeep),
        const SizedBox(width: 6),
        Text(label, style: YFont.caption().copyWith(color: YColor.brandDeep)),
      ]),
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
        width: 14, height: 14,
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
                  onPressed: () => key == '⌫' ? onDelete() : onDigit(key),
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
          width: 78, height: 64,
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
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
