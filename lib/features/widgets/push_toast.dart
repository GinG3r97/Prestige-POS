import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../design_system/colors.dart';
import '../../design_system/icons.dart';
import '../../design_system/typography.dart';

/// iOS-style push notification toast that slides down from the top edge with
/// a glass card. Auto-dismisses after [duration]; tap to dismiss early.
///
/// Leading thumbnail precedence (same ladder as product tiles):
///   1. [leadingImageUrl] — uploaded image (cover-fit)
///   2. [leadingIconName] — curated Material-icon key
///   3. [leadingIcon] — explicit IconData
///   4. [leadingEmoji] — last resort glyph
///   5. default bell
class PushToast {
  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? leadingImageUrl,
    String? leadingIconName,
    String? leadingEmoji,
    IconData? leadingIcon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    final controller = _ToastController();

    entry = OverlayEntry(
      builder: (ctx) => _PushToastView(
        controller: controller,
        title: title,
        subtitle: subtitle,
        leadingImageUrl: leadingImageUrl,
        leadingIconName: leadingIconName,
        leadingEmoji: leadingEmoji,
        leadingIcon: leadingIcon,
        duration: duration,
        onDismissed: () {
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

class _ToastController {
  void Function()? dismiss;
}

class _PushToastView extends StatefulWidget {
  const _PushToastView({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.leadingImageUrl,
    required this.leadingIconName,
    required this.leadingEmoji,
    required this.leadingIcon,
    required this.duration,
    required this.onDismissed,
  });

  final _ToastController controller;
  final String title;
  final String? subtitle;
  final String? leadingImageUrl;
  final String? leadingIconName;
  final String? leadingEmoji;
  final IconData? leadingIcon;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_PushToastView> createState() => _PushToastViewState();
}

class _PushToastViewState extends State<_PushToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 240),
    );
    widget.controller.dismiss = _dismiss;
    _anim.forward();
    _autoDismiss = Timer(widget.duration, _dismiss);
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    _autoDismiss?.cancel();
    if (_anim.status == AnimationStatus.dismissed ||
        _anim.status == AnimationStatus.reverse) return;
    await _anim.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final progress = _anim.value.clamp(0.0, 1.0);
        final t = Curves.easeOutBack.transform(progress);
        return Positioned(
          top: topInset + 12,
          left: 0,
          right: 0,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, (1 - t) * -80),
              child: Opacity(opacity: progress, child: child),
            ),
          ),
        );
      },
      child: _ToastCard(
        title: widget.title,
        subtitle: widget.subtitle,
        leadingImageUrl: widget.leadingImageUrl,
        leadingIconName: widget.leadingIconName,
        leadingEmoji: widget.leadingEmoji,
        leadingIcon: widget.leadingIcon,
        onTap: _dismiss,
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({
    required this.title,
    required this.subtitle,
    required this.leadingImageUrl,
    required this.leadingIconName,
    required this.leadingEmoji,
    required this.leadingIcon,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? leadingImageUrl;
  final String? leadingIconName;
  final String? leadingEmoji;
  final IconData? leadingIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, minWidth: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
                decoration: BoxDecoration(
                  color: YColor.surface1.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: YColor.hairline,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Row(children: [
                  _leading(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YFont.bodyStrong().copyWith(
                            fontSize: 14,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: YFont.caption().copyWith(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'now',
                      style: YFont.caption().copyWith(
                        fontSize: 10,
                        color: YColor.inkSubtle,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _leading() {
    // Precedence: image → curated icon key → explicit IconData → emoji
    // → default bell. Image fills the 36px tile cover-fit with rounded
    // corners; falls back to the brand-tinted tile on network error.
    if (leadingImageUrl != null && leadingImageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          leadingImageUrl!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconTile(),
        ),
      );
    }
    return _iconTile();
  }

  Widget _iconTile() {
    final curatedIcon = iconFromKey(leadingIconName);
    final iconData = curatedIcon ?? leadingIcon;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: YColor.brand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: iconData != null
          ? Icon(iconData, color: Colors.white, size: 18)
          : (leadingEmoji != null
              ? Text(leadingEmoji!, style: const TextStyle(fontSize: 20))
              : const Icon(Icons.notifications,
                  color: Colors.white, size: 18)),
    );
  }
}
