import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/spacing.dart';
import '../../design_system/themed_dropdown.dart';
import '../../design_system/typography.dart';
import '../../models/booking.dart';
import '../widgets/keyboard_accessory_field.dart';
import '../widgets/push_toast.dart';

/// Maintenance tab where owners manage what customers can reserve —
/// meeting rooms, hot desks, event spaces. Each row drives a column on
/// the Bookings calendar.
class BookableResourcesTab extends StatelessWidget {
  const BookableResourcesTab({super.key, required this.state});
  final AppState state;

  /// Curated brand-friendly palette owners pick from when setting a
  /// resource's accent. Maps a friendly label to its hex string + a
  /// solid Color for the swatch tile.
  static const palette = <(String label, String hex, Color preview)>[
    ('Brand', '#B07C4F', Color(0xFFB07C4F)),
    ('Olive', '#7C8F65', Color(0xFF7C8F65)),
    ('Slate', '#6E7A8A', Color(0xFF6E7A8A)),
    ('Claret', '#A04545', Color(0xFFA04545)),
    ('Forest', '#5C8A6B', Color(0xFF5C8A6B)),
    ('Navy', '#3D5A7A', Color(0xFF3D5A7A)),
    ('Mustard', '#C29A36', Color(0xFFC29A36)),
    ('Plum', '#8A5A8A', Color(0xFF8A5A8A)),
  ];

  static Color hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return YColor.brand;
    final clean = hex.replaceFirst('#', '');
    final v = int.tryParse('FF$clean', radix: 16);
    return v == null ? YColor.brand : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final resources = state.bookableResources;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bookable resources',
                          style: YFont.titleMD().copyWith(fontSize: 20)),
                      const SizedBox(height: 2),
                      Text(
                        'Anything the customer can reserve on the Bookings '
                        'calendar — meeting rooms, hot desks, event spaces. '
                        'Set capacity, hourly rate, and an accent colour per row.',
                        style: YFont.caption(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                ElevatedButton.icon(
                  onPressed: () => _openForm(context, state, null),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add resource'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              if (resources.isEmpty)
                _empty()
              else
                LayoutBuilder(builder: (ctx, c) {
                  final cols = c.maxWidth > 900
                      ? 4
                      : c.maxWidth > 640
                          ? 3
                          : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: resources.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      // Wider than tall — keeps the tile compact since
                      // the content is just an icon + name + 3 chips.
                      childAspectRatio: 1.7,
                    ),
                    itemBuilder: (_, i) {
                      final r = resources[i];
                      return _ResourceTile(
                        resource: r,
                        accent: hexToColor(r.color),
                        onTap: () => _openForm(context, state, r),
                        onRemove: () => _confirmRemove(context, state, r),
                      );
                    },
                  );
                }),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: YColor.surface1,
        borderRadius: BorderRadius.circular(YRadius.lg),
        border: Border.all(color: YColor.hairline),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_available_outlined,
              size: 38, color: YColor.inkMuted),
          const SizedBox(height: 8),
          Text('No bookable resources yet', style: YFont.bodyStrong()),
          const SizedBox(height: 4),
          Text(
            'Tap "Add resource" to create your first one — e.g. "Meeting Room A", '
            '"Hot Desk 1", or "Event Space".',
            textAlign: TextAlign.center,
            style: YFont.caption(),
          ),
        ],
      ),
    );
  }

  Future<void> _openForm(BuildContext context, AppState state,
      BookableResource? existing) async {
    final saved = await showDialog<BookableResource>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BookableResourceDialog(initial: existing),
    );
    if (saved == null || !context.mounted) return;
    final err = existing == null
        ? await state.addBookableResource(saved)
        : await state.updateBookableResource(saved);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not save',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: existing == null ? 'Resource added' : 'Resource updated',
        subtitle: saved.name,
        leadingIcon: saved.kind.icon);
  }

  Future<void> _confirmRemove(BuildContext context, AppState state,
      BookableResource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove "${r.name}"?'),
        content: const Text(
            'Existing bookings on this resource will block deletion. '
            'Cancel or complete them first.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove',
                style: TextStyle(color: YColor.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final err = await state.removeBookableResource(r.id);
    if (!context.mounted) return;
    if (err != null) {
      PushToast.show(context,
          title: 'Could not remove',
          subtitle: err,
          leadingIcon: Icons.error_outline);
      return;
    }
    PushToast.show(context,
        title: 'Resource removed',
        subtitle: r.name,
        leadingIcon: Icons.delete_outline);
  }
}

class _ResourceTile extends StatelessWidget {
  const _ResourceTile({
    required this.resource,
    required this.accent,
    required this.onTap,
    required this.onRemove,
  });
  final BookableResource resource;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final iconData =
        iconFromKey(resource.iconName) ?? resource.kind.icon;
    // Use a Stack so the accent stripe and the uniform hairline border
    // can coexist with a rounded outer corner. (BoxDecoration won't let
    // you mix per-side border colors with borderRadius.)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(YRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            color: YColor.surface1,
            borderRadius: BorderRadius.circular(YRadius.lg),
            border: Border.all(color: YColor.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(YRadius.lg),
            child: Stack(
              children: [
                // Accent stripe down the left edge.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 3, color: accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
                  // Fill the tile vertically so the Spacer below pushes
                  // the badge chips to the bottom edge, regardless of
                  // resource name length.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(iconData, size: 16, color: accent),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    resource.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: YFont.bodyStrong().copyWith(fontSize: 13),
                  ),
                ),
                IconButton(
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 28, minHeight: 28),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                  icon: const Icon(Icons.delete_outline,
                      color: YColor.inkMuted),
                ),
              ]),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(resource.kind.label),
                  _chip('${resource.capacity} pax',
                      icon: Icons.people_outline),
                  _chip(
                    '₱${resource.hourlyRatePesos.toStringAsFixed(0)}/hr',
                    tone: YColor.brand,
                  ),
                  if (!resource.isActive)
                    _chip('Inactive',
                        tone: YColor.danger,
                        icon: Icons.visibility_off_outlined),
                ],
              ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, {Color? tone, IconData? icon}) {
    final c = tone ?? YColor.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: YFont.caption().copyWith(
            fontSize: 10,
            color: c,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ]),
    );
  }
}

