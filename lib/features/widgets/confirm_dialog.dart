import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/spacing.dart';
import '../../design_system/typography.dart';

/// App-themed yes/no confirmation popup (SweetAlert-style): a centred card with
/// an icon badge, title, message and two buttons. Returns `true` if confirmed,
/// `false` if cancelled/dismissed. Reuse this anywhere a destructive or
/// important action needs a clear "are you sure?".
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
  IconData? icon,
}) async {
  final accent = danger ? YColor.danger : YColor.brand;
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: YColor.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    icon ??
                        (danger
                            ? Icons.warning_amber_rounded
                            : Icons.help_outline),
                    color: accent,
                    size: 30),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: YFont.titleMD()),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message,
                    textAlign: TextAlign.center,
                    style: YFont.body()
                        .copyWith(color: YColor.inkMuted, height: 1.4)),
              ],
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: YColor.ink,
                      side: const BorderSide(color: YColor.hairline),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                    child: Text(cancelLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(YRadius.md)),
                    ),
                    child: Text(confirmLabel),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}
