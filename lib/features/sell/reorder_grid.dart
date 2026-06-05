import 'dart:async';

import 'package:flutter/material.dart';

/// A drag-to-reorder GRID whose lifted tile is positioned in *local* (content)
/// coordinates instead of an Overlay. Overlay/global-coordinate reorder widgets
/// (the built-in ReorderableListView, the reorderable_grid_view package, etc.)
/// float the dragged tile OFF the finger when an ancestor applies a scale
/// transform — which our app-wide responsive scaler does. This widget reads the
/// pointer via the GestureDetector's `localPosition` (Flutter already maps that
/// through every transform), so the lifted tile stays exactly under the finger.
///
/// Interaction: tap a tile → [onTapItem]; press-and-hold then drag → reorder,
/// with the held tile growing slightly and the others sliding to open a gap.
/// Drag near the top/bottom edge to auto-scroll.
class ReorderGrid extends StatefulWidget {
  const ReorderGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onTapItem,
    required this.onReorder,
    this.maxTileExtent = 186,
    this.childAspectRatio = 1.2,
    this.spacing = 12,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;

  /// Builds the (gesture-free) visual for the item at [index].
  final Widget Function(int index) itemBuilder;
  final void Function(int index) onTapItem;

  /// Move the item from [oldIndex] to [newIndex] (direct slot indices).
  final void Function(int oldIndex, int newIndex) onReorder;

  final double maxTileExtent;
  final double childAspectRatio;
  final double spacing;
  final EdgeInsets padding;

  @override
  State<ReorderGrid> createState() => _ReorderGridState();
}

class _ReorderGridState extends State<ReorderGrid> {
  final _scroll = ScrollController();

  // _order[slot] = original item index currently shown at that slot.
  late List<int> _order;
  int? _fromSlot; // slot the drag started at (null = not dragging)
  int? _activeSlot; // slot the dragged item currently occupies
  Offset _pointer = Offset.zero; // content-space pointer
  Offset _grab = Offset.zero; // tile-top-left → grab point
  Timer? _autoScroll;

  // Geometry, recomputed each build.
  int _cols = 1;
  double _tileW = 1;
  double _tileH = 1;
  double _viewportH = 0;

  @override
  void initState() {
    super.initState();
    _resetOrder();
  }

  void _resetOrder() =>
      _order = List<int>.generate(widget.itemCount, (i) => i);

