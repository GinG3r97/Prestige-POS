import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/stores/members_store.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart'
    show iconFromKey, NameIconOrEmoji;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/member.dart';
import '../widgets/push_toast.dart';
import 'member_form_dialog.dart';
import 'plans_manager_sheet.dart';

/// Member roster page. Owner-facing summary of who's paying for what
/// and when each subscription expires. Built around the four filter
/// chips at the top (All / Active / Expiring / Lapsed / Churned) and
/// a grid of full-bleed member cards underneath. The "Manage plans"
/// button opens a separate sheet for plan templates, since plans are
/// configuration the owner sets up once.
enum _RosterFilter { all, active, expiring, lapsed, churned }

extension on _RosterFilter {
  String get label => switch (this) {
        _RosterFilter.all => 'All',
        _RosterFilter.active => 'Active',
        _RosterFilter.expiring => 'Expiring soon',
        _RosterFilter.lapsed => 'Lapsed',
        _RosterFilter.churned => 'Churned',
      };
}

class MembersView extends StatefulWidget {
  const MembersView({super.key});

  @override
  State<MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends State<MembersView> {
  _RosterFilter _filter = _RosterFilter.all;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Member> _filtered(List<Member> members) {
    final q = _search.text.trim().toLowerCase();
    Iterable<Member> base = members;
    switch (_filter) {
      case _RosterFilter.all:
        break;
      case _RosterFilter.active:
        base = base.where((m) => m.status == MemberStatus.active);
      case _RosterFilter.expiring:
        base = base.where(
            (m) => m.status == MemberStatus.active && m.isExpiringSoon);
      case _RosterFilter.lapsed:
        base = base.where((m) => m.status == MemberStatus.lapsed);
      case _RosterFilter.churned:
        base = base.where((m) => m.status == MemberStatus.churned);
    }
    if (q.isEmpty) return base.toList();
    return base
        .where((m) =>
            m.fullName.toLowerCase().contains(q) ||
            (m.phone ?? '').toLowerCase().contains(q) ||
            (m.email ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MembersStore>();
    final members = state.members;
    final filtered = _filtered(members);
    final hasMembers = members.isNotEmpty;

    return Container(
      color: YColor.surface2,
      child: Column(
        children: [
          _header(state),
          if (hasMembers) _statsHero(state),
          if (hasMembers) _filterBar(members),
          Expanded(
            child: hasMembers
                ? (filtered.isEmpty
                    ? _emptyFilter()
                    : _grid(filtered, state))
                : _firstTimeEmpty(state),
          ),
        ],
      ),
    );
  }

  Widget _header(MembersStore state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 16),
      decoration: const BoxDecoration(
        color: YColor.surface1,
        border: Border(
          bottom: BorderSide(color: YColor.hairline, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: YColor.brandTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.card_membership_outlined,
                color: YColor.brandDeep, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Members',
                    style: YFont.titleLG().copyWith(
                        fontSize: 22, letterSpacing: -0.3)),
                const SizedBox(height: 3),
                Text(
                  'Monthly residents, hour packs, day-pass packs — recurring '
                  'revenue you can rely on.',
                  style: YFont.caption(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _openPlansSheet(),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Manage plans'),
            style: OutlinedButton.styleFrom(
              foregroundColor: YColor.brandDeep,
              side: const BorderSide(color: YColor.hairline),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed:
                state.memberPlans.isEmpty ? null : () => _openMemberForm(null),
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Add member'),
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsHero(MembersStore state) {
    final mrr = state.monthlyRecurringRevenueCents / 100.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: LayoutBuilder(builder: (_, c) {
        final cols = c.maxWidth > 1100
            ? 4
            : c.maxWidth > 720
                ? 4
                : c.maxWidth > 480
                    ? 2
                    : 1;
        final cards = <Widget>[
          _statCard(
            icon: Icons.payments_outlined,
            label: 'Monthly recurring revenue',
            value: '₱${mrr.toStringAsFixed(0)}',
            sub: 'from active monthly subs',
            accent: YColor.brand,
          ),
          _statCard(
            icon: Icons.group_outlined,
            label: 'Active members',
            value: '${state.activeMemberCount}',
            sub: 'of ${state.members.length} total',
            accent: MemberStatus.active.tone,
          ),
          _statCard(
            icon: Icons.hourglass_bottom_rounded,
            label: 'Expiring in 7 days',
            value: '${state.expiringSoonCount}',
            sub: 'good moment to reach out',
            accent: MemberStatus.lapsed.tone,
          ),
          _statCard(
            icon: Icons.trending_down_rounded,
            label: 'Lapsed',
            value: '${state.lapsedMemberCount}',
            sub: 'expired but not cancelled',
            accent: YColor.danger,
          ),
        ];
        final gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((c) => SizedBox(width: w, child: c)).toList(),
        );
      }),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YFont.caption().copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: YColor.inkMuted,
                  )),
            ),
          ]),
          const SizedBox(height: 10),
          Text(value,
              style: YFont.titleLG().copyWith(
                fontSize: 26,
                letterSpacing: -0.6,
                color: YColor.ink,
              )),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: YFont.caption().copyWith(fontSize: 11)),
        ],
      ),
    );
  }

  Widget _filterBar(List<Member> all) {
    final counts = {
      _RosterFilter.all: all.length,
      _RosterFilter.active:
          all.where((m) => m.status == MemberStatus.active).length,
      _RosterFilter.expiring: all
          .where(
              (m) => m.status == MemberStatus.active && m.isExpiringSoon)
          .length,
      _RosterFilter.lapsed:
          all.where((m) => m.status == MemberStatus.lapsed).length,
      _RosterFilter.churned:
          all.where((m) => m.status == MemberStatus.churned).length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in _RosterFilter.values) ...[
                  _filterChip(f, counts[f] ?? 0),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 260,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, email…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: YColor.surface1,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(YRadius.md),
                  borderSide: const BorderSide(color: YColor.hairline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(YRadius.md),
                  borderSide: const BorderSide(color: YColor.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(YRadius.md),
                  borderSide:
                      const BorderSide(color: YColor.brand, width: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_RosterFilter f, int count) {
    final on = _filter == f;
    return GestureDetector(
      onTap: () => setState(() => _filter = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: on ? YColor.brand : YColor.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? YColor.brand : YColor.hairline,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            f.label,
            style: YFont.bodyStrong().copyWith(
              fontSize: 12,
              color: on ? Colors.white : YColor.ink,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: on
                  ? Colors.white.withValues(alpha: 0.2)
                  : YColor.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$count',
                style: YFont.caption().copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : YColor.inkMuted,
                )),
          ),
        ]),
      ),
    );
  }

  Widget _grid(List<Member> members, MembersStore state) {
    return LayoutBuilder(builder: (_, c) {
      final cols = (c.maxWidth / 380).floor().clamp(1, 4);
      const gap = 14.0;
      final w = (c.maxWidth - 40 - gap * (cols - 1)) / cols;
      return SingleChildScrollView(
        // Bottom padding clears the floating nav pill (~70px tall +
        // safe-area inset + lift) so the last roster row isn't tucked
        // behind it once you've added enough members to scroll.
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final m in members)
              SizedBox(
                width: w,
                child: _MemberCard(
                  member: m,
                  plan: state.memberPlanById(m.planId),
                  onTap: () => _openMemberForm(m),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _firstTimeEmpty(MembersStore state) {
    final hasPlans = state.memberPlans.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: const BoxDecoration(
                  color: YColor.brandTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.card_membership_outlined,
                    size: 42, color: YColor.brandDeep),
              ),
              const SizedBox(height: 16),
              Text(
                hasPlans ? 'No members yet' : 'Set up your first plan',
                style: YFont.titleMD().copyWith(fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                hasPlans
                    ? 'Sign up your first regular — a monthly resident, an '
                        'hour-pack customer, or a day-pass holder. They\'ll '
                        'show up here with their balance and renewal date.'
                    : 'Plans are the products you sell to members — "Resident '
                        'Monthly", "10-Hour Pack", "5 Day-Passes". Set up one '
                        'or two, then come back to add your first member.',
                textAlign: TextAlign.center,
                style: YFont.caption(),
              ),
              const SizedBox(height: 18),
              if (hasPlans)
                ElevatedButton.icon(
                  onPressed: () => _openMemberForm(null),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add your first member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _openPlansSheet,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Set up plans'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyFilter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_off_outlined,
                size: 42, color: YColor.inkMuted),
            const SizedBox(height: 10),
            Text('No members match this filter',
                style: YFont.bodyStrong()),
            const SizedBox(height: 4),
            Text(
              _search.text.isNotEmpty
                  ? 'Try clearing the search box or pick a different filter.'
                  : 'Pick a different filter to see other members.',
              textAlign: TextAlign.center,
              style: YFont.caption(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMemberForm(Member? existing) async {
    final result = await showDialog<Member>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MemberFormDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    PushToast.show(
      context,
      title: existing == null ? 'Member added' : 'Member updated',
      subtitle: result.fullName,
      leadingIcon: Icons.check_circle_outline,
    );
  }

  Future<void> _openPlansSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlansManagerSheet(),
    );
  }
}

/// A single member tile — photo / initials, name + status pill, plan
/// summary, balance bar, and a renewal countdown. Tapping the card
/// opens the member form for editing.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.plan,
    required this.onTap,
  });
  final Member member;
  final MemberPlan? plan;
  final VoidCallback onTap;

  Color get _planAccent {
    final raw = plan?.color;
    if (raw == null || raw.isEmpty) return YColor.brand;
    final hex = raw.replaceFirst('#', '');
    final v = int.tryParse('FF$hex', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  IconData get _planIcon {
    if (plan == null) return Icons.help_outline;
    return iconFromKey(plan!.iconName) ?? plan!.kind.icon;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = member.balanceFraction(plan);
    final balanceText = member.balanceDisplay(plan);
    final statusTone = member.status.tone;
    final daysLeft = member.daysUntilExpiry;
    final emphasiseExpiry = member.status == MemberStatus.active &&
        daysLeft != null &&
        daysLeft <= 7;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.lg),
            border:
                Border.all(color: YColor.hairline.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _avatar(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YFont.bodyStrong().copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member.phone?.isNotEmpty == true
                              ? member.phone!
                              : (member.email?.isNotEmpty == true
                                  ? member.email!
                                  : 'No contact info'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YFont.caption().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _statusPill(statusTone, member.status.label),
                ]),
                const SizedBox(height: 14),
                // Plan summary line — icon + plan name + price.
                Container(
                  padding:
                      const EdgeInsets.fromLTRB(10, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: _planAccent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(YRadius.md),
                  ),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _planAccent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(_planIcon, size: 14, color: _planAccent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        plan?.name ?? 'No plan assigned',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YFont.bodyStrong().copyWith(
                            fontSize: 12, color: _planAccent),
                      ),
                    ),
                    if (plan != null)
                      Text(
                        '₱${plan!.pricePesos.toStringAsFixed(0)}',
                        style: YFont.bodyStrong().copyWith(
                          fontSize: 12,
                          color: _planAccent,
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Text(
                      balanceText.toUpperCase(),
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w800,
                        color: emphasiseExpiry
                            ? MemberStatus.lapsed.tone
                            : YColor.inkMuted,
                      ),
                    ),
                  ),
                  if (plan != null && fraction > 0)
                    Text(
                      '${(fraction * 100).round()}%',
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _planAccent,
                      ),
                    ),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor: YColor.surface2,
                    valueColor: AlwaysStoppedAnimation(
                      emphasiseExpiry
                          ? MemberStatus.lapsed.tone
                          : _planAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    if (member.photoUrl != null && member.photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(YRadius.md),
        child: Image.network(
          member.photoUrl!,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          cacheWidth: 120,
          cacheHeight: 120,
          errorBuilder: (_, _, _) => _initialsTile(),
        ),
      );
    }
    return _initialsTile();
  }

  Widget _initialsTile() {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _planAccent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(YRadius.md),
      ),
      child: NameIconOrEmoji(
        name: member.fullName,
        fallbackIcon: Icons.person_outline,
        iconSize: 20,
      ),
    );
  }

  Widget _statusPill(Color tone, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label.toUpperCase(),
          style: YFont.caption().copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: tone,
          )),
    );
  }
}
