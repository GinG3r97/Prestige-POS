import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/employee.dart';

/// The "More" hub — back-office destinations that used to clutter the bottom
/// nav. Owners and staff land here when they tap the More tab; tiles are
/// filtered by [AppState.canAccess] so each role only sees what their
/// permissions allow. Three layouts are available via the header toggle:
///   • Grouped — sections by intent (Sales / People / Catalog / Store)
///   • Grid    — flat 4-column grid, no headers
///   • List    — vertical rows, one per destination
class MoreView extends StatefulWidget {
  const MoreView({super.key});

  @override
  State<MoreView> createState() => _MoreViewState();
}

enum _MoreLayout { grouped, grid, list }

class _MoreViewState extends State<MoreView> {
  _MoreLayout _layout = _MoreLayout.grid;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sections = _buildSections(state);
    final allTiles = [for (final s in sections) ...s.tiles];
    final body = allTiles.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'You don\'t have access to any back-office screens.',
                style: YFont.caption(),
              ),
            ),
          )
        : switch (_layout) {
            _MoreLayout.grouped => _GroupedLayout(sections: sections),
            _MoreLayout.grid => _GridLayout(tiles: allTiles),
            _MoreLayout.list => _ListLayout(tiles: allTiles),
          };

    return Container(
      color: YColor.surface2,
      // Header sits outside the scroll view so it stays anchored at the top
      // while the tile grid scrolls beneath it. Both header and body are
      // horizontally centered inside the same 1080px column on wide screens.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _CenteredColumn(
              child: _Header(
                layout: _layout,
                onChange: (l) => setState(() => _layout = l),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
              child: _CenteredColumn(child: body),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the visible sections for the current user — drops sections that
  /// have zero accessible tiles so we don't render empty headers.
  List<_Section> _buildSections(AppState state) {
    const raw = <_Section>[
      _Section('Sales', YColor.brand, [
        _Tile(AppRoute.reports, Icons.insights_outlined, 'Reports',
            'Sales trends, top items, payment mix'),
      ]),
      _Section('People', Color(0xFF7C8F65), [
        _Tile(AppRoute.employees, Icons.person_outline, 'Staff',
            'Employees, roles, schedules'),
        _Tile(AppRoute.payroll, Icons.account_balance_wallet_outlined,
            'Payroll', 'Pay runs, timesheets, payslips'),
      ]),
      _Section('Catalog', Color(0xFFB07C4F), [
        _Tile(AppRoute.products, Icons.coffee_outlined, 'Products',
            'Menu items, prices, modifiers'),
      ]),
      _Section('Store', Color(0xFF6E7A8A), [
        _Tile(AppRoute.maintenance, Icons.tune_outlined, 'Maintenance',
            'Categories, modifier groups, payroll rules'),
        _Tile(AppRoute.settings, Icons.settings_outlined, 'Settings',
            'Business profile, features, branches'),
      ]),
    ];
    return raw
        .map((s) => _Section(
              s.title,
              s.accent,
              s.tiles.where((t) => state.canAccess(t.route)).toList(),
            ))
        .where((s) => s.tiles.isNotEmpty)
        .toList();
  }
}

/// Horizontally centers [child] inside a max-width column using a Row with
/// Spacers. Plain Center / Align inside a SingleChildScrollView vertically
/// centers content too, which pulls short bodies away from the top — we
/// avoid that here by relying on Row's natural cross-axis behavior.
class _CenteredColumn extends StatelessWidget {
  const _CenteredColumn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Center (not Spacer+ConstrainedBox+Spacer) so the content is capped to
    // the available width on a narrow iPad mini instead of overflowing.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: child,
      ),
    );
  }
}

class _Section {
  final String title;
  final Color accent;
  final List<_Tile> tiles;
  const _Section(this.title, this.accent, this.tiles);
}

class _Tile {
  final AppRoute route;
  final IconData icon;
  final String label;
  final String description;
  const _Tile(this.route, this.icon, this.label, this.description);
}

/// Per-route accent color used by every layout (grouped, grid, list) so
/// icon backgrounds stay visually consistent no matter which view the
/// owner picks. Mirrors the section accent in [_buildSections]; if you add
/// a new route, add it here too.
Color _accentForRoute(AppRoute r) {
  switch (r) {
    case AppRoute.reports:
      return YColor.brand;
    case AppRoute.employees:
    case AppRoute.payroll:
      return const Color(0xFF7C8F65); // muted olive — People
    case AppRoute.products:
      return const Color(0xFFB07C4F); // warm tan — Catalog
    case AppRoute.maintenance:
    case AppRoute.settings:
      return const Color(0xFF6E7A8A); // cool slate — Store
    default:
      return YColor.brandDeep;
  }
}