class _BookableResourceDialog extends StatefulWidget {
  const _BookableResourceDialog({this.initial});
  final BookableResource? initial;

  @override
  State<_BookableResourceDialog> createState() =>
      _BookableResourceDialogState();
}

class _BookableResourceDialogState extends State<_BookableResourceDialog> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final TextEditingController _rate;
  late final TextEditingController _sortOrder;
  late final TextEditingController _notes;

  BookableKind _kind = BookableKind.room;
  String _color = '#B07C4F';
  String? _iconName;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _name = TextEditingController(text: r?.name ?? '');
    _capacity = TextEditingController(text: (r?.capacity ?? 1).toString());
    _rate = TextEditingController(
        text: r == null ? '' : r.hourlyRatePesos.toStringAsFixed(0));
    _sortOrder =
        TextEditingController(text: (r?.sortOrder ?? 100).toString());
    _notes = TextEditingController(text: r?.notes ?? '');
    _kind = r?.kind ?? BookableKind.room;
    _color = r?.color ?? '#B07C4F';
    _iconName = r?.iconName;
    _isActive = r?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _rate.dispose();
    _sortOrder.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave => _name.text.trim().isNotEmpty;

  void _save() {
    final rate = double.tryParse(_rate.text) ?? 0;
    final saved = BookableResource(
      id: widget.initial?.id ?? '00000000-0000-0000-0000-000000000000',
      name: _name.text.trim(),
      kind: _kind,
      capacity: int.tryParse(_capacity.text) ?? 1,
      hourlyRateCents: (rate * 100).round(),
      color: _color,
      iconName: _iconName,
      sortOrder: int.tryParse(_sortOrder.text) ?? 100,
      isActive: _isActive,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: YColor.surface1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(children: [
                Text(
                  widget.initial == null
                      ? 'Add Bookable Resource'
                      : 'Edit Bookable Resource',
                  style: YFont.titleLG().copyWith(fontSize: 20),
                ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4, bottom: 6),
                                child:
                                    Text('Icon', style: YFont.caption()),
                              ),
                              IconPickerField(
                                value: _iconName,
                                fallbackName: _name.text.isEmpty
                                    ? _kind.label
                                    : _name.text,
                                fallbackIcon: _kind.icon,
                                onChanged: (key) =>
                                    setState(() => _iconName = key),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: KeyboardAccessoryField(
                            controller: _name,
                            label: 'Name',
                            accessoryLabel: 'NAME',
                            hint: 'e.g. Meeting Room A, Hot Desk 1',
                            fillColor: YColor.surface1,
                            borderColor: YColor.hairline,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: ThemedDropdown<BookableKind>(
                          label: 'Type',
                          value: _kind,
                          items: BookableKind.values,
                          labelOf: (k) => k.label,
                          iconOf: (k) => k.icon,
                          onChanged: (k) {
                            if (k != null) setState(() => _kind = k);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _capacity,
                          label: 'Capacity (pax)',
                          accessoryLabel: 'CAPACITY',
                          hint: '1',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _rate,
                          label: 'Hourly rate (₱)',
                          accessoryLabel: 'RATE',
                          hint: '0',
                          keyboardType: TextInputType.number,
                          formatPreview: (raw) {
                            final n = double.tryParse(raw) ?? 0;
                            return '₱${n.toStringAsFixed(0)}/hr';
                          },
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: KeyboardAccessoryField(
                          controller: _sortOrder,
                          label: 'Order',
                          accessoryLabel: 'ORDER',
                          hint: '100',
                          keyboardType: TextInputType.number,
                          fillColor: YColor.surface1,
                          borderColor: YColor.hairline,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    Text('Accent colour'.toUpperCase(),
                        style: YFont.caption().copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: YColor.brandDeep,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children:
                          BookableResourcesTab.palette.map((entry) {
                        final (label, hex, preview) = entry;
                        final selected =
                            _color.toLowerCase() == hex.toLowerCase();
                        return GestureDetector(
                          onTap: () => setState(() => _color = hex),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? preview.withValues(alpha: 0.18)
                                  : YColor.surface1,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: selected
                                    ? preview
                                    : YColor.hairline,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: preview,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(label,
                                    style: YFont.bodyStrong().copyWith(
                                      fontSize: 12,
                                      color: selected
                                          ? preview
                                          : YColor.ink,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    KeyboardAccessoryField(
                      controller: _notes,
                      label: 'Notes (optional)',
                      accessoryLabel: 'NOTES',
                      hint:
                          'House rules, AV available, layout — anything '
                          'the cashier should know',
                      fillColor: YColor.surface1,
                      borderColor: YColor.hairline,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Switch(
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        activeThumbColor: YColor.brand,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _isActive
                              ? 'Active — shows on the Bookings calendar'
                              : 'Hidden — won\'t appear on the calendar',
                          style: YFont.caption(),
                        ),
                      ),
                    ]),
                  ],
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
                  onPressed: _canSave ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: YColor.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YRadius.md)),
                  ),
                  child: Text(widget.initial == null
                      ? 'Add resource'
                      : 'Save changes'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
