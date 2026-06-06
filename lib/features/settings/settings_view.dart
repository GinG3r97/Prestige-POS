import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../data/supabase_client.dart';
import '../../design_system/colors.dart';
import '../../design_system/image_util.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';
import '../auth/otp_numpad.dart';
import '../pin/set_pin_view.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';
import '../printing/cash_drawer_dialog.dart';
import '../printing/printer_setup_sheet.dart';
import '../shell/nav_controller.dart';
import 'store_qr_modal.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

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
                const SizedBox(height: 20),
                _searchField(),
                if (_query.trim().isNotEmpty) _searchResults(context, state),
                if (_query.trim().isEmpty) ...[
                const SizedBox(height: 28),

                // ── Account
                _SectionHeader(title: 'Account', subtitle: 'Owner profile'),
                _Card(children: [
                  _Row(
                    leading: const Icon(Icons.person_outline, color: YColor.brandDeep),
                    title: 'Owner name',
                    subtitle: state.currentOwner?.displayName.isNotEmpty == true
                        ? state.currentOwner!.displayName
                        : 'Tap to set your name',
                    trailing: const _Badge(text: 'OWNER'),
                    onTap: () => _editOwnerName(context, state),
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
                    title: 'Change PIN',
                    subtitle: 'Verify by email, then set a new PIN',
                    onTap: () => _changePin(context, state),
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

                  // ── Tax / BIR registration
                  _SectionHeader(
                    title: 'Tax / BIR registration',
                    subtitle: (tenant.tin ?? '').trim().isEmpty
                        ? 'Add your TIN to print a BIR Sales Invoice'
                        : 'Printed on every Sales Invoice',
                  ),
                  _Card(children: [
                    _Row(
                      leading: const Icon(Icons.receipt_long_outlined,
                          color: YColor.brandDeep),
                      title: 'VAT-registered',
                      subtitle: tenant.vatRegistered
                          ? 'Invoice shows the 12% VAT breakdown'
                          : 'Non-VAT — prints "not valid for input tax"',
                      trailing: Switch(
                        value: tenant.vatRegistered,
                        activeThumbColor: YColor.brand,
                        onChanged: (v) async {
                          final err =
                              await state.updateBirInfo(vatRegistered: v);
                          if (!context.mounted) return;
                          if (err != null) {
                            _saveToast(context, err, '');
                          }
                        },
                      ),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.badge_outlined,
                          color: YColor.brandDeep),
                      title: 'TIN',
                      subtitle: (tenant.tin ?? '').isEmpty
                          ? 'Not set'
                          : tenant.tin!,
                      onTap: () => _editBirField(context, state,
                          title: 'TIN',
                          hint: '123-456-789-00000',
                          current: tenant.tin,
                          save: (v) => state.updateBirInfo(tin: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.account_tree_outlined,
                          color: YColor.brandDeep),
                      title: 'Branch code',
                      subtitle: tenant.branchCode,
                      onTap: () => _editBirField(context, state,
                          title: 'Branch code',
                          hint: '000',
                          current: tenant.branchCode,
                          save: (v) => state.updateBirInfo(branchCode: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.memory_outlined,
                          color: YColor.brandDeep),
                      title: 'Machine ID (MIN)',
                      subtitle: (tenant.birMin ?? '').isEmpty
                          ? 'Not set'
                          : tenant.birMin!,
                      onTap: () => _editBirField(context, state,
                          title: 'Machine ID (MIN)',
                          current: tenant.birMin,
                          save: (v) => state.updateBirInfo(birMin: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.tag_outlined,
                          color: YColor.brandDeep),
                      title: 'Serial number',
                      subtitle: (tenant.birSerial ?? '').isEmpty
                          ? 'Not set'
                          : tenant.birSerial!,
                      onTap: () => _editBirField(context, state,
                          title: 'Serial number',
                          current: tenant.birSerial,
                          save: (v) => state.updateBirInfo(birSerial: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.verified_outlined,
                          color: YColor.brandDeep),
                      title: 'Permit To Use (PTU) no.',
                      subtitle: (tenant.ptuNumber ?? '').isEmpty
                          ? 'Not set'
                          : tenant.ptuNumber!,
                      onTap: () => _editBirField(context, state,
                          title: 'PTU number',
                          current: tenant.ptuNumber,
                          save: (v) => state.updateBirInfo(ptuNumber: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.event_available_outlined,
                          color: YColor.brandDeep),
                      title: 'PTU valid until',
                      subtitle: (tenant.ptuValidUntil ?? '').isEmpty
                          ? 'Not set'
                          : tenant.ptuValidUntil!,
                      onTap: () => _editBirField(context, state,
                          title: 'PTU valid until',
                          hint: 'e.g. Jun 30, 2030',
                          current: tenant.ptuValidUntil,
                          save: (v) =>
                              state.updateBirInfo(ptuValidUntil: v)),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.workspace_premium_outlined,
                          color: YColor.brandDeep),
                      title: 'Accreditation no.',
                      subtitle: (tenant.birAccreditationNo ?? '').isEmpty
                          ? 'Not set'
                          : tenant.birAccreditationNo!,
                      onTap: () => _editBirField(context, state,
                          title: 'Accreditation no.',
                          current: tenant.birAccreditationNo,
                          save: (v) =>
                              state.updateBirInfo(birAccreditationNo: v)),
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
                      subtitle: (tenant.receiptHeader?.isNotEmpty ?? false) ||
                              (tenant.receiptFooter?.isNotEmpty ?? false)
                          ? 'Custom text set · tap to edit'
                          : 'Add lines under your name + a footer message',
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _ReceiptTextDialog(),
                      ),
                    ),
                    const _Divider(),
                    _Row(
                      leading: const Icon(Icons.dashboard_customize_outlined,
                          color: YColor.brandDeep),
                      title: 'Print templates & spacing',
                      subtitle: 'Receipt #${tenant.receiptTemplate} · '
                          'Ticket #${tenant.ticketTemplate} · '
                          '${tenant.printTailLines}-line gap',
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const _PrintTemplateDialog(),
                      ),
                    ),
                    const _Divider(),
                    _Row(
                      leading: _logoLeading(tenant.logoUrl),
                      title: 'Logo',
                      subtitle: (tenant.logoUrl?.isNotEmpty ?? false)
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
                      subtitle: state.printerConfig != null
                          ? 'Opens via the receipt printer on cash sales · tap to test'
                          : 'Connect a receipt printer first',
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => const CashDrawerDialog(),
                      ),
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
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const _LegalDialog(
                          title: 'Terms & Conditions', body: _kTermsText),
                    ),
                  ),
                  const _Divider(),
                  _Row(
                    leading: const Icon(Icons.privacy_tip_outlined,
                        color: YColor.brandDeep),
                    title: 'Privacy policy',
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => const _LegalDialog(
                          title: 'Privacy Policy', body: _kPrivacyText),
                    ),
                  ),
                ]),

                const SizedBox(height: 32),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
        hintText: 'Search settings…',
        hintStyle: YFont.body().copyWith(color: YColor.inkSubtle),
        filled: true,
        fillColor: YColor.surface1,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          borderSide: const BorderSide(color: YColor.brand, width: 1.5),
        ),
      ),
    );
  }

  Widget _searchResults(BuildContext context, AppState state) {
    final q = _query.trim().toLowerCase();
    final hits = _settingsIndex(context, state)
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.section.toLowerCase().contains(q) ||
            e.keywords.any((k) => k.contains(q)))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: hits.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text('No settings match "${_query.trim()}"',
                    style: YFont.body().copyWith(color: YColor.inkMuted)),
              ),
            )
          : _Card(children: [
              for (var i = 0; i < hits.length; i++) ...[
                _Row(
                  leading: Icon(hits[i].icon, color: YColor.brandDeep),
                  title: hits[i].title,
                  subtitle: hits[i].section,
                  onTap: hits[i].onTap,
                ),
                if (i != hits.length - 1) const _Divider(),
              ],
            ]),
    );
  }

  /// Flat, searchable index of the actionable settings.
  List<
      ({
        IconData icon,
        String title,
        String section,
        List<String> keywords,
        VoidCallback onTap
      })> _settingsIndex(BuildContext context, AppState state) {
    final t = state.tenant;
    return [
      (icon: Icons.person_outline, title: 'Owner name', section: 'Account', keywords: const ['name','profile'], onTap: () => _editOwnerName(context, state)),
      (icon: Icons.alternate_email, title: 'Email', section: 'Account', keywords: const ['email','login'], onTap: () => _editEmail(context, state)),
      (icon: Icons.lock_outline, title: 'Change PIN', section: 'Account', keywords: const ['pin','password','security'], onTap: () => _changePin(context, state)),
      (icon: Icons.logout, title: 'Sign out', section: 'Account', keywords: const ['logout','exit'], onTap: () => _confirmSignOut(context, state)),
      (icon: Icons.storefront, title: 'Business name', section: 'This Store', keywords: const ['store','shop','name'], onTap: () => _editStoreName(context, state)),
      (icon: Icons.place_outlined, title: 'Business address', section: 'This Store', keywords: const ['address','location'], onTap: () => _editStoreAddress(context, state)),
      (icon: Icons.badge_outlined, title: 'TIN', section: 'Tax / BIR', keywords: const ['tax','bir','tin'], onTap: () => _editBirField(context, state, title: 'TIN', current: t?.tin, save: (v) => state.updateBirInfo(tin: v))),
      (icon: Icons.account_tree_outlined, title: 'Branch code', section: 'Tax / BIR', keywords: const ['bir','branch'], onTap: () => _editBirField(context, state, title: 'Branch code', current: t?.branchCode, save: (v) => state.updateBirInfo(branchCode: v))),
      (icon: Icons.memory_outlined, title: 'Machine ID (MIN)', section: 'Tax / BIR', keywords: const ['bir','min','machine'], onTap: () => _editBirField(context, state, title: 'Machine ID (MIN)', current: t?.birMin, save: (v) => state.updateBirInfo(birMin: v))),
      (icon: Icons.tag_outlined, title: 'Serial number', section: 'Tax / BIR', keywords: const ['bir','serial','sn'], onTap: () => _editBirField(context, state, title: 'Serial number', current: t?.birSerial, save: (v) => state.updateBirInfo(birSerial: v))),
      (icon: Icons.verified_outlined, title: 'PTU number', section: 'Tax / BIR', keywords: const ['bir','ptu','permit'], onTap: () => _editBirField(context, state, title: 'PTU number', current: t?.ptuNumber, save: (v) => state.updateBirInfo(ptuNumber: v))),
      (icon: Icons.event_available_outlined, title: 'PTU valid until', section: 'Tax / BIR', keywords: const ['bir','ptu','permit'], onTap: () => _editBirField(context, state, title: 'PTU valid until', current: t?.ptuValidUntil, save: (v) => state.updateBirInfo(ptuValidUntil: v))),
      (icon: Icons.workspace_premium_outlined, title: 'Accreditation no.', section: 'Tax / BIR', keywords: const ['bir','accreditation'], onTap: () => _editBirField(context, state, title: 'Accreditation no.', current: t?.birAccreditationNo, save: (v) => state.updateBirInfo(birAccreditationNo: v))),
      (icon: Icons.receipt_outlined, title: 'Receipt header & footer', section: 'Tax & Receipts', keywords: const ['receipt','header','footer','tin'], onTap: () => showDialog(context: context, builder: (_) => const _ReceiptTextDialog())),
      (icon: Icons.dashboard_customize_outlined, title: 'Print templates & spacing', section: 'Tax & Receipts', keywords: const ['print','template','spacing','ticket','receipt'], onTap: () => showDialog(context: context, builder: (_) => const _PrintTemplateDialog())),
      (icon: Icons.image_outlined, title: 'Logo', section: 'Tax & Receipts', keywords: const ['logo','image','brand'], onTap: () => showDialog(context: context, builder: (_) => const _LogoDialog())),
      (icon: Icons.print_outlined, title: 'Receipt printer', section: 'Hardware', keywords: const ['printer','bluetooth','hardware'], onTap: () => showPrinterSetup(context)),
    ];
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

  Future<void> _editBirField(
    BuildContext context,
    AppState state, {
    required String title,
    required String? current,
    required Future<String?> Function(String) save,
    String? hint,
  }) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: title,
        controller: controller,
        hint: hint,
      ),
    );
    if (result != null) {
      final err = await save(result.trim());
      if (!context.mounted) return;
      _saveToast(context, err, '$title updated');
    }
  }

  Future<void> _editOwnerName(BuildContext context, AppState state) async {
    final controller =
        TextEditingController(text: state.currentOwner?.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Owner name',
        controller: controller,
        hint: 'Your full name',
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      final err = await state.updateOwnerName(result.trim());
      if (!context.mounted) return;
      _saveToast(context, err, 'Owner name updated');
    }
  }

  Future<void> _editEmail(BuildContext context, AppState state) async {
    // Step 1 — collect the NEW email. Start blank so they type the new one
    // rather than editing the old (clearer, and avoids accidental no-ops).
    final controller = TextEditingController();
    final newEmail = await showDialog<String>(
      context: context,
      builder: (_) => _TextFieldDialog(
        title: 'Change email',
        controller: controller,
        hint: 'new-email@example.com',
        confirmLabel: 'Send code',
      ),
    );
    if (newEmail == null || newEmail.trim().isEmpty) return;

    // Step 1b — send the OTP to the new address.
    final startErr = await state.startEmailChange(newEmail.trim());
    if (!context.mounted) return;
    if (startErr != null) {
      PushToast.show(context,
          title: 'Could not change email',
          subtitle: startErr,
          leadingIcon: Icons.error_outline);
      return;
    }

    // Step 2 — verify the 6-digit code sent to the new inbox.
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpDialog(
        email: newEmail.trim().toLowerCase(),
        purpose: 'to finish changing your email',
        verifyLabel: 'Verify & change email',
        onVerify: (code) => state.confirmEmailChange(code),
        onResend: () => state.resendEmailChangeOtp(),
      ),
    );
    if (!context.mounted) return;
    if (changed == true) {
      PushToast.show(context,
          title: 'Email updated',
          subtitle: 'Use your new email to sign in from now on.',
          leadingIcon: Icons.mark_email_read_outlined);
    } else {
      // Dialog closed without finishing — drop the pending change.
      state.cancelEmailChange();
    }
  }

  /// Change PIN: verify it's really the owner via an email OTP first, then
  /// push the PIN screen to set a new one. The new PIN overwrites the old via
  /// setOwnerPin, so this works whether or not a PIN already exists.
  Future<void> _changePin(BuildContext context, AppState state) async {
    final email = state.currentOwner?.email ?? '';
    if (email.isEmpty) {
      PushToast.show(context,
          title: "Can't verify you",
          subtitle: 'No account email on file.',
          leadingIcon: Icons.error_outline);
      return;
    }

    // 1) Confirm + send the identity code.
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: YColor.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Change PIN'),
        content: Text(
            "We'll send a 6-digit code to $email to confirm it's you. "
            'Then you can set a new PIN.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: YColor.brand, foregroundColor: Colors.white),
            child: const Text('Send code'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final sendErr = await state.sendLoginOtp(email: email);
    if (!context.mounted) return;
    if (sendErr != null) {
      PushToast.show(context,
          title: 'Could not send code',
          subtitle: sendErr,
          leadingIcon: Icons.error_outline);
      return;
    }

    // 2) Verify the code.
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OtpDialog(
        email: email,
        purpose: 'to continue',
        verifyLabel: 'Verify',
        onVerify: (code) => state.verifyOtp(code),
        onResend: () => state.resendOtp(),
      ),
    );
    if (!context.mounted) return;
    if (verified != true) {
      state.cancelOtpVerification();
      return;
    }

    // 3) Identity confirmed — set a new PIN (overwrites the old one).
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => SetPinView(
        title: 'Set a new PIN',
        subtitle: 'Enter a new 4-digit PIN for signing in on this device.',
        onCompleted: () => Navigator.of(ctx).pop(),
      ),
    ));
    if (!context.mounted) return;
    PushToast.show(context,
        title: 'PIN updated', leadingIcon: Icons.check_circle_outline);
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
    // Compact, auto-height dialog — sized to its content rather than the
    // whole screen. KeyboardAccessoryField still floats the value above the
    // keyboard, so a small centered dialog stays usable when it opens.
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
                Text(title, style: YFont.titleLG().copyWith(fontSize: 22)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 14),
              KeyboardAccessoryField(
                controller: controller,
                accessoryLabel: title,
                hint: hint,
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
                  onPressed: () => Navigator.pop(context, controller.text),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable 6-digit OTP confirm dialog. Pops `true` once [onVerify] succeeds.
/// Used for both email-change (verify the new address) and PIN-change (verify
/// the owner via a login code before letting them set a new PIN).
class _OtpDialog extends StatefulWidget {
  const _OtpDialog({
    required this.email,
    required this.purpose,
    required this.verifyLabel,
    required this.onVerify,
    required this.onResend,
  });

  /// Address the code was sent to (shown to the user).
  final String email;

  /// Sentence explaining what finishing does, e.g. "to finish changing your
  /// email" / "to continue".
  final String purpose;
  final String verifyLabel;

  /// Verifies [code]; returns null on success or a user-safe error message.
  final Future<String?> Function(String code) onVerify;

  /// Re-sends the code; returns null on success or a message.
  final Future<String?> Function() onResend;

  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  String _code = '';
  bool _busy = false;
  String? _error;

  int get _digits => SupabaseBootstrap.otpLength;

  void _onDigit(String d) {
    if (_busy || _code.length >= _digits) return;
    setState(() {
      _code += d;
      _error = null;
    });
    if (_code.length == _digits) _verify();
  }

  void _onBackspace() {
    if (_busy || _code.isEmpty) return;
    setState(() {
      _code = _code.substring(0, _code.length - 1);
      _error = null;
    });
  }

  Future<void> _verify() async {
    if (_busy || _code.length != _digits) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await widget.onVerify(_code);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
        _code = '';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _resend() async {
    if (_busy) return;
    final err = await widget.onResend();
    if (!mounted) return;
    PushToast.show(context,
        title: err == null ? 'Code resent' : 'Could not resend',
        subtitle: err ?? 'Check ${widget.email} again.',
        leadingIcon: err == null
            ? Icons.mark_email_read_outlined
            : Icons.error_outline);
  }

  @override
  Widget build(BuildContext context) {
    final left = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'We sent a $_digits-digit code to ${widget.email}. '
          'Enter it ${widget.purpose}.',
          style: YFont.body().copyWith(color: YColor.inkMuted, height: 1.4),
        ),
        const SizedBox(height: 20),
        OtpCells(code: _code, length: _digits, hasError: _error != null),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: YFont.body().copyWith(color: YColor.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        TextButton(
          onPressed: _busy ? null : _resend,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text("Didn't get it? Resend code"),
        ),
      ],
    );

    final right = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OtpNumpad(
          onDigit: _onDigit,
          onBackspace: _onBackspace,
          enabled: !_busy,
          keyWidth: 62,
          keyHeight: 46,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 250,
          child: ElevatedButton(
            onPressed: (_busy || _code.length != _digits) ? null : _verify,
            style: ElevatedButton.styleFrom(
              backgroundColor: YColor.brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(YRadius.md)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white))
                : Text(widget.verifyLabel),
          ),
        ),
      ],
    );

    return Dialog(
      backgroundColor: YColor.surface1,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('Enter code',
                    style: YFont.titleLG().copyWith(fontSize: 22)),
                const Spacer(),
                IconButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ]),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 28),
                  right,
                ],
              ),
            ],
          ),
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
            KeyboardAccessoryField(
              controller: _header,
              accessoryLabel: 'RECEIPT HEADER',
              hint: 'VAT Reg TIN 000-000-000-000\nThe best coffee in town',
              maxLines: 3,
              textAlign:
                  _align == 'center' ? TextAlign.center : TextAlign.start,
            ),
            const SizedBox(height: 16),
            Text('FOOTER', style: YFont.caption()),
            const SizedBox(height: 2),
            Text('Prints at the bottom (thank-you, promo, return policy).',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
            const SizedBox(height: 6),
            KeyboardAccessoryField(
              controller: _footer,
              accessoryLabel: 'RECEIPT FOOTER',
              hint: 'Thank you for visiting!\nFollow us @prestigecafe',
              maxLines: 3,
              textAlign:
                  _align == 'center' ? TextAlign.center : TextAlign.start,
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

/// Picks the receipt + ticket layout templates and the paper tail-spacing
/// (blank lines fed after each print). Saved as small ints on the tenant.
class _PrintTemplateDialog extends StatefulWidget {
  const _PrintTemplateDialog();

  @override
  State<_PrintTemplateDialog> createState() => _PrintTemplateDialogState();
}

class _PrintTemplateDialogState extends State<_PrintTemplateDialog> {
  late int _receipt;
  late int _ticket;
  late int _tail;
  late String _font;
  bool _busy = false;

  static const _receiptNames = {
    1: 'Standard — logo, address, full totals',
    2: 'Compact — name + items + total (saves paper)',
    3: 'Official — adds "Official Receipt" + closing line',
  };
  static const _ticketNames = {
    1: 'Standard — order #, time, items + mods',
    2: 'Minimal — order # + items only (tight)',
    3: 'Detailed — adds [ ] checkboxes + notes',
  };

  @override
  void initState() {
    super.initState();
    final t = context.read<AppState>().tenant;
    _receipt = t?.receiptTemplate ?? 1;
    _ticket = t?.ticketTemplate ?? 1;
    _tail = t?.printTailLines ?? 2;
    _font = t?.printFont ?? 'a';
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final err = await context.read<AppState>().updatePrintTemplates(
        receiptTemplate: _receipt,
        ticketTemplate: _ticket,
        tailLines: _tail,
        font: _font);
    if (!mounted) return;
    Navigator.of(context).pop();
    PushToast.show(context,
        title: err == null ? 'Print settings saved' : 'Could not save',
        subtitle: err,
        leadingIcon:
            err == null ? Icons.check_circle_outline : Icons.error_outline);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Print templates & spacing', style: YFont.titleMD()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RECEIPT LAYOUT', style: YFont.caption()),
              const SizedBox(height: 6),
              for (final e in _receiptNames.entries)
                _choice(e.key, e.value, _receipt,
                    (v) => setState(() => _receipt = v)),
              const SizedBox(height: 16),
              Text('TICKET LAYOUT (barista / kitchen)', style: YFont.caption()),
              const SizedBox(height: 6),
              for (final e in _ticketNames.entries)
                _choice(e.key, e.value, _ticket,
                    (v) => setState(() => _ticket = v)),
              const SizedBox(height: 16),
              Text('FONT SIZE', style: YFont.caption()),
              const SizedBox(height: 2),
              Text('The typeface is fixed by the printer; this picks its '
                  'built-in Normal or Small size. Small fits more per line.',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: _fontChip('Normal', 'a', Icons.text_fields),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _fontChip('Small (condensed)', 'b', Icons.short_text),
                ),
              ]),
              const SizedBox(height: 16),
              Text('PAPER GAP AFTER EACH PRINT', style: YFont.caption()),
              const SizedBox(height: 2),
              Text('Blank lines fed after a ticket so you can tear it off. '
                  'Lower = less wasted paper.',
                  style: YFont.caption().copyWith(color: YColor.inkMuted)),
              const SizedBox(height: 8),
              Row(children: [
                _stepBtn(Icons.remove, () {
                  if (_tail > 0) setState(() => _tail--);
                }),
                Container(
                  width: 56,
                  alignment: Alignment.center,
                  child: Text('$_tail',
                      style: YFont.titleMD().copyWith(color: YColor.brand)),
                ),
                _stepBtn(Icons.add, () {
                  if (_tail < 8) setState(() => _tail++);
                }),
                const SizedBox(width: 10),
                Text('lines', style: YFont.caption()),
              ]),
            ],
          ),
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

  Widget _choice(int value, String label, int selected, ValueChanged<int> onTap) {
    final on = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: on ? YColor.brandTint : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? YColor.brand : YColor.hairline,
              width: on ? 1.4 : 1),
        ),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? YColor.brand : YColor.surface1,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('$value',
                style: YFont.bodyStrong().copyWith(
                    fontSize: 13,
                    color: on ? Colors.white : YColor.inkMuted)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: YFont.body().copyWith(
                    color: on ? YColor.brandDeep : YColor.ink)),
          ),
          if (on) const Icon(Icons.check_circle, size: 18, color: YColor.brand),
        ]),
      ),
    );
  }

  Widget _fontChip(String label, String value, IconData icon) {
    final on = _font == value;
    return GestureDetector(
      onTap: () => setState(() => _font = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? YColor.brandTint : YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? YColor.brand : YColor.hairline,
              width: on ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 16, color: on ? YColor.brandDeep : YColor.inkMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YFont.bodyStrong().copyWith(
                    fontSize: 13,
                    color: on ? YColor.brandDeep : YColor.ink)),
          ),
        ]),
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: YColor.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: YColor.hairline),
        ),
        child: Icon(icon, size: 18, color: YColor.brandDeep),
      ),
    );
  }
}