// ───── Header with layout toggle ──────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.layout, required this.onChange});
  final _MoreLayout layout;
  final ValueChanged<_MoreLayout> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('More',
                  style: YFont.titleLG()
                      .copyWith(fontSize: 26, letterSpacing: -0.4)),
              const SizedBox(height: 2),
              Text(
                'Back-office screens. Pick a layout that suits you.',
                style: YFont.body().copyWith(color: YColor.inkMuted),
              ),
            ],
          ),
        ),
        _LayoutToggle(layout: layout, onChange: onChange),
      ],
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  const _LayoutToggle({required this.layout, required this.onChange});
  final _MoreLayout layout;
  final ValueChanged<_MoreLayout> onChange;

  static const _items = <(_MoreLayout, IconData, String)>[
    (_MoreLayout.grouped, Icons.dashboard_outlined, 'Grouped'),
    (_MoreLayout.grid, Icons.grid_view_outlined, 'Grid'),
    (_MoreLayout.list, Icons.view_list_outlined, 'List'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YColor.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final it in _items)
            _ToggleChip(
              icon: it.$2,
              label: it.$3,
              selected: layout == it.$1,
              onTap: () => onChange(it.$1),
            ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : YColor.brandDeep;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? YColor.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: YFont.bodyStrong().copyWith(
                fontSize: 12,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ───── Layout: Grouped ────────────────────────────────────────────────

class _GroupedLayout extends StatelessWidget {
  const _GroupedLayout({required this.sections});
  final List<_Section> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          _GroupHeader(title: sections[i].title, accent: sections[i].accent),
          const SizedBox(height: 8),
          _TileGrid(tiles: sections[i].tiles),
          if (i != sections.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.accent});
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 3, height: 14, color: accent),
      const SizedBox(width: 8),
      Text(
        title.toUpperCase(),
        style: YFont.caption().copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: accent,
        ),
      ),
    ]);
  }
}

// ───── Layout: Flat grid ──────────────────────────────────────────────

class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) => _TileGrid(tiles: tiles);
}

/// Shared compact tile grid. Picks the right column count for the available
/// width so tiles never stretch into huge dead-space rectangles. Each tile
/// picks its own accent from [_accentForRoute] so the icon colors stay
/// consistent across grouped / grid / list layouts.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = switch (c.maxWidth) {
        > 900 => 4,
        > 640 => 3,
        _ => 2,
      };
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tiles.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Wider/shorter tiles — the previous 1.25 left a lot of dead
          // vertical space; 1.9 packs the icon, label, description, and
          // summary chip without making them feel cramped.
          childAspectRatio: 1.9,
        ),
        itemBuilder: (_, i) => _MoreTile(tile: tiles[i]),
      );
    });
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.tile});
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final summary = _summaryFor(context.watch<AppState>(), tile.route);
    final accent = _accentForRoute(tile.route);
    // Outer DecoratedBox carries the soft drop shadow that gives the tile
    // its floating feel; the inner Material is the surface + clip + ink.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(YRadius.lg),
          onTap: () => context.read<AppState>().selectRoute(tile.route),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YRadius.lg),
              border: Border.all(
                  color: YColor.hairline.withValues(alpha: 0.4)),
            ),
            // Stack so the summary badge can be anchored to the bottom-right
            // corner of the tile, flush with the edge, independent of the
            // text-flow column above.
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(tile.icon, size: 18, color: accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tile.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: YFont.bodyStrong().copyWith(
                                  fontSize: 14, letterSpacing: -0.2),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tile.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  YFont.caption().copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (summary != null)
                  Positioned(
                    right: 10,
                    bottom: 8,
                    child: _SummaryBadge(text: summary, accent: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny brand-accented pill at the bottom of each tile. Pulls live counts
/// from AppState so the tile is informative at a glance, not just a link.
class _SummaryBadge extends StatelessWidget {
  const _SummaryBadge({required this.text, required this.accent});
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: YFont.caption().copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: accent,
        ),
      ),
    );
  }
}

/// One-liner pulled from AppState caches — already populated by the tenant
/// restore, so reading is O(1). Returns null when there's nothing useful
/// (avoids surfacing a "0 items" badge before initial data lands).
String? _summaryFor(AppState s, AppRoute r) {
  switch (r) {
    case AppRoute.reports:
      final n = s.recentOrders.length;
      return n == 0 ? null : '$n recent orders';
    case AppRoute.employees:
      final total = s.employees.length;
      if (total == 0) return null;
      final active = s.employees
          .where((e) => e.status == EmployeeStatus.active)
          .length;
      return active == total
          ? '$total ${total == 1 ? 'employee' : 'employees'}'
          : '$active active · $total total';
    case AppRoute.payroll:
      final n = s.employees.length;
      return n == 0 ? null : '$n on payroll';
    case AppRoute.products:
      final n = s.products.length;
      return n == 0 ? null : '$n items';
    case AppRoute.maintenance:
      final c = s.categories.length;
      final m = s.modifierGroups.length;
      if (c == 0 && m == 0) return null;
      return '$c cats · $m groups';
    case AppRoute.settings:
      final branches = s.tenant?.branches.length ?? 0;
      return branches == 0
          ? null
          : '$branches branch${branches == 1 ? '' : 'es'}';
    default:
      return null;
  }
}

// ───── Layout: List ───────────────────────────────────────────────────

class _ListLayout extends StatelessWidget {
  const _ListLayout({required this.tiles});
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            _MoreListRow(tile: tiles[i]),
            if (i != tiles.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(height: 0.5, color: YColor.hairline),
              ),
          ],
        ],
      ),
    );
  }
}

class _MoreListRow extends StatelessWidget {
  const _MoreListRow({required this.tile});
  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final accent = _accentForRoute(tile.route);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.read<AppState>().selectRoute(tile.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(tile.icon, size: 18, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tile.label,
                      style:
                          YFont.bodyStrong().copyWith(fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    tile.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.caption(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right,
                size: 20, color: YColor.inkMuted),
          ]),
        ),
      ),
    );
  }
}
