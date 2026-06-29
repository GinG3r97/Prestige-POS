import 'package:flutter/material.dart';

import '../../data/supabase_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// Owner-only screen to grant other people web-portal access to this store.
/// Co-owners sign in on the web portal with their email and see the sales
/// dashboard alongside the owner — they can't run the POS or change settings.
class CoOwnersView extends StatefulWidget {
  const CoOwnersView({super.key});

  @override
  State<CoOwnersView> createState() => _CoOwnersViewState();
}

class _CoOwner {
  const _CoOwner(this.email, this.role);
  final String email;
  final String role;
}

class _CoOwnersViewState extends State<CoOwnersView> {
  bool _loading = true;
  bool _error = false;
  List<_CoOwner> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rows = await supabase.rpc('tenant_members_list') as List;
      final members = rows
          .map((r) => _CoOwner(
                (r['email'] ?? '').toString(),
                (r['role'] ?? 'owner').toString(),
              ))
          .where((m) => m.email.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _members = members;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _add() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCoOwnerDialog(),
    );
    if (email == null || email.trim().isEmpty) return;
    try {
      await supabase.rpc('tenant_member_add', params: {'p_email': email.trim()});
      if (!mounted) return;
      PushToast.show(context,
          title: 'Co-owner added',
          subtitle: '${email.trim().toLowerCase()} can now sign in on the '
              'web portal to see this store.',
          leadingIcon: Icons.check_circle_outline);
      _load();
    } catch (e) {
      if (!mounted) return;
      PushToast.show(context,
          title: 'Could not add',
          subtitle: _friendly(e),
          leadingIcon: Icons.error_outline);
    }
  }

  Future<void> _remove(String email) async {
    final ok = await showConfirm(
      context,
      title: 'Remove co-owner?',
      message: '$email will lose access to this store\'s sales and dashboard.',
      confirmLabel: 'Remove',
      danger: true,
      icon: Icons.person_remove_outlined,
    );
    if (!ok) return;
    try {
      await supabase.rpc('tenant_member_remove', params: {'p_email': email});
      if (!mounted) return;
      PushToast.show(context,
          title: 'Co-owner removed', leadingIcon: Icons.check_circle_outline);
      _load();
    } catch (e) {
      if (!mounted) return;
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: _friendly(e),
          leadingIcon: Icons.error_outline);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('BAD_EMAIL')) return 'That doesn\'t look like a valid email.';
    if (s.contains('ALREADY_OWNER')) return 'That\'s already the owner\'s email.';
    if (s.contains('NOT_OWNER')) {
      return 'Only the store owner can manage co-owners.';
    }
    return 'Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YColor.surface2,
      appBar: AppBar(
        backgroundColor: YColor.surface1,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: YColor.ink),
        title: Text('Co-owners', style: YFont.titleMD()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'People you add here can sign in on the web portal with their '
                  'email to see this store\'s sales and dashboard — alongside you. '
                  'They can\'t run the POS or change your store settings.',
                  style: YFont.body().copyWith(color: YColor.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error)
                  _emptyCard('Couldn\'t load co-owners.', retry: true)
                else ...[
                  if (_members.isEmpty)
                    _emptyCard('No co-owners yet. Add someone by email below.')
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: YColor.surface1,
                        borderRadius: BorderRadius.circular(YRadius.lg),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _members.length; i++) ...[
                            _memberRow(_members[i]),
                            if (i != _members.length - 1)
                              Container(
                                height: 0.5,
                                color: YColor.hairline,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Add co-owner'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: YColor.brand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberRow(_CoOwner m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 32,
            child: Icon(Icons.account_circle_outlined, color: YColor.brandDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.email, style: YFont.bodyStrong()),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Co-owner · web portal access',
                      style: YFont.caption()),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: YColor.inkMuted),
            onPressed: () => _remove(m.email),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String msg, {bool retry = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline),
      ),
      child: Column(
        children: [
          Text(msg,
              textAlign: TextAlign.center,
              style: YFont.body().copyWith(color: YColor.inkMuted)),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class _AddCoOwnerDialog extends StatefulWidget {
  const _AddCoOwnerDialog();

  @override
  State<_AddCoOwnerDialog> createState() => _AddCoOwnerDialogState();
}

class _AddCoOwnerDialogState extends State<_AddCoOwnerDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: YColor.surface1,
      insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('Add co-owner', style: YFont.titleLG().copyWith(fontSize: 22)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 6),
              Text('They\'ll sign in on the web portal with this email.',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              const SizedBox(height: 14),
              KeyboardAccessoryField(
                controller: _ctrl,
                accessoryLabel: 'Co-owner email',
                hint: 'name@example.com',
                keyboardType: TextInputType.emailAddress,
                fillColor: YColor.surface2,
                borderColor: YColor.hairline,
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _ctrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                  child: const Text('Add'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
