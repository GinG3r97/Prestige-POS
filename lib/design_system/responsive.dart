import 'package:flutter/widgets.dart';

/// Width for a master list / side panel that adapts across iPad sizes.
///
/// Returns [fraction] of the current screen width, clamped to [min]..[max].
/// On an iPad mini (≈1133pt landscape) panels shrink toward [min]; on an
/// iPad Pro (≈1366pt) they cap at [max]. Also keeps panels sane in
/// split-view multitasking, where the app may get far less width.
double panelWidth(
  BuildContext context, {
  double fraction = 0.30,
  double min = 280,
  double max = 380,
}) {
  final w = MediaQuery.sizeOf(context).width;
  return (w * fraction).clamp(min, max);
}
