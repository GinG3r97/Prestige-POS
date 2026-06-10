import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart' show iconFromKey;
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../../models/member.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// Dialog for adding or editing a single member. Surfaces every
/// editable field on one scrollable surface so the cashier can sign
/// someone up in under 30 seconds: pick a plan chip, type a name,
/// optional phone/email, save.
class MemberFormDialog extends StatefulWidget {
  const MemberFormDialog({super.key, this.existing});
  final Member? existing;

  @override
  State<MemberFormDialog> createState() => _MemberFormDialogState();
}

class _MemberFormDialogState extends State<MemberFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _notes;

  String? _planId;
  MemberStatus _status = MemberStatus.active;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _name = TextEditingController(text: m?.fullName ?? '');
    _phone = TextEditingController(text: m?.phone ?? '');
    _email = TextEditingController(text: m?.email ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _planId = m?.planId;
    _status = m?.status ?? MemberStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty && !_busy;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    String? err;
    if (_isEdit) {
      final original = widget.existing!;
      final planChanged = original.planId != _planId;
      // Save profile edits first so name / phone / email always
      // persist even if a downstream plan reassignment fails.
      final draft = Member(
        id: original.id,
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        photoUrl: original.photoUrl,
        planId: original.planId,
        planStartedAt: original.planStartedAt,
        planExpiresAt: original.planExpiresAt,
        unitsRemaining: original.unitsRemaining,
        status: _status,
        joinedAt: original.joinedAt,
        notes: _notes.text,
      );
      err = await state.updateMember(draft);
      if (err == null && planChanged && _planId != null) {
        err = await state.assignMemberPlan(
            memberId: original.id, planId: _planId!);
      }
    } else {
      err = await state.addMember(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        planId: _planId,
        notes: _notes.text,
      );
    }
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    // Re-find the freshly saved record by name (or original id) so we
    // can pop it back to the caller. The roster is sorted by name so
    // this is unique enough for a single-tenant client.
    final saved = state.members.firstWhere(
      (m) =>
          m.id == widget.existing?.id ||
          m.fullName.toLowerCase() == _name.text.trim().toLowerCase(),
      orElse: () => Member(id: '', fullName: _name.text.trim()),
    );
    Navigator.of(context).pop(saved);
  }

  Future<void> _confirmRemove() async {
    if (!_isEdit) return;
    final ok = await showConfirm(
      context,
      title: 'Remove member?',
      message: 'This permanently deletes ${widget.existing!.fullName} and '
          'their plan info. Use "Churned" status instead if you want '
          'to keep their record for analytics.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final state = context.read<AppState>();
    final err = await state.removeMember(widget.existing!.id);
    if (!mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Member removed',
        subtitle: widget.existing!.fullName,
        leadingIcon: Icons.delete_outline);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plans =
        state.memberPlans.where((p) => p.isActive).toList();
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(children: [
                Text(_isEdit ? 'Edit member' : 'Add member',
                    style: YFont.titleLG().copyWith(fontSize: 20)),
                const Spacer(),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Container(height: 0.5, color: YColor.hairline),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyboardAccessoryField(
                      controller: _name,
                      label: 'Full name',
                      accessoryLabel: 'NAME',
                      hint: 'e.g. Maria Reyes',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _phone,
                          label: 'Phone',
                          accessoryLabel: 'PHONE',
                          hint: '09xx xxx xxxx',
                          keyboardType: TextInputType.phone,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _email,
                          label: 'Email',
                          accessoryLabel: 'EMAIL',
                          hint: 'name@example.com',
                          keyboardType: TextInputType.emailAddress,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    Text('PLAN',
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    if (plans.isEmpty)
                      _noPlansBanner()
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final p in plans)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _planTile(p),
                            ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    if (_isEdit) ...[
                      Text('STATUS',
                          style: YFont.caption().copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: YColor.brandDeep,
                          )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in MemberStatus.values)
                            GestureDetector(
                              onTap: () => setState(() => _status = s),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 130),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _status == s
                                      ? s.tone
                                      : s.tone.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _status == s
                                        ? s.tone
                                        : s.tone.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  s.label,
                                  style: YFont.bodyStrong().copyWith(
                                    fontSize: 12,
                                    color:
                                        _status == s ? Colors.white : s.tone,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                    KeyboardAccessoryField(
                      controller: _notes,
                      label: 'Notes (optional)',
                      accessoryLabel: 'NOTES',
                      hint:
                          'Anything to remember — preferred desk, billing '
                          'reminders, special requests',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
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
                  ],
                ),
              ),
            ),
            Container(height: 0.5, color: YColor.hairline),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                if (_isEdit)
                  TextButton.icon(
                    onPressed: _busy ? null : _confirmRemove,
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: YColor.danger),
                    label: const Text('Remove',
                        style: TextStyle(color: YColor.danger)),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _canSave ? _save : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ))
                      : const Icon(Icons.check, size: 18),
                  label: Text(_isEdit ? 'Save changes' : 'Add member'),
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
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planTile(MemberPlan p) {
    final on = _planId == p.id;
    final accent = _accentFor(p.color);
    final icon = iconFromKey(p.iconName) ?? p.kind.icon;
    return GestureDetector(
      onTap: () => setState(() => _planId = p.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: on
              ? accent.withValues(alpha: 0.10)
              : YColor.surface1,
          borderRadius: BorderRadius.circular(YRadius.md),
          border: Border.all(
            color: on ? accent : YColor.hairline,
            width: on ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.bodyStrong().copyWith(fontSize: 14)),
                const SizedBox(height: 2),
                Text(p.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.caption().copyWith(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 140),
            child: on
                ? Icon(Icons.check_circle, key: ValueKey(p.id), color: accent)
                : Icon(Icons.radio_button_unchecked,
                    key: ValueKey('off-${p.id}'),
                    color: YColor.hairline),
          ),
        ]),
      ),
    );
  }

  Widget _noPlansBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: YColor.brandTint.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(YRadius.md),
        border: Border.all(color: YColor.hairline),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: YColor.brandDeep, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'You haven\'t set up any plan templates yet. Tap "Manage '
            'plans" on the Members page to add a "Resident Monthly", '
            '"10-Hour Pack", or "Day-Pass Pack" — then come back.',
            style: YFont.caption(),
          ),
        ),
      ]),
    );
  }

  Color _accentFor(String? hex) {
    if (hex == null || hex.isEmpty) return YColor.brand;
    final clean = hex.replaceFirst('#', '');
    final v = int.tryParse('FF$clean', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }
}