  @override
  void didUpdateWidget(ReorderGrid old) {
    super.didUpdateWidget(old);
    // Re-sync when the parent's list changes and we're not mid-drag.
    if (_fromSlot == null && old.itemCount != widget.itemCount) _resetOrder();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  double get _stepX => _tileW + widget.spacing;
  double get _stepY => _tileH + widget.spacing;

  Offset _slotTopLeft(int slot) {
    final r = slot ~/ _cols;
    final c = slot % _cols;
    return Offset(widget.padding.left + c * _stepX,
        widget.padding.top + r * _stepY);
  }

  int _slotAt(Offset content) {
    var c = ((content.dx - widget.padding.left) / _stepX).floor();
    var r = ((content.dy - widget.padding.top) / _stepY).floor();
    if (c < 0) c = 0;
    if (c >= _cols) c = _cols - 1;
    if (r < 0) r = 0;
    final s = r * _cols + c;
    if (s < 0) return 0;
    if (s >= widget.itemCount) return widget.itemCount - 1;
    return s;
  }

  // GestureDetector localPosition is viewport-relative; add scroll for content.
  Offset _content(Offset viewportLocal) =>
      Offset(viewportLocal.dx, viewportLocal.dy + _scroll.offset);

  void _start(Offset viewportLocal) {
    final content = _content(viewportLocal);
    final slot = _slotAt(content);
    setState(() {
      _fromSlot = slot;
      _activeSlot = slot;
      _pointer = content;
      _grab = content - _slotTopLeft(slot);
    });
  }

  void _move(Offset viewportLocal) {
    final content = _content(viewportLocal);
    final center =
        content - _grab + Offset(_tileW / 2, _tileH / 2);
    final target = _slotAt(center);
    setState(() {
      _pointer = content;
      if (_activeSlot != null && target != _activeSlot) {
        final it = _order.removeAt(_activeSlot!);
        _order.insert(target, it);
        _activeSlot = target;
      }
    });
    _autoScrollCheck(viewportLocal);
  }

  void _end() {
    _autoScroll?.cancel();
    _autoScroll = null;
    final from = _fromSlot;
    final to = _activeSlot;
    setState(() {
      _fromSlot = null;
      _activeSlot = null;
    });
    if (from != null && to != null && from != to) {
      widget.onReorder(from, to);
    }
    // Parent rebuilds with the new order; either way fall back to identity.
    _resetOrder();
  }

  void _autoScrollCheck(Offset viewportLocal) {
    const edge = 72.0;
    double d = 0;
    if (viewportLocal.dy < edge) {
      d = -12;
    } else if (viewportLocal.dy > _viewportH - edge) {
      d = 12;
    }
    if (d == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final next = (_scroll.offset + d)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if (next == _scroll.offset) return;
      _scroll.jumpTo(next);
      // Keep the dragged item tracking as the content scrolls under it.
      _move(Offset(_pointer.dx, _pointer.dy - _scroll.offset + d));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _viewportH = c.maxHeight;
      final usable = c.maxWidth - widget.padding.horizontal;
      // Match SliverGridDelegateWithMaxCrossAxisExtent (the normal Sell grid):
      // ceil() packs as many columns as fit ≤ maxTileExtent, so the tile size
      // and column count match the view grid exactly.
      _cols = (usable / (widget.maxTileExtent + widget.spacing)).ceil();
      if (_cols < 1) _cols = 1;
      _tileW = (usable - widget.spacing * (_cols - 1)) / _cols;
      _tileH = _tileW / widget.childAspectRatio;

      final rows = (widget.itemCount / _cols).ceil();
      final contentH = widget.padding.top +
          widget.padding.bottom +
          rows * _tileH +
          (rows > 0 ? (rows - 1) * widget.spacing : 0);
      final dragging = _fromSlot != null;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: dragging
            ? null
            : (d) {
                final slot = _slotAt(_content(d.localPosition));
                if (slot < _order.length) widget.onTapItem(_order[slot]);
              },
        onLongPressStart: (d) => _start(d.localPosition),
        onLongPressMoveUpdate: (d) => _move(d.localPosition),
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: () {
          if (_fromSlot != null) _end();
        },
        child: SingleChildScrollView(
          controller: _scroll,
          physics: dragging
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          child: SizedBox(
            height: contentH < c.maxHeight ? c.maxHeight : contentH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int slot = 0; slot < _order.length; slot++)
                  AnimatedPositioned(
                    key: ValueKey('rg-${_order[slot]}'),
                    duration: Duration(milliseconds: dragging ? 160 : 0),
                    curve: Curves.easeOut,
                    left: _slotTopLeft(slot).dx,
                    top: _slotTopLeft(slot).dy,
                    width: _tileW,
                    height: _tileH,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (dragging && slot == _activeSlot) ? 0.0 : 1.0,
                        child: widget.itemBuilder(_order[slot]),
                      ),
                    ),
                  ),
                if (dragging && _activeSlot != null)
                  Positioned(
                    left: _pointer.dx - _grab.dx,
                    top: _pointer.dy - _grab.dy,
                    width: _tileW,
                    height: _tileH,
                    child: IgnorePointer(
                      child: Transform.scale(
                        scale: 1.08,
                        child: Material(
                          color: Colors.transparent,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.22),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6)),
                              ],
                            ),
                            child: widget.itemBuilder(_order[_activeSlot!]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// A 1-D (horizontal or vertical) drag-to-reorder strip with the same
/// scaler-proof, lift-in-place behaviour as [ReorderGrid]. Unlike the grid it
/// does NOT intercept taps — the child tiles keep their own onTap (so a Type/
/// Sub-type box can still select itself and its pencil can still open the
/// editor); only press-and-hold starts a drag.
class ReorderStrip extends StatefulWidget {
  const ReorderStrip({
    super.key,
    required this.axis,
    required this.itemCount,
    required this.itemBuilder,
    required this.onReorder,
    required this.mainExtent,
    this.crossExtent,
    this.spacing = 10,
    this.padding = EdgeInsets.zero,
  });

  final Axis axis;
  final int itemCount;
  final Widget Function(int index) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Tile size along the scroll axis (width when horizontal, height when
  /// vertical). The cross size fills the strip unless [crossExtent] is set.
  final double mainExtent;
  final double? crossExtent;
  final double spacing;
  final EdgeInsets padding;

  @override
  State<ReorderStrip> createState() => _ReorderStripState();
}

class _ReorderStripState extends State<ReorderStrip> {
  final _scroll = ScrollController();
  late List<int> _order;
  int? _fromSlot;
  int? _activeSlot;
  double _pointerMain = 0; // content-space main-axis coord
  double _grabMain = 0;
  Timer? _autoScroll;
  double _viewportMain = 0;

  bool get _h => widget.axis == Axis.horizontal;
  double get _padMainStart => _h ? widget.padding.left : widget.padding.top;
  double get _step => widget.mainExtent + widget.spacing;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() => _order = List<int>.generate(widget.itemCount, (i) => i);

  @override
  void didUpdateWidget(ReorderStrip old) {
    super.didUpdateWidget(old);
    if (_fromSlot == null && old.itemCount != widget.itemCount) _reset();
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  double _slotMain(int slot) => _padMainStart + slot * _step;

  int _slotAt(double contentMain) {
    var s = ((contentMain - _padMainStart) / _step).floor();
    if (s < 0) s = 0;
    if (s >= widget.itemCount) s = widget.itemCount - 1;
    return s;
  }

  double _contentMain(Offset vl) => (_h ? vl.dx : vl.dy) + _scroll.offset;

  void _start(Offset vl) {
    final cm = _contentMain(vl);
    final slot = _slotAt(cm);
    setState(() {
      _fromSlot = slot;
      _activeSlot = slot;
      _pointerMain = cm;
      _grabMain = cm - _slotMain(slot);
    });
  }

  void _move(Offset vl) {
    final cm = _contentMain(vl);
    final target = _slotAt(cm - _grabMain + widget.mainExtent / 2);
    setState(() {
      _pointerMain = cm;
      if (_activeSlot != null && target != _activeSlot) {
        final it = _order.removeAt(_activeSlot!);
        _order.insert(target, it);
        _activeSlot = target;
      }
    });
    _autoScrollCheck(vl);
  }

  void _end() {
    _autoScroll?.cancel();
    _autoScroll = null;
    final f = _fromSlot;
    final t = _activeSlot;
    setState(() {
      _fromSlot = null;
      _activeSlot = null;
    });
    if (f != null && t != null && f != t) widget.onReorder(f, t);
    _reset();
  }

  void _autoScrollCheck(Offset vl) {
    final m = _h ? vl.dx : vl.dy;
    const edge = 48.0;
    double d = 0;
    if (m < edge) {
      d = -10;
    } else if (m > _viewportMain - edge) {
      d = 10;
    }
    if (d == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scroll.hasClients) return;
      final next = (_scroll.offset + d)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if (next == _scroll.offset) return;
      _scroll.jumpTo(next);
      final vm = (_pointerMain - _scroll.offset);
      _move(_h ? Offset(vm, vl.dy) : Offset(vl.dx, vm));
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _viewportMain = _h ? c.maxWidth : c.maxHeight;
      final crossFull = _h ? c.maxHeight : c.maxWidth;
      final cross = widget.crossExtent ??
          (crossFull -
              (_h ? widget.padding.vertical : widget.padding.horizontal));
      final crossStart = _h ? widget.padding.top : widget.padding.left;
      final contentMain = _padMainStart +
          (_h ? widget.padding.right : widget.padding.bottom) +
          widget.itemCount * widget.mainExtent +
          (widget.itemCount > 0 ? (widget.itemCount - 1) * widget.spacing : 0);
      final dragging = _fromSlot != null;
      final proxyMain = _pointerMain - _grabMain;

      Widget slotTile(int slot) {
        final main = _slotMain(slot);
        return AnimatedPositioned(
          key: ValueKey('rs-${_order[slot]}'),
          duration: Duration(milliseconds: dragging ? 150 : 0),
          curve: Curves.easeOut,
          left: _h ? main : crossStart,
          top: _h ? crossStart : main,
          width: _h ? widget.mainExtent : cross,
          height: _h ? cross : widget.mainExtent,
          child: Opacity(
            opacity: (dragging && slot == _activeSlot) ? 0.0 : 1.0,
            child: widget.itemBuilder(_order[slot]),
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _start(d.localPosition),
        onLongPressMoveUpdate: (d) => _move(d.localPosition),
        onLongPressEnd: (_) => _end(),
        onLongPressCancel: () {
          if (_fromSlot != null) _end();
        },
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: widget.axis,
          physics: dragging ? const NeverScrollableScrollPhysics() : null,
          child: SizedBox(
            width: _h
                ? (contentMain < c.maxWidth ? c.maxWidth : contentMain)
                : c.maxWidth,
            height: _h
                ? c.maxHeight
                : (contentMain < c.maxHeight ? c.maxHeight : contentMain),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int s = 0; s < _order.length; s++) slotTile(s),
                if (dragging && _activeSlot != null)
                  Positioned(
                    left: _h ? proxyMain : crossStart,
                    top: _h ? crossStart : proxyMain,
                    width: _h ? widget.mainExtent : cross,
                    height: _h ? cross : widget.mainExtent,
                    child: IgnorePointer(
                      child: Transform.scale(
                        scale: 1.08,
                        child: Material(
                          color: Colors.transparent,
                          child: widget.itemBuilder(_order[_activeSlot!]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}
