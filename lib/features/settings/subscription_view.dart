import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/push_toast.dart';

/// Plan & usage screen. App Store / Play Store safe: shows the current plan,
/// live usage meters, the Store ID, and a plan comparison — with NO prices, NO
/// in-app purchase, and NO purchase buttons. A "Learn more" link opens an
/// informational plans page on the web; plan changes are handled off-app.
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
    ('Branches', '1', '1', '1 + add-ons'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshOrdersToday();
    });
  }

  /// The plans info page. Informational only: no prices and no checkout here or
  /// on the page it opens, so nothing steers the customer to an external
  /// purchase (App Store guideline 3.1.1 / Play billing safe). Change this if
  /// your info page lives elsewhere — just keep that page free of prices.
  static final Uri _learnMoreUri =
      Uri.parse('https://pos.prestigeitsolutions.tech/plans');

  /// Opens the plans info page in the browser. No in-app purchase ever.
  Future<void> _openLearnMore(BuildContext context) async {
    final ok =
        await launchUrl(_learnMoreUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      PushToast.show(context,
          title: 'Could not open',
          subtitle: 'Visit pos.prestigeitsolutions.tech/plans',
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          _hero(context, state, isPro),
          const SizedBox(height: 16),
          _usageCard(state),
          const SizedBox(height: 16),
          _compareCard(state, isPro),
          const SizedBox(height: 16),
          if (!isPro) _learnMore(context),
        ],
      ),
    );
  }

  // ── Hero: current plan + integrated Store ID ──────────────────────────────
  Widget _hero(BuildContext context, AppState state, bool isPro) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [YColor.ink, YColor.brandDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: YColor.brandDeep.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 14),
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CURRENT PLAN',
                  style: YFont.caption().copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
              const Spacer(),
              _statusPill(isPro),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(state.planLabel,
                  style: YFont.titleLG().copyWith(
                      color: Colors.white,
                      fontSize: 32,
                      letterSpacing: -0.5)),
              if (isPro) ...[
                const SizedBox(width: 8),
                Icon(Icons.workspace_premium,
                    size: 22, color: Colors.amber.shade300),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isPro
                ? 'Everything unlocked, unlimited.'
                : 'Higher limits and more features come with the Basic and Pro plans.',
            style: YFont.body()
                .copyWith(color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 18),
          _storeIdChip(context, state),
        ],
      ),
    );
  }

  Widget _statusPill(bool isPro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isPro ? Colors.greenAccent.shade400 : Colors.amber.shade300,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(isPro ? 'ACTIVE' : 'FREE TIER',
            style: YFont.caption().copyWith(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
      ]),
    );
  }

  Widget _storeIdChip(BuildContext context, AppState state) {
    final code = state.storeCode;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined,
              size: 17, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Text('STORE ID',
              style: YFont.caption().copyWith(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              code ?? '—',
              style: YFont.titleMD().copyWith(
                  color: Colors.white,
                  fontFamily: 'Menlo',
                  fontSize: 15,
                  letterSpacing: 1),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: code == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: code));
                      PushToast.show(context,
                          title: 'Store ID copied',
                          subtitle: code,
                          leadingIcon: Icons.check_circle_outline);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.copy, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Copy',
                      style: YFont.bodyStrong()
                          .copyWith(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Usage meters (icon-led) ───────────────────────────────────────────────
  Widget _usageCard(AppState state) {
    return _CardSection(
      title: 'Your usage',
      child: Column(
        children: [
          _Meter(
              icon: Icons.receipt_long_outlined,
              label: 'Orders today',
              used: state.ordersToday,
              cap: state.ordersCap),
          _Meter(
              icon: Icons.people_alt_outlined,
              label: 'Staff',
              used: state.planCount('employees'),
              cap: state.planCap('employees')),
          _Meter(
              icon: Icons.inventory_2_outlined,
              label: 'Products',
              used: state.planCount('products'),
              cap: state.planCap('products')),
          _Meter(
              icon: Icons.category_outlined,
              label: 'Categories',
              used: state.planCount('categories'),
              cap: state.planCap('categories')),
          _Meter(
              icon: Icons.warehouse_outlined,
              label: 'Inventory items',
              used: state.planCount('inventory'),
              cap: state.planCap('inventory')),
          _Meter(
              icon: Icons.location_city_outlined,
              label: 'Branches',
              used: state.planCount('branches'),
              cap: state.planCap('branches'),
              last: true),
        ],
      ),
    );
  }

  // ── Compare plans (current column highlighted) ────────────────────────────
  Widget _compareCard(AppState state, bool isPro) {
    return _CardSection(
      title: 'Compare plans',
      child: Column(
        children: [
          IntrinsicHeight(
            child: Stack(
              children: [
                // Highlight strip behind the current plan's column.
                Positioned.fill(
                  child: Row(
                    children: [
                      const Expanded(flex: 4, child: SizedBox()),
                      _highlight('trial', state.plan),
                      _highlight('basic', state.plan),
                      _highlight('pro', state.plan),
                    ],
                  ),
                ),
                Column(
                  children: [
                    _CompareRow(
                      label: '',
                      free: 'Free',
                      basic: 'Basic',
                      pro: 'Pro',
                      header: true,
                      current: state.plan,
                    ),
                    _Divider(),
                    for (var i = 0; i < _compare.length; i++) ...[
                      _CompareRow(
                        label: _compare[i].$1,
                        free: _compare[i].$2,
                        basic: _compare[i].$3,
                        pro: _compare[i].$4,
                        current: state.plan,
                      ),
                      if (i < _compare.length - 1) _Divider(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: YColor.surface2,
              borderRadius: BorderRadius.circular(YRadius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium,
                    size: 16, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pro also unlocks payroll & timekeeping, bookings, customer '
                    'subscriptions, multi-branch, and selfie-verified attendance '
                    '(anti-buddy-punch).',
                    style: YFont.caption()
                        .copyWith(color: YColor.inkMuted, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _highlight(String key, String current) {
    final on = key == current;
    return Expanded(
      flex: 3,
      child: on
          ? Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: YColor.brand.withValues(alpha: 0.4)),
              ),
            )
          : const SizedBox(),
    );
  }

  // ── Learn more (informational only — App Store / Play Store safe) ─────────
  // No prices, no purchase button, no payment wording. Just a link to the web
  // plans page; plan changes are handled off-app via Prestige IT Solutions.
  Widget _learnMore(BuildContext context) {
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
          Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.brandTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.workspace_premium_outlined,
                  size: 19, color: YColor.brandDeep),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Explore Basic & Pro',
                  style: YFont.bodyStrong().copyWith(fontSize: 15.5)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            'See what each plan includes on our website. To move to a higher '
            'plan, contact Prestige IT Solutions and share your Store ID above.',
            style: YFont.body().copyWith(color: YColor.inkMuted, height: 1.45),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openLearnMore(context),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Learn more'),
              style: OutlinedButton.styleFrom(
                foregroundColor: YColor.brandDeep,
                side: BorderSide(color: YColor.brand.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YRadius.md)),
              ),
            ),
          ),
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
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.icon,
    required this.label,
    required this.used,
    required this.cap,
    this.last = false,
  });
  final IconData icon;
  final String label;
  final int used;
  final int? cap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final unlimited = cap == null;
    final frac =
        unlimited ? 1.0 : (cap == 0 ? 1.0 : (used / cap!).clamp(0.0, 1.0));
    final atCap = !unlimited && used >= cap!;
    final near = !unlimited && !atCap && frac >= 0.7;
    final Color bar = unlimited
        ? YColor.success
        : atCap
            ? YColor.danger
            : near
                ? Colors.amber.shade600
                : YColor.brand;

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: atCap
                  ? YColor.danger.withValues(alpha: 0.12)
                  : YColor.brandTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon,
                size: 19, color: atCap ? YColor.danger : YColor.brandDeep),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(label,
                            style: YFont.body()
                                .copyWith(fontWeight: FontWeight.w600))),
                    Text(
                      unlimited ? '$used · ∞' : '$used / $cap',
                      style: YFont.body().copyWith(
                        color: atCap ? YColor.danger : YColor.inkMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 6,
                    backgroundColor: YColor.surface3,
                    color: bar,
                  ),
                ),
              ],
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
        fontSize: 12.5,
        fontWeight: header || isCurrent ? FontWeight.w800 : FontWeight.w500,
        color: isCurrent ? YColor.brandDeep : YColor.ink,
      );
    }

    Widget planCell(String text, String plan) {
      final isCurrent = (plan == 'trial' && current == 'trial') ||
          (plan == 'basic' && current == 'basic') ||
          (plan == 'pro' && current == 'pro');
      return Expanded(
        flex: 3,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (header && plan == 'pro') ...[
              Icon(Icons.workspace_premium,
                  size: 12, color: Colors.amber.shade700),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(text,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cell(plan)),
            ),
            if (header && isCurrent) ...[
              const SizedBox(width: 3),
              const Icon(Icons.check_circle,
                  size: 12, color: YColor.brandDeep),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: YFont.caption()
                    .copyWith(fontSize: 12, color: YColor.inkMuted)),
          ),
          planCell(free, 'trial'),
          planCell(basic, 'basic'),
          planCell(pro, 'pro'),
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