const String _kTermsText = '''
By using Prestige POS ("the app"), provided by Prestige IT Solutions, you agree to these terms.

1. Licence. The app is licensed to you to operate your point-of-sale. You are responsible for the accuracy of your products, prices, taxes, and the sales you record.

2. Compliance. You are responsible for your own tax and BIR compliance — registration, permits, and the accuracy of any receipts or invoices issued through the app.

3. Accounts. Keep your login and staff PINs confidential. You are responsible for activity under your account.

4. "As is". The app is provided as is. We work to keep it reliable but do not guarantee uninterrupted service and are not liable for losses arising from downtime, device, or network issues.

5. Changes. We may update these terms and the app from time to time. Continued use means you accept the changes.

Questions? Contact us at hello@prestigeitsolutions.tech.
''';

const String _kPrivacyText = '''
Prestige IT Solutions respects your privacy. This explains what the app stores and why.

• What we store: your store details, products, inventory, staff, and the sales/orders you record — used only to operate the POS.

• Payments: card and e-wallet payments are processed outside the app. We store only the amount and any reference number you enter, for your records.

• We do not sell your data.

• Access is protected by your account login and staff PINs.

• Your data: to access, correct, or delete your store's data, contact us.

Questions? Contact us at hello@prestigeitsolutions.tech.
''';

/// A small read-only legal text viewer (Terms / Privacy).
class _LegalDialog extends StatelessWidget {
  const _LegalDialog({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 560,
        constraints: BoxConstraints(maxHeight: h < 760 ? h - 96 : 640),
        decoration: BoxDecoration(
          color: YColor.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(children: [
              const Icon(Icons.gavel_outlined, color: YColor.brandDeep),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: YFont.titleMD())),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(body.trim(),
                  style: YFont.body().copyWith(height: 1.5)),
            ),
          ),
          Container(height: 0.5, color: YColor.hairline),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Prestige POS · v1.0.0',
                style: YFont.caption().copyWith(color: YColor.inkMuted)),
          ),
        ]),
      ),
    );
  }
}
