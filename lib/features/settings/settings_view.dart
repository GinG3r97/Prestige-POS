import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/image_util.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import '../printing/printer_setup_sheet.dart';
import '../shell/nav_controller.dart';
import 'store_qr_modal.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final navCtrl = context.watch<NavController>();
    final tenant = state.tenant;

    return Container(
      color: YColor.surface2,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settings',
                              style: YFont.titleLG().copyWith(
                                  fontSize: 30, letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text('Configure your account, store, and POS.',
                              style: YFont.body().copyWith(
                                  color: YColor.inkMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (tenant != null)
                      OutlinedButton.icon(
                        onPressed: () => showStoreQrModal(
                          context,
                          businessName: tenant.businessName,
                        ),
                        icon: const Icon(Icons.qr_code_2, size: 18),
                        label: const Text('Store QR code'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: YColor.brand,
                          side: const BorderSide(color: YColor.hairline),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(YRadius.md)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── Account
                _SectionHeader(title: 'Account', subtitle: 'Owner profile'),
                _Card(children: [
                  _Row(
                    leading: const Icon(Icons.person_outline, color: YColor.brandDeep),
                    title: state.currentOwner?.displayName ?? '',
                    subtitle: state.currentOwner?.email ?? '',
                    trailing: const _Badge(text: 'OWNER'),
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.alternate_email,
                        color: YColor.brandDeep),
                    title: 'Email',
                    subtitle: state.currentOwner?.email ?? 'Not set',
                    onTap: () => _editEmail(context, state),
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.lock_outline, color: YColor.brandDeep),
                    title: 'Change password',
                    subtitle: 'Update your account password',
                    onTap: () => _comingSoon(context, 'Change password'),
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.logout, color: YColor.danger),
                    title: 'Sign out of account',
                    subtitle: 'Returns to the welcome screen',
                    titleColor: YColor.danger,
                    onTap: () => _confirmSignOut(context, state),
                  ),
                ]),

                const SizedBox(height: 32),

                // ── This Store
                if (tenant != null) ...[
                  _SectionHeader(
                    title: 'This Store',
                    subtitle: tenant.businessName,
                  ),
                  _Card(children: [
                    _Row(
                      leading: const Icon(Icons.storefront, color: YColor.brandDeep),
                      title: 'Business name',
                      subtitle: tenant.businessName,
                      onTap: () => _editStoreName(context, state),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.place_outlined, color: YColor.brandDeep),
                      title: 'Business address',
                      subtitle: tenant.address.isEmpty ? 'Not set' : tenant.address,
                      onTap: () => _editStoreAddress(context, state),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.payments, color: YColor.brandDeep),
                      title: 'Currency',
                      subtitle: '${tenant.currency} · ₱',
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.schedule, color: YColor.brandDeep),
                      title: 'Timezone',
                      subtitle: tenant.timezone,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Branches
                  _SectionHeader(
                    title: 'Branches',
                    subtitle: '${tenant.branches.length} location${tenant.branches.length == 1 ? '' : 's'}',
                    action: _SmallButton(
                      icon: Icons.add,
                      label: 'Add branch',
                      onPressed: () => _addBranch(context, state),
                    ),
                  ),
                  _Card(children: [
                    for (var i = 0; i < tenant.branches.length; i++) ...[
                      _Row(
                        leading: const Icon(Icons.location_city, color: YColor.brandDeep),
                        title: tenant.branches[i].name,
                        subtitle: i == 0 ? 'Primary location' : 'Branch',
                        trailing: tenant.branches.length > 1
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: YColor.inkMuted),
                                onPressed: () => state.removeBranchFromCurrentStore(
                                    tenant.branches[i].id),
                              )
                            : null,
                      ),
                      if (i != tenant.branches.length - 1) const _Divider(),
                    ],
                  ]),

                  const SizedBox(height: 24),

                  // ── Appearance
                  _SectionHeader(
                    title: 'Appearance',
                    subtitle: 'How the POS feels while you work',
                  ),
                  _Card(children: [
                    _Row(
                      leading: const Icon(Icons.fullscreen_exit,
                          color: YColor.brandDeep),
                      title: 'Auto-collapse nav',
                      subtitle:
                          'Shrink the bottom nav to a single icon when you scroll or tap',
                      trailing: Switch(
                        value: navCtrl.autoCollapse,
                        onChanged: navCtrl.setAutoCollapse,
                        activeThumbColor: YColor.brand,
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Tax & Receipts
                  _SectionHeader(title: 'Tax & Receipts'),
                  _Card(children: [
                    _Row(
                      leading: const Icon(Icons.percent, color: YColor.brandDeep),
                      title: 'VAT rate',
                      subtitle: '12% (Philippines)',
                      onTap: () => _comingSoon(context, 'VAT rate editor'),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.receipt_outlined, color: YColor.brandDeep),
                      title: 'Receipt header & footer',
                      subtitle: (tenant?.receiptHeader?.isNotEmpty ?? false) ||
                              (tenant?.receiptFooter?.isNotEmpty ?? false)
                          ? 'Custom text set · tap to edit'
                          : 'Add lines under your name + a footer message',
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _ReceiptTextDialog(),
                      ),
                    ),
                    const _Divider(),
                    _Row(
                      leading: _logoLeading(tenant?.logoUrl),
                      title: 'Logo',
                      subtitle: (tenant?.logoUrl?.isNotEmpty ?? false)
                          ? 'Tap to change or remove'
                          : 'Upload a logo for receipts & screens',
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _LogoDialog(),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ── Hardware
                  _SectionHeader(title: 'Hardware'),
                  _Card(children: [
                    _Row(
                      leading: const Icon(Icons.print_outlined, color: YColor.brandDeep),
                      title: 'Receipt printer',
                      subtitle: state.printerConfig != null
                          ? '${state.printerConfig!.name} · '
                              '${state.printerConfig!.paperWidth}mm · tap to change'
                          : 'Tap to connect a Bluetooth printer',
                      onTap: () => showPrinterSetup(context),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.monetization_on_outlined,
                          color: YColor.brandDeep),
                      title: 'Cash drawer',
                      subtitle: 'Not connected',
                      onTap: () => _comingSoon(context, 'Cash drawer'),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.credit_card, color: YColor.brandDeep),
                      title: 'Card terminal',
                      subtitle: 'Not paired',
                      onTap: () => _comingSoon(context, 'Card terminal'),
                    ),
                  ]),
                ],

                const SizedBox(height: 32),

                // ── Stores (multi-store)
                _SectionHeader(
                  title: 'Stores',
                  subtitle: '${state.stores.length} business${state.stores.length == 1 ? '' : 'es'} on this account',
                  action: _SmallButton(
                    icon: Icons.add,
                    label: 'Add store',
                    onPressed: () => state.startAddingStore(),
                  ),
                ),
                _Card(children: [
                  for (var i = 0; i < state.stores.length; i++) ...[
                    _Row(
                      leading: Icon(
                        i == state.currentStoreIndex
                            ? Icons.check_circle
                            : Icons.storefront,
                        color: i == state.currentStoreIndex
                            ? YColor.brand
                            : YColor.brandDeep,
                      ),
                      title: state.stores[i].businessName,
                      subtitle: i == state.currentStoreIndex
                          ? 'Currently active'
                          : 'Tap to switch',
                      onTap: i == state.currentStoreIndex
                          ? null
                          : () => state.switchStore(i),
                      trailing: i == state.currentStoreIndex
                          ? const _Badge(text: 'ACTIVE')
                          : null,
                    ),
                    if (i != state.stores.length - 1) const _Divider(),
                  ],
                ]),

                const SizedBox(height: 32),

                // ── About
                _SectionHeader(title: 'About'),
                _Card(children: [
                  _Row(
                    leading: const Icon(Icons.info_outline, color: YColor.brandDeep),
                    title: 'Version',
                    subtitle: 'Prestige POS · v1.0.0',
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.description_outlined,
                        color: YColor.brandDeep),
                    title: 'Terms of service',
                    onTap: () => _comingSoon(context, 'Terms'),
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.privacy_tip_outlined,
                        color: YColor.brandDeep),
                    title: 'Privacy policy',
                    onTap: () => _comingSoon(context, 'Privacy'),
                  ),
                ]),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Actions ──
  void _comingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label · coming soon')),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out of account?'),
        content: const Text(
            'This will return you to the welcome screen. In-memory data will be cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await state.signOutAccount();
  }

  Future<void> _editStoreName(BuildContext context, AppState state) async {
    final controller = TextEditingController(text: state.tenant?.businessName);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Business name',
        controller: controller,
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final err = await state.updateStoreInfo(businessName: result.trim());
      if (!context.mounted) return;
      _saveToast(context, err, 'Business name updated');
    }
  }

  Future<void> _editStoreAddress(BuildContext context, AppState state) async {
    final controller = TextEditingController(text: state.tenant?.address);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Business address',
        controller: controller,
        hint: 'Street, city, country',
      ),
    );
    if (result != null) {
      final err = await state.updateStoreInfo(address: result.trim());
      if (!context.mounted) return;
      _saveToast(context, err, 'Address updated');
    }
  }

  Future<void> _editEmail(BuildContext context, AppState state) async {
    final controller =
        TextEditingController(text: state.currentOwner?.email ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Change email',
        controller: controller,
        hint: 'name@example.com',
        confirmLabel: 'Send confirmation',
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final err = await state.updateOwnerEmail(result.trim());
      if (!context.mounted) return;
      if (err != null) {
        PushToast.show(context,
            title: 'Could not change email',
            subtitle: err,
            leadingIcon: Icons.error_outline);
      } else {
        PushToast.show(context,
            title: 'Confirmation sent',
            subtitle:
                'Check the new inbox and tap the link to finish the change.',
            leadingIcon: Icons.mark_email_read_outlined);
      }
    }
  }

  void _saveToast(BuildContext context, String? err, String okMsg) {
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
    } else {
      PushToast.show(context,
          title: okMsg, leadingIcon: Icons.check_circle_outline);
    }
  }

  Future<void> _addBranch(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Add branch',
        controller: controller,
        hint: 'e.g., Downtown, BGC, Cebu',
        confirmLabel: 'Add',
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      state.addBranchToCurrentStore(result.trim());
    }
  }
}

