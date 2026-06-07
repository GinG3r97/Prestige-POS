import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/category.dart';
import '../auth/auth_form_field.dart';

class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  int _step = 0;
  bool _busy = false;
  String? _error;

  // Catalog packs offered at signup — the cafe set, all pre-selected. Books /
  // Retail, Co-working and Memberships are hidden for now.
  static const _visiblePacks = [
    SellPack.coffee,
    SellPack.food,
    SellPack.drinks,
  ];
  final Set<SellPack> _picks = {..._visiblePacks};

  late final TextEditingController _businessName;
  late final TextEditingController _businessAddress;
  late final TextEditingController _branchName;

  @override
  void initState() {
    super.initState();
    final tenant = context.read<AppState>().tenant;
    _businessName = TextEditingController(text: tenant?.businessName ?? '')
      ..addListener(_onTextChanged);
    _businessAddress = TextEditingController(text: tenant?.address ?? '')
      ..addListener(_onTextChanged);
    _branchName = TextEditingController(text: 'Main Branch')
      ..addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _businessName.removeListener(_onTextChanged);
    _businessAddress.removeListener(_onTextChanged);
    _branchName.removeListener(_onTextChanged);
    _businessName.dispose();
    _businessAddress.dispose();
    _branchName.dispose();
    super.dispose();
  }

  bool get _canAdvance => switch (_step) {
        0 => _businessName.text.trim().isNotEmpty &&
            _businessAddress.text.trim().isNotEmpty,
        1 => _branchName.text.trim().isNotEmpty,
        2 => _picks.isNotEmpty,
        _ => false,
      };

  void _next() {
    if (!_canAdvance) return;
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() => _step--);
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AppState>().completeOnboarding(
          businessName: _businessName.text.trim(),
          businessAddress: _businessAddress.text.trim(),
          firstBranchName: _branchName.text.trim(),
          sellPacks: _picks,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    // On success the root Consumer<AppState> routes to SetPinView automatically.
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Adding a store from Settings (not the first-time setup).
    final canCancel = state.stores.isNotEmpty;

    return Scaffold(
      backgroundColor: YColor.surface2,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        if (canCancel)
                          Text(
                            'Add a new store',
                            style: YFont.caption().copyWith(
                              color: YColor.inkMuted,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          Text(
                            (state.currentOwner?.email.isNotEmpty == true)
                                ? 'Signed in as ${state.currentOwner!.email}'
                                : 'Setting up your business',
                            style: YFont.caption().copyWith(
                              color: YColor.inkMuted,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        const Spacer(),
                        if (canCancel)
                          TextButton.icon(
                            onPressed: () => state.cancelAddingStore(),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Cancel'),
                            style: TextButton.styleFrom(
                              foregroundColor: YColor.inkMuted,
                            ),
                          )
                        else
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    await context
                                        .read<AppState>()
                                        .signOutAccount();
                                  },
                            icon: const Icon(Icons.logout, size: 14),
                            label: const Text('Sign out'),
                            style: TextButton.styleFrom(
                              foregroundColor: YColor.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Header(step: _step),
                  const SizedBox(height: 24),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: YColor.surface1,
                        borderRadius: BorderRadius.circular(YRadius.lg),
                      ),
                      child: SingleChildScrollView(child: _stepBody()),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
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
                  const SizedBox(height: 16),
                  _Footer(
                    step: _step,
                    canAdvance: _canAdvance && !_busy,
                    busy: _busy,
                    onBack: _busy
                        ? null
                        : (_step == 0
                            ? (canCancel
                                ? () => state.cancelAddingStore()
                                : null)
                            : _back),
                    backLabel: _step == 0 && canCancel ? 'Cancel' : 'Back',
                    onNext: _next,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _stepBusiness();
      case 1:
        return _stepBranch();
      case 2:
        return _stepWhatYouSell();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepWhatYouSell() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What do you sell?',
            style: YFont.titleLG().copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text(
            "Pick everything that applies. We'll set up starter categories you can rename or extend.",
            style: YFont.body().copyWith(color: YColor.inkMuted)),
        const SizedBox(height: 20),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            // Wider than tall — fits icon + label + 1-line description.
            childAspectRatio: 4.2,
          ),
          itemCount: _visiblePacks.length,
          itemBuilder: (_, i) {
            final pack = _visiblePacks[i];
            final selected = _picks.contains(pack);
            return _PackChip(
              pack: pack,
              selected: selected,
              onTap: () => setState(() {
                if (selected) {
                  _picks.remove(pack);
                } else {
                  _picks.add(pack);
                }
              }),
            );
          },
        ),
        const SizedBox(height: 20),
        if (_picks.contains(SellPack.coworking) ||
            _picks.contains(SellPack.memberships))
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(YRadius.md),
            ),
            child: Row(children: [
              const Icon(Icons.bolt, color: YColor.brandDeep, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _picks.contains(SellPack.coworking) &&
                          _picks.contains(SellPack.memberships)
                      ? 'Bookings, Sessions & Members tabs will appear in your nav.'
                      : _picks.contains(SellPack.coworking)
                          ? 'Bookings & Sessions tabs will appear in your nav.'
                          : 'Members tab will appear in your nav.',
                  style: YFont.caption().copyWith(color: YColor.brandDeep),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _stepBusiness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tell us about your business',
            style: YFont.titleLG().copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text('You can change these later in Settings.',
            style: YFont.body().copyWith(color: YColor.inkMuted)),
        const SizedBox(height: 24),
        AuthField(
          controller: _businessName,
          label: 'Business name',
          hint: 'e.g., Beachside Inn, Downtown Cafe',
        ),
        const SizedBox(height: 14),
        AuthField(
          controller: _businessAddress,
          label: 'Business address',
          hint: 'Street, city, country',
          keyboardType: TextInputType.streetAddress,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _ReadOnlyChip(
              label: 'Currency',
              value: '₱ — Philippine Peso',
              icon: Icons.payments,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ReadOnlyChip(
              label: 'Timezone',
              value: 'Asia / Manila',
              icon: Icons.schedule,
            ),
          ),
        ]),
      ],
    );
  }

  Widget _stepBranch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your first branch',
            style: YFont.titleLG().copyWith(fontSize: 24)),
        const SizedBox(height: 8),
        Text('Most businesses start with one location. Add more in Settings later.',
            style: YFont.body().copyWith(color: YColor.inkMuted)),
        const SizedBox(height: 24),
        AuthField(
          controller: _branchName,
          label: 'Branch name',
          hint: 'Main Branch, Downtown, etc.',
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: YColor.brandTint,
            borderRadius: BorderRadius.circular(YRadius.md),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: YColor.brandDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "After this, you'll sign in to the POS terminal with a 4-digit staff PIN.",
                style: YFont.caption().copyWith(color: YColor.brandDeep),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step});
  final int step;

  static const _titles = ['Business', 'Branch', 'Catalog'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_titles.length, (i) {
        final active = i <= step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? YColor.brand : YColor.surface3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${i + 1}. ${_titles[i]}',
                    style: YFont.caption().copyWith(
                      color: active ? YColor.brandDeep : YColor.inkMuted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    )),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.canAdvance,
    required this.onBack,
    required this.onNext,
    this.backLabel = 'Back',
    this.busy = false,
  });

  final int step;
  final bool canAdvance;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final String backLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onBack,
          icon: Icon(
            backLabel == 'Cancel' ? Icons.close : Icons.arrow_back,
            size: 16,
          ),
          label: Text(backLabel),
          style: TextButton.styleFrom(
            foregroundColor: onBack == null ? YColor.inkSubtle : YColor.ink,
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: canAdvance ? onNext : null,
          icon: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(step == 2 ? Icons.check : Icons.arrow_forward, size: 16),
          label: Text(step == 2
              ? (busy ? 'Saving…' : 'Finish setup')
              : 'Continue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YRadius.md)),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyChip extends StatelessWidget {
  const _ReadOnlyChip({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: YColor.surface2,
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: YColor.inkMuted),
            const SizedBox(width: 6),
            Text(label, style: YFont.caption()),
          ]),
          const SizedBox(height: 4),
          Text(value, style: YFont.bodyStrong()),
        ],
      ),
    );
  }
}

class _PackChip extends StatelessWidget {
  const _PackChip({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  final SellPack pack;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YRadius.md),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        decoration: BoxDecoration(
          color: selected ? YColor.brandTint : YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(
            color: selected ? YColor.brand : YColor.hairline,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? YColor.brandSoft
                  : YColor.brandTint.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(pack.icon, size: 20, color: YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pack.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.bodyStrong().copyWith(
                    fontSize: 14,
                    color: selected ? YColor.brandDeep : YColor.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pack.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.caption().copyWith(
                    fontSize: 11,
                    color: selected ? YColor.brandDeep : YColor.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: selected
                ? const Icon(Icons.check_circle,
                    key: ValueKey('on'),
                    size: 18,
                    color: YColor.brand)
                : const Icon(Icons.add_circle_outline,
                    key: ValueKey('off'),
                    size: 18,
                    color: YColor.inkMuted),
          ),
        ]),
      ),
    );
  }
}
