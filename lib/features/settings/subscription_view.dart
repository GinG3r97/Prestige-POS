import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/push_toast.dart';

/// Plan & usage screen. Apple-safe: shows the current plan, live usage meters,
/// the Store ID, and a plan comparison — but NO in-app purchase or payment.
/// Upgrades happen on the website using the Store ID.
class SubscriptionView extends StatefulWidget {
  const SubscriptionView({super.key});

  @override
  State<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<SubscriptionView> {
  // Keep in sync with public.plan_limits.
  static const _compare = <(String, String, String, String)>[
    ('Orders / day', '20', '100', 'Unlimited'),
    ('Staff', '2', '5', 'Unlimited'),
    ('Products', '25', '100', 'Unlimited'),
    ('Categories', '6', '15', 'Unlimited'),
    ('Inventory items', '15', '60', 'Unlimited'),
    ('Branches', '1', '1', 'Multiple'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshOrdersToday();
    });
  }

  /// Opens the secure web payment page with the Store ID + owner email
  /// pre-filled, so the owner doesn't have to copy/paste anything. Payment
  /// happens on the web (never in-app).
  Future<void> _openUpgrade(BuildContext context, AppState state) async {
    final email = state.currentOwner?.email ?? '';
    final uri = Uri.https('prestigeitsolutions.tech', '/upgrade', {
      if (state.storeCode != null) 'code': state.storeCode!,
      if (email.isNotEmpty) 'email': email,
    });
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      PushToast.show(context,
          title: 'Could not open',
          subtitle: 'Visit prestigeitsolutions.tech/upgrade',
          leadingIcon: Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isPro = state.plan == 'pro';

    return Scaffold(
      backgroundColor: YColor.surface2,
      appBar: AppBar(
        title: const Text('Subscription'),
        backgroundColor: YColor.surface1,
        foregroundColor: YColor.ink,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Current plan
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [YColor.brandDeep, YColor.brand],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(YRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT PLAN',
                    style: YFont.caption().copyWith(
                        color: Colors.white70,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(state.planLabel,
                    style: YFont.titleLG()
                        .copyWith(color: Colors.white, fontSize: 30)),
                const SizedBox(height: 4),
                Text(
                  isPro
                      ? 'Everything unlocked, unlimited.'
                      : 'Upgrade for higher limits and more features.',
                  style: YFont.body().copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Store ID
          _CardSection(
            title: 'Store ID',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.storeCode ?? '—',
                    style: YFont.titleMD().copyWith(
                        fontFamily: 'Menlo', letterSpacing: 1, fontSize: 18),
                  ),
                ),
                TextButton.icon(
                  onPressed: state.storeCode == null
                      ? null
                      : () {
                          Clipboard.setData(
                              ClipboardData(text: state.storeCode!));
                          PushToast.show(context,
                              title: 'Copied',
                              subtitle: state.storeCode!,
                              leadingIcon: Icons.check_circle_outline);
                        },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy'),
                  style: TextButton.styleFrom(foregroundColor: YColor.brandDeep),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Usage meters
          _CardSection(
            title: 'Your usage',
            child: Column(
              children: [
                _Meter(label: 'Orders today', used: state.ordersToday, cap: state.ordersCap),
                _Meter(label: 'Staff', used: state.planCount('employees'), cap: state.planCap('employees')),
                _Meter(label: 'Products', used: state.planCount('products'), cap: state.planCap('products')),
                _Meter(label: 'Categories', used: state.planCount('categories'), cap: state.planCap('categories')),
                _Meter(label: 'Inventory items', used: state.planCount('inventory'), cap: state.planCap('inventory')),
                _Meter(label: 'Branches', used: state.planCount('branches'), cap: state.planCap('branches'), last: true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Plan comparison
          _CardSection(
            title: 'Compare plans',
            child: Column(
              children: [
                _CompareRow(
                  label: '',
                  free: 'Free',
                  basic: 'Basic',
                  pro: 'Pro',
                  header: true,
                  current: state.plan,
                ),
                const _Divider(),
                for (final r in _compare) ...[
                  _CompareRow(
                    label: r.$1,
                    free: r.$2,
                    basic: r.$3,
                    pro: r.$4,
                    current: state.plan,
                  ),
                  const _Divider(),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Pro also unlocks payroll & timekeeping, bookings, customer subscriptions, and multi-branch.',
                    style: YFont.caption().copyWith(color: YColor.inkMuted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Upgrade — Android deep-links to the pre-filled web payment page.
          // iOS must NOT surface external payment (App Store 3.1.1), so the
          // button is hidden there; a neutral note shows instead (below).
          if (!isPro && !Platform.isIOS)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.public, size: 18, color: YColor.brandDeep),
                    const SizedBox(width: 8),
                    Text('Upgrade your plan',
                        style: YFont.bodyStrong()
                            .copyWith(color: YColor.brandDeep)),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                    'Opens your secure GCash payment page with your Store ID '
                    'and email already filled in — no copy/paste needed.',
                    style: YFont.body().copyWith(color: YColor.ink, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openUpgrade(context, state),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open payment page'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: YColor.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(YRadius.md)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // iOS-only neutral note (App Store-safe: no external payment).
          if (!isPro && Platform.isIOS)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(YRadius.md),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: YColor.brandDeep),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your plan is managed by Prestige IT Solutions. '
                    'Contact us to change it.',
                    style: YFont.body().copyWith(color: YColor.ink, height: 1.4),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: YFont.caption().copyWith(
                  color: YColor.brandDeep,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.used,
    required this.cap,
    this.last = false,
  });
  final String label;
  final int used;
  final int? cap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final unlimited = cap == null;
    final frac = unlimited ? 0.0 : (cap == 0 ? 1.0 : (used / cap!).clamp(0.0, 1.0));
    final atCap = !unlimited && used >= cap!;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: YFont.body().copyWith(fontWeight: FontWeight.w600))),
              Text(
                unlimited ? '$used · ∞' : '$used / $cap',
                style: YFont.body().copyWith(
                  color: atCap ? YColor.danger : YColor.inkMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: unlimited ? null : frac,
              minHeight: 6,
              backgroundColor: YColor.surface3,
              color: atCap ? YColor.danger : YColor.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.free,
    required this.basic,
    required this.pro,
    required this.current,
    this.header = false,
  });
  final String label;
  final String free, basic, pro, current;
  final bool header;

  @override
  Widget build(BuildContext context) {
    TextStyle cell(String plan) {
      final isCurrent = (plan == 'trial' && current == 'trial') ||
          (plan == 'basic' && current == 'basic') ||
          (plan == 'pro' && current == 'pro');
      return YFont.caption().copyWith(
        fontSize: 12,
        fontWeight: header || isCurrent ? FontWeight.w800 : FontWeight.w500,
        color: isCurrent ? YColor.brandDeep : YColor.ink,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: YFont.caption()
                    .copyWith(fontSize: 12, color: YColor.inkMuted)),
          ),
          Expanded(flex: 3, child: Text(free, textAlign: TextAlign.center, style: cell('trial'))),
          Expanded(flex: 3, child: Text(basic, textAlign: TextAlign.center, style: cell('basic'))),
          Expanded(flex: 3, child: Text(pro, textAlign: TextAlign.center, style: cell('pro'))),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: YColor.hairline.withValues(alpha: 0.6));
}
