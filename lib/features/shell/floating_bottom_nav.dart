import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/typography.dart';
import 'nav_controller.dart';

class FloatingBottomNav extends StatefulWidget {
  const FloatingBottomNav({super.key});

  @override
  State<FloatingBottomNav> createState() => _FloatingBottomNavState();
}

class _FloatingBottomNavState extends State<FloatingBottomNav> {
  /// Maps a selected route to the primary-nav tab that should look active.
  /// Routes shown inside the More hub (Reports, Staff, Payroll, Products,
  /// Maintenance, Settings) all anchor to AppRoute.more so the user can
  /// see which bucket they're in.
  static AppRoute _navAnchorFor(AppRoute r) {
    const inMore = <AppRoute>{
      AppRoute.reports,
      AppRoute.employees,
      AppRoute.payroll,
      AppRoute.products,
      AppRoute.maintenance,
      AppRoute.settings,
    };
    return inMore.contains(r) ? AppRoute.more : r;
  }

  /// Primary bottom-nav destinations. Daily-use only — back-office screens
  /// (Reports, Staff, Payroll, Products, Maintenance, Settings) live behind
  /// the "More" hub so the nav doesn't get crowded. Feature-flagged tabs
  /// (Bookings / Sessions / Members) appear only when the tenant has those
  /// flags on, and every item is permission-gated via [AppState.canAccess].
  List<_NavSpec> _buildItems(AppState state) {
    final f = state.features;
    final all = <_NavSpec>[
      const _NavSpec(
        route: AppRoute.dashboard,
        icon: Icons.space_dashboard_outlined,
        label: 'Home',
      ),
      const _NavSpec(
          route: AppRoute.sell,
          icon: Icons.storefront_outlined,
          label: 'Sell'),
      if (f.reserveEnabled)
        const _NavSpec(
            route: AppRoute.bookings,
            icon: Icons.event_available_outlined,
            label: 'Bookings'),
      if (f.timerEnabled)
        const _NavSpec(
            route: AppRoute.sessions,
            icon: Icons.timer_outlined,
            label: 'Sessions'),
      if (f.subscribeEnabled)
        const _NavSpec(
            route: AppRoute.members,
            icon: Icons.card_membership_outlined,
            label: 'Members'),
      const _NavSpec(
          route: AppRoute.orders,
          icon: Icons.receipt_long_outlined,
          label: 'Orders'),
      const _NavSpec(
          route: AppRoute.tabs,
          icon: Icons.schedule_outlined,
          label: 'Tabs'),
      const _NavSpec(
          route: AppRoute.inventory,
          icon: Icons.inventory_2_outlined,
          label: 'Stock'),
      const _NavSpec(
          route: AppRoute.more,
          icon: Icons.apps_outlined,
          label: 'More'),
    ];
    return all.where((s) => state.canAccess(s.route)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final navCtrl = context.watch<NavController>();
    final lowStockCount = state.lowStockCount;
    final expanded = navCtrl.expanded;
    final allItems = _buildItems(state);

    // If the currently selected route is no longer accessible (e.g. owner
    // just trimmed permissions on this user's role), snap back to the first
    // allowed tab on the next frame so we never render a forbidden screen.
    // We check canAccess (not membership in the primary nav) so secondary
    // destinations behind the More hub (Maintenance, Settings, …) don't
    // trigger the snap-back.
    if (allItems.isNotEmpty && !state.canAccess(state.selectedRoute)) {
      final fallback = allItems.first.route;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) state.selectedRoute = fallback;
      });
    }

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              // Two-stop shadow gives the pill a sense of weight — a
              // sharper near-shadow for the contact, and a soft, wide
              // ambient one further down so it reads as floating.
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 48,
                  offset: const Offset(0, 18),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                // Blur sigma stays high enough to fully smear the
                // background; saturation bump pushes warmth through
                // the glass so the nav inherits the room's colour
                // rather than looking sterile-white.
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                  inner: const ColorFilter.matrix(<double>[
                    1.32, 0,    0,    0, 0,
                    0,    1.32, 0,    0, 0,
                    0,    0,    1.32, 0, 0,
                    0,    0,    0,    1, 0,
                  ]),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  child: _GlassSurface(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      child: expanded
                          ? _ExpandedRow(
                              items: allItems,
                              // If the active route is one of More's
                              // child destinations, highlight the More
                              // tab so the nav stays in sync with
                              // where the user is.
                              selectedRoute:
                                  _navAnchorFor(state.selectedRoute),
                              lowStockCount: lowStockCount,
                              onSelect: state.selectRoute,
                            )
                          : _CompactButton(
                              onTap: () => navCtrl.toggle(),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stacks three light layers onto the same rounded surface so the
/// pill reads as iOS-style "liquid glass" rather than a plain
/// translucent rectangle. The order matters:
///
/// 1. **Body**: a three-stop vertical gradient — bright white at the
///    top, neutral white at the midline, warm brand tint at the
///    bottom — gives the impression of light bending through the
///    glass from above.
/// 2. **Specular sheen**: a top-half gradient that fades from white
///    to transparent, creating the "wet" highlight that catches the
///    eye and makes the curvature legible.
/// 3. **Edge highlight**: a hairline white border at high alpha to
///    catch the rim, with a subtle dark inner halo at the very bottom
///    for weight.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Layer 1 — glass body with a warm three-stop gradient.
        // [child] sizes the Stack, so the gloss + edge layers below
        // automatically match.
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.72),
                Colors.white.withValues(alpha: 0.42),
                const Color(0xFFEDE3D6).withValues(alpha: 0.42),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.78),
              width: 1.0,
            ),
          ),
          child: child,
        ),
        // Layer 2 — specular sheen. Bright in the top third, fades
        // out by the middle. IgnorePointer so it doesn't eat taps.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Colors.white.withValues(alpha: 0.55),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Layer 3 — bottom-half darkening for refraction depth so the
        // pill doesn't look flat. Very subtle.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFFB07C4F).withValues(alpha: 0.08),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single round icon shown when the nav is collapsed. Tapping it expands the
