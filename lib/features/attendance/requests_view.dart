import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/supabase_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// Owner review + approval of employee requests (leave / OT / undertime).
class RequestsView extends StatefulWidget {
  const RequestsView({super.key});

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tid = context.read<AppState>().currentTenantDbId;
    if (tid == null) {
      setState(() {
        _loading = false;
        _error = 'No store selected.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await supabase
          .from('employee_requests')
          .select(
              'id, employee_name, kind, start_date, end_date, leave_type_name, hours, reason, status, decided_by, decision_note, created_at')
          .eq('tenant_id', tid)
          .order('created_at', ascending: false);
      setState(() {
        _rows = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not load requests.';
      });
    }
  }

  Future<void> _decide(String id, bool approved) async {
    setState(() => _busy.add(id));
    try {
      await supabase.rpc('decide_request',
          params: {'p_id': id, 'p_approved': approved, 'p_note': null});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save. Try again.'),
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _rows.where((r) => r['status'] == 'pending').toList();
    final decided = _rows.where((r) => r['status'] != 'pending').toList();
    return Scaffold(
      backgroundColor: YColor.surface2,
      appBar: AppBar(
        title: const Text('Requests'),
        backgroundColor: YColor.surface1,
        foregroundColor: YColor.ink,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: YFont.body().copyWith(color: YColor.inkMuted)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sectionHeader('To approve (${pending.length})'),
                      if (pending.isEmpty)
                        _emptyCard('Nothing waiting. 🎉')
                      else
                        ...pending.map((r) => _card(r, actionable: true)),
                      if (decided.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _sectionHeader('History'),
                        ...decided.map((r) => _card(r, actionable: false)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: YFont.caption().copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: YColor.brandDeep)),
      );

  Widget _emptyCard(String t) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.lg),
          border: Border.all(color: YColor.hairline),
        ),
        child: Center(
            child: Text(t, style: YFont.body().copyWith(color: YColor.inkSubtle))),
      );

  Widget _card(Map<String, dynamic> r, {required bool actionable}) {
    final id = r['id'] as String;
    final kind = r['kind'] as String;
    final status = r['status'] as String;
    final start = r['start_date'] as String?;
    final end = r['end_date'] as String?;
    final hours = r['hours'];
    final title = kind == 'leave'
        ? (r['leave_type_name'] as String? ?? 'Leave')
        : kind == 'ot'
            ? 'Overtime'
            : 'Undertime';
    final dateText = (end != null && end != start) ? '$start → $end' : (start ?? '');
    final busy = _busy.contains(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(r['employee_name'] as String? ?? 'Employee',
                  style: YFont.titleMD().copyWith(fontSize: 15)),
            ),
            _statusChip(status),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _kindChip(title),
            const SizedBox(width: 8),
            Text(dateText, style: YFont.caption().copyWith(color: YColor.inkMuted)),
            if (hours != null) ...[
              const SizedBox(width: 8),
              Text('· ${hours}h',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
            ],
          ]),
          if ((r['reason'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(r['reason'] as String,
                style: YFont.body().copyWith(color: YColor.ink, fontSize: 13)),
          ],
          if (actionable) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : () => _decide(id, true),
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.success,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : () => _decide(id, false),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: YColor.danger,
                  side: const BorderSide(color: YColor.hairline),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ]),
          ] else if ((r['decided_by'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 6),
            Text('$status by ${r['decided_by']}',
                style: YFont.caption().copyWith(color: YColor.inkSubtle)),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = status == 'approved'
        ? YColor.success
        : status == 'rejected'
            ? YColor.danger
            : Colors.amber.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.toUpperCase(),
          style: YFont.caption().copyWith(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _kindChip(String title) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: YColor.brandTint,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(title,
            style: YFont.caption().copyWith(
                fontWeight: FontWeight.w700, color: YColor.brandDeep)),
      );
}