// ───── Reusable styled bits ─────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: YFont.titleMD().copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    )),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: YFont.caption().copyWith(color: YColor.inkMuted)),
                  ),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 0.5, color: YColor.hairline, margin: const EdgeInsets.symmetric(horizontal: 16));
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(width: 32, child: leading),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: YFont.bodyStrong()
                            .copyWith(color: titleColor ?? YColor.ink)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: YFont.caption()),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              if (onTap != null && trailing == null)
                const Icon(Icons.chevron_right,
                    color: YColor.inkMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: YColor.brandTint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: YColor.brand,
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: YColor.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(YRadius.md)),
      ),
    );
  }
}

class _TextFieldDialog extends StatelessWidget {
  const _TextFieldDialog({
    required this.title,
    required this.controller,
    this.hint,
    this.confirmLabel = 'Save',
  });

  final String title;
  final TextEditingController controller;
  final String? hint;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Strip the keyboard inset so the dialog stays full-size when the keyboard
    // opens — the KeyboardAccessoryField floats the value above the keyboard.
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 100, vertical: 60),
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: size.width - 200,
        height: size.height - 120,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(children: [
              Text(title,
                  style: YFont.titleLG().copyWith(fontSize: 22)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Floats a blurred preview card above the keyboard (so the
                    // value stays visible) and the dialog doesn't collapse.
                    KeyboardAccessoryField(
                      controller: controller,
                      accessoryLabel: title,
                      hint: hint,
                      fillColor: YColor.surface2,
                      borderColor: YColor.hairline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    Navigator.pop(context, controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: YColor.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(YRadius.md)),
                ),
                child: Text(confirmLabel),
              ),
            ]),
          ),
        ]),
      ),
    ),
    );
  }
}