/// full row back out with the center-outward unfurl.
class _CompactButton extends StatelessWidget {
  const _CompactButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 50,
          height: 50,
          alignment: Alignment.center,
          child: const Icon(
            Icons.space_dashboard_outlined,
            size: 24,
            color: YColor.brandDeep,
          ),
        ),
      ),
    );
  }
}

/// Full nav row. Compact icon-only tiles; the selected tile inflates to
/// show its label inside a brand pill. Each tile owns its own background +
/// label animation — no per-frame measurement, no white flash.
class _ExpandedRow extends StatelessWidget {
  const _ExpandedRow({
    required this.items,
    required this.selectedRoute,
    required this.lowStockCount,
    required this.onSelect,
  });

  final List<_NavSpec> items;
  final AppRoute selectedRoute;
  final int lowStockCount;
  final ValueChanged<AppRoute> onSelect;

  @override
  Widget build(BuildContext context) {
    final centerIdx = (items.length - 1) / 2;
    final maxDist = centerIdx;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            _UnfurlTile(
              indexFromCenter: i - centerIdx,
              normalizedDist:
                  maxDist == 0 ? 0 : (i - centerIdx).abs() / maxDist,
              child: _NavTile(
                icon: items[i].icon,
                label: items[i].label,
                selected: selectedRoute == items[i].route,
                onTap: () => onSelect(items[i].route),
                badge: items[i].route == AppRoute.inventory &&
                        lowStockCount > 0
                    ? lowStockCount.toString()
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Wraps a tile in a fade + horizontal slide animation that runs once on
/// mount. [indexFromCenter] gives the tile's signed distance from the center
/// (negative = left of center). [normalizedDist] is 0..1 (center..edge) and
/// drives the stagger interval.
class _UnfurlTile extends StatelessWidget {
  const _UnfurlTile({
    required this.indexFromCenter,
    required this.normalizedDist,
    required this.child,
  });

  final double indexFromCenter;
  final double normalizedDist;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Start the animation later for tiles further from the center.
    final start = (normalizedDist * 0.55).clamp(0.0, 0.9);
    final interval = Interval(start, 1.0, curve: Curves.easeOutCubic);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 520),
      curve: interval,
      builder: (_, t, c) {
        // Tiles on the left side of center get a positive nudge (pull right →
        // toward center) at the start, and ease back to their natural spot.
        // Tiles on the right get a negative nudge (pull left → toward center).
        final dir = indexFromCenter < 0 ? 1.0 : -1.0;
        final dx = dir * 28.0 * (1 - t);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

class _NavSpec {
  const _NavSpec({
    required this.route,
    required this.icon,
    required this.label,
  });
  final AppRoute route;
  final IconData icon;
  final String label;
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 22,
                color: selected ? Colors.white : YColor.brandDeep),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: YColor.danger,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        label,
                        style: YFont.bodyStrong().copyWith(
                          color: Colors.white,
                          fontSize: 15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}
