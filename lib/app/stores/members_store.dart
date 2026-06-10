import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../data/supabase_client.dart';
import '../../models/member.dart';

/// Owns the Members domain (member roster + plan templates), extracted
/// from the monolithic [AppState] so that Sell / Products / etc. watching
/// AppState no longer rebuild when a member or plan changes. All member-data
/// consumers watch this store directly.
///
/// AppState owns a single instance ([AppState.members]) and drives its
/// lifecycle via [hydrate] (on tenant restore) and [reset] (on sign-out /
/// tenant switch). The Supabase calls, sorting, and notify timing are
/// identical to what AppState used to do inline.
class MembersStore extends ChangeNotifier {
  /// The active tenant DB id, set by [hydrate]. All mutations are scoped to
  /// this tenant. `null` means no store is selected (signed out / no tenant).
  String? _tenantId;

  // ───── members + plan templates (Supabase-backed) ────────────────

  List<MemberPlan> _memberPlans = [];
  List<MemberPlan> get memberPlans => List.unmodifiable(_memberPlans);

  List<Member> _members = [];
  List<Member> get members => List.unmodifiable(_members);

  MemberPlan? memberPlanById(String? id) {
    if (id == null) return null;
    for (final p in _memberPlans) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Active members = status=active AND plan hasn't expired. Lapsed =
  /// expired but not yet churned. Churned = explicitly removed. The
  /// roster filter chips use these counts.
  int get activeMemberCount =>
      _members.where((m) => m.status == MemberStatus.active).length;
  int get lapsedMemberCount =>
      _members.where((m) => m.status == MemberStatus.lapsed).length;
  int get churnedMemberCount =>
      _members.where((m) => m.status == MemberStatus.churned).length;
  int get expiringSoonCount => _members
      .where((m) => m.status == MemberStatus.active && m.isExpiringSoon)
      .length;

  /// Estimated monthly recurring revenue in centavos, summed from
  /// active monthly subscriptions only. Hour-packs and day-pass
  /// packs are one-time so they don't count toward MRR.
  int get monthlyRecurringRevenueCents {
    var total = 0;
    for (final m in _members) {
      if (m.status != MemberStatus.active) continue;
      final p = memberPlanById(m.planId);
      if (p == null || p.kind != MemberPlanKind.monthly) continue;
      // Normalize to a 30-day month so 60-day plans count for half.
      total += ((p.priceCents * 30) / p.durationDays).round();
    }
    return total;
  }

  /// Loads the plan templates + member roster for [tenantId] from Supabase,
  /// reconciles statuses, then notifies. Called by AppState during tenant
  /// hydration. Both tables are tenant-scoped and small enough to load
  /// up-front so the Members page is instant.
  Future<void> hydrate(String tenantId) async {
    _tenantId = tenantId;

    final planRows = await supabase
        .from('member_plans')
        .select('*')
        .eq('tenant_id', tenantId)
        .order('sort_order');
    _memberPlans = (planRows as List)
        .map((r) => MemberPlan.fromRow(r as Map<String, dynamic>))
        .toList();

    final memberRows = await supabase
        .from('members')
        .select('*')
        .eq('tenant_id', tenantId)
        .order('full_name');
    _members = (memberRows as List)
        .map((r) => Member.fromRow(r as Map<String, dynamic>))
        .toList();
    _reconcileMemberStatuses();
    notifyListeners();
  }

  /// Clears all member state (sign-out / tenant switch).
  void reset() {
    _tenantId = null;
    _memberPlans = [];
    _members = [];
    notifyListeners();
  }

  /// Walks the roster and bumps `status` to lapsed when a member's
  /// plan has expired. Pure client-side reconciliation — keeps the
  /// roster filter accurate without us needing a cron job. Called on
  /// every restore.
  void _reconcileMemberStatuses() {
    final now = DateTime.now();
    for (final m in _members) {
      if (m.status != MemberStatus.active) continue;
      final expires = m.planExpiresAt;
      if (expires != null && expires.isBefore(now)) {
        m.status = MemberStatus.lapsed;
      }
    }
  }

  // ── Plan template CRUD ──

  Future<String?> addMemberPlan(MemberPlan plan) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (plan.name.trim().isEmpty) return 'Plan name is required.';
    try {
      final row = await supabase
          .from('member_plans')
          .insert(plan.toRowPayload(tenantId))
          .select('*')
          .single();
      _memberPlans.add(MemberPlan.fromRow(row));
      _memberPlans.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not add plan: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> updateMemberPlan(MemberPlan updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.name.trim().isEmpty) return 'Plan name is required.';
    try {
      final row = await supabase
          .from('member_plans')
          .update(updated.toRowPayload(tenantId))
          .eq('id', updated.id)
          .select('*')
          .single();
      final fresh = MemberPlan.fromRow(row);
      final i = _memberPlans.indexWhere((p) => p.id == fresh.id);
      if (i >= 0) _memberPlans[i] = fresh;
      _memberPlans.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not update plan: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  Future<String?> removeMemberPlan(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('member_plans').delete().eq('id', id);
      _memberPlans.removeWhere((p) => p.id == id);
      // FK on members.plan_id is ON DELETE SET NULL — any member who
      // was on this plan now sits with plan_id = NULL, surfacing as
      // "No plan" until the owner reassigns.
      for (final m in _members) {
        if (m.planId == id) {
          m.planId = null;
          m.planStartedAt = null;
          m.planExpiresAt = null;
          m.unitsRemaining = null;
        }
      }
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete plan: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  // ── Member CRUD ──

  /// Insert a new member. If [planId] is provided, the subscription
  /// window is initialized using the plan's [durationDays] and
  /// [includedUnits] so the cashier doesn't have to compute it.
  Future<String?> addMember({
    required String fullName,
    String? phone,
    String? email,
    String? photoUrl,
    String? planId,
    String? notes,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (fullName.trim().isEmpty) return 'Member name is required.';
    final now = DateTime.now();
    final plan = memberPlanById(planId);
    final m = Member(
      id: '00000000-0000-0000-0000-000000000000',
      fullName: fullName.trim(),
      phone: phone,
      email: email,
      photoUrl: photoUrl,
      planId: planId,
      planStartedAt: plan == null ? null : now,
      planExpiresAt:
          plan == null ? null : now.add(Duration(days: plan.durationDays)),
      unitsRemaining: plan == null
          ? null
          : (plan.kind == MemberPlanKind.monthly ? null : plan.includedUnits),
      joinedAt: now,
      notes: notes,
    );
    try {
      final payload = Map<String, dynamic>.from(m.toRowPayload(tenantId))
        ..remove('id');
      final row = await supabase
          .from('members')
          .insert(payload)
          .select('*')
          .single();
      _members.add(Member.fromRow(row));
      _members.sort((a, b) => a.fullName
          .toLowerCase()
          .compareTo(b.fullName.toLowerCase()));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A member with that phone number already exists.';
      }
      return 'Could not add member: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Persist edits to a member's profile (name / phone / email /
  /// photo / notes / status). Plan changes go through
  /// [assignMemberPlan] so the subscription window stays consistent.
  Future<String?> updateMember(Member updated) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    if (updated.fullName.trim().isEmpty) return 'Member name is required.';
    try {
      final row = await supabase
          .from('members')
          .update(updated.toRowPayload(tenantId))
          .eq('id', updated.id)
          .select('*')
          .single();
      final fresh = Member.fromRow(row);
      final i = _members.indexWhere((m) => m.id == fresh.id);
      if (i >= 0) _members[i] = fresh;
      _members.sort((a, b) => a.fullName
          .toLowerCase()
          .compareTo(b.fullName.toLowerCase()));
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      if (e.code == '23505') {
        return 'A member with that phone number already exists.';
      }
      return 'Could not update member: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }

  /// Assigns or replaces a member's plan. Starts a fresh subscription
  /// window (`plan_started_at = now`, `plan_expires_at = now +
  /// duration_days`) and refreshes the unit balance. Use this when
  /// the cashier sells a renewal or upgrade — NOT for status edits.
  Future<String?> assignMemberPlan({
    required String memberId,
    required String planId,
  }) async {
    final tenantId = _tenantId;
    if (tenantId == null) return 'No store selected.';
    final member = _members.firstWhere(
      (m) => m.id == memberId,
      orElse: () => Member(id: '', fullName: ''),
    );
    if (member.id.isEmpty) return 'That member no longer exists.';
    final plan = memberPlanById(planId);
    if (plan == null) return 'That plan no longer exists.';
    final now = DateTime.now();
    member.planId = planId;
    member.planStartedAt = now;
    member.planExpiresAt = now.add(Duration(days: plan.durationDays));
    member.unitsRemaining = plan.kind == MemberPlanKind.monthly
        ? null
        : plan.includedUnits;
    member.status = MemberStatus.active;
    return updateMember(member);
  }

  Future<String?> removeMember(String id) async {
    if (_tenantId == null) return 'No store selected.';
    try {
      await supabase.from('members').delete().eq('id', id);
      _members.removeWhere((m) => m.id == id);
      notifyListeners();
      return null;
    } on sb.PostgrestException catch (e) {
      return 'Could not delete member: ${e.message}';
    } catch (_) {
      return 'Could not reach the server. Please try again.';
    }
  }
}