/// Leading widget for the Logo settings row — shows the current logo as a
/// rounded thumbnail when set, otherwise the default image icon.
Widget _logoLeading(String? url) {
  if (url != null && url.isNotEmpty) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 28,
        height: 28,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.image_outlined, color: YColor.brandDeep),
      ),
    );
  }
  return const Icon(Icons.image_outlined, color: YColor.brandDeep);
}

/// Dialog to upload / change / remove the store logo. Picks from the gallery,
/// downsizes the image, uploads it, and saves the URL on the tenant.
class _LogoDialog extends StatefulWidget {
  const _LogoDialog();

  @override
  State<_LogoDialog> createState() => _LogoDialogState();
}

class _LogoDialogState extends State<_LogoDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final raw = await picked.readAsBytes();
      final jpeg = await compressImage(raw, maxEdge: 512, quality: 85);
      final url = await state.uploadStoreLogo(jpeg);
      final err = await state.setTenantLogo(url);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _busy = false;
          _error = err;
        });
        return;
      }
      Navigator.of(context).pop();
      PushToast.show(context,
          title: 'Logo updated',
          subtitle: 'It now shows on login, the top bar, and receipts.',
          leadingIcon: Icons.check_circle_outline);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not upload that image. Please try another.';
      });
    }
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    final err = await state.setTenantLogo(null);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    Navigator.of(context).pop();
    PushToast.show(context,
        title: 'Logo removed',
        leadingIcon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final url = context.watch<AppState>().tenant?.logoUrl;
    final hasLogo = url != null && url.isNotEmpty;
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Store logo', style: YFont.titleMD()),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: YColor.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: YColor.hairline),
              ),
              child: hasLogo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(url, fit: BoxFit.cover,
                          width: 120, height: 120, errorBuilder: (_, __, ___) {
                        return const Icon(Icons.storefront_outlined,
                            size: 44, color: YColor.inkMuted);
                      }),
                    )
                  : const Icon(Icons.storefront_outlined,
                      size: 44, color: YColor.inkMuted),
            ),
            const SizedBox(height: 14),
            Text(
              'Shown on the login screen, the top bar, and printed receipts. '
              'A square image works best.',
              textAlign: TextAlign.center,
              style: YFont.caption().copyWith(color: YColor.inkMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: YFont.caption().copyWith(color: YColor.danger)),
            ],
          ],
        ),
      ),
      actions: [
        if (hasLogo && !_busy)
          TextButton(
            onPressed: _remove,
            child: Text('Remove',
                style: YFont.bodyStrong().copyWith(color: YColor.danger)),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Close',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_outlined, size: 16),
          label: Text(hasLogo ? 'Change' : 'Upload'),
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

/// Edits the custom receipt header (lines under the business name) and footer
/// (message at the bottom). Both are multi-line and persist on the tenant.
class _ReceiptTextDialog extends StatefulWidget {
  const _ReceiptTextDialog();

  @override
  State<_ReceiptTextDialog> createState() => _ReceiptTextDialogState();
}

class _ReceiptTextDialogState extends State<_ReceiptTextDialog> {
  static const _sampleHeader =
      'VAT Reg TIN 000-000-000-000\nThanks for choosing us!';
  static const _sampleFooter =
      'Thank you for your purchase!\nThis serves as your Official Receipt.';

  late final TextEditingController _header;
  late final TextEditingController _footer;
  late String _align;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = context.read<AppState>().tenant;
    _header = TextEditingController(text: t?.receiptHeader ?? '');
    _footer = TextEditingController(text: t?.receiptFooter ?? '');
    _align = t?.receiptAlign ?? 'center';
  }

  void _insertSample() {
    setState(() {
      _header.text = _sampleHeader;
      _footer.text = _sampleFooter;
    });
  }

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final state = context.read<AppState>();
    final err = await state.updateReceiptText(
        header: _header.text, footer: _footer.text, align: _align);
    if (!mounted) return;
    Navigator.of(context).pop();
    PushToast.show(context,
        title: err == null ? 'Receipt text saved' : 'Could not save',
        subtitle: err,
        leadingIcon:
            err == null ? Icons.check_circle_outline : Icons.error_outline);
  }

  Widget _alignChip(String label, String value, IconData icon) {
    final selected = _align == value;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _align = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? YColor.brandTint : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? YColor.brand : YColor.hairline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 15,
              color: selected ? YColor.brandDeep : YColor.inkMuted),
          const SizedBox(width: 6),
          Text(label,
              style: YFont.bodyStrong().copyWith(
                fontSize: 13,
                color: selected ? YColor.brandDeep : YColor.ink,
              )),
        ]),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: YFont.caption().copyWith(color: YColor.inkSubtle),
        filled: true,
        fillColor: YColor.surface2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(YRadius.md),
          borderSide: BorderSide.none,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        Expanded(
            child: Text('Receipt header & footer', style: YFont.titleMD())),
        TextButton.icon(
          onPressed: _busy ? null : _insertSample,
          icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
          label: const Text('Insert sample'),
          style: TextButton.styleFrom(foregroundColor: YColor.brandDeep),
        ),
      ]),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('HEADER', style: YFont.caption()),
            const SizedBox(height: 2),
            Text('Prints under your business name (e.g. TIN, tagline).',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _header,
              maxLines: 3,
              style: YFont.body(),
              decoration: _dec('VAT Reg TIN 000-000-000-000\nThe best coffee in town'),
            ),
            const SizedBox(height: 16),
            Text('FOOTER', style: YFont.caption()),
            const SizedBox(height: 2),
            Text('Prints at the bottom (thank-you, promo, return policy).',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _footer,
              maxLines: 3,
              style: YFont.body(),
              decoration: _dec('Thank you for visiting!\nFollow us @prestigecafe'),
            ),
            const SizedBox(height: 16),
            Text('ALIGNMENT', style: YFont.caption()),
            const SizedBox(height: 6),
            Row(children: [
              _alignChip('Centered', 'center', Icons.format_align_center),
              const SizedBox(width: 8),
              _alignChip('Left', 'left', Icons.format_align_left),
            ]),
            const SizedBox(height: 4),
            Text('Your business name always prints centered.',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: YFont.bodyStrong().copyWith(color: YColor.inkMuted)),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: YColor.brand,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
