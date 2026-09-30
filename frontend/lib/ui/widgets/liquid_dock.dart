import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';

/// Một ô trên Dock.
class DockEntry {
  const DockEntry({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Trang đang mở -> chấm sáng bên dưới (như app đang chạy trên macOS).
  final bool selected;
}

/// Thanh Dock kiểu macOS cho máy tính: kính mờ trong suốt nổi giữa đáy màn hình,
/// icon phóng to khi rê chuột (icon bên cạnh to theo), rê vào hiện tên.
class LiquidDock extends StatefulWidget {
  const LiquidDock({super.key, required this.entries, this.dividerAfter});

  final List<DockEntry> entries;

  /// Vạch ngăn sau ô thứ [dividerAfter] (tách trang chính với chức năng phụ).
  final int? dividerAfter;

  @override
  State<LiquidDock> createState() => _LiquidDockState();
}

class _LiquidDockState extends State<LiquidDock> {
  static const _icon = 46.0;
  static const _slot = 60.0;
  static const _divider = 20.0;
  static const _padX = 10.0;
  static const _glassH = 70.0;
  static const _maxScale = 1.45;

  /// Vị trí chuột theo trục ngang trong Dock; null = chuột không ở trên Dock.
  double? _hoverX;

  double _center(int i) {
    final d = widget.dividerAfter;
    final shift = d != null && i > d ? _divider : 0.0;
    return _padX + i * _slot + _slot / 2 + shift;
  }

  double _scaleFor(int i, bool animate) {
    final x = _hoverX;
    if (x == null || !animate) return 1;
    final dist = (x - _center(i)).abs();
    const reach = _slot * 2.2;
    if (dist >= reach) return 1;
    // Đường cong cos: icon dưới chuột to nhất, giảm mượt sang hai bên.
    final t = (math.cos(dist / reach * math.pi) + 1) / 2;
    return 1 + (_maxScale - 1) * t;
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final hasDivider = widget.dividerAfter != null;
    final width = _padX * 2 + entries.length * _slot + (hasDivider ? _divider : 0);
    final animate = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final scheme = Theme.of(context).colorScheme;

    final tiles = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      tiles.add(_DockTile(
        entry: entries[i],
        size: _icon,
        slot: _slot,
        scale: _scaleFor(i, animate),
      ));
      if (i == widget.dividerAfter) {
        tiles.add(SizedBox(
          width: _divider,
          height: _icon,
          child: Center(
            child: Container(
              width: 1.2,
              height: _icon * 0.7,
              color: scheme.onSurface.withValues(alpha: 0.18),
            ),
          ),
        ));
      }
    }

    return MouseRegion(
      onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
      onExit: (_) => setState(() => _hoverX = null),
      child: SizedBox(
        width: width,
        // Chừa khoảng phía trên để icon phóng to không bị cắt.
        height: _glassH + _icon * (_maxScale - 1) + 6,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: width,
              height: _glassH,
              child: const GlassCard(
                blur: true,
                radius: 24,
                opacity: 0.85,
                padding: EdgeInsets.zero,
                child: SizedBox.expand(),
              ),
            ),
            Positioned(
              left: _padX,
              right: _padX,
              bottom: 7,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: tiles),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockTile extends StatelessWidget {
  const _DockTile({
    required this.entry,
    required this.size,
    required this.slot,
    required this.scale,
  });

  final DockEntry entry;
  final double size;
  final double slot;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = entry.color;
    final dot = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    return SizedBox(
      width: slot,
      child: Tooltip(
        message: entry.label,
        preferBelow: false,
        verticalOffset: size * 0.95,
        waitDuration: const Duration(milliseconds: 250),
        child: Semantics(
          button: true,
          selected: entry.selected,
          label: entry.label,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: entry.onTap,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: scale,
                    alignment: Alignment.bottomCenter,
                    duration: const Duration(milliseconds: 110),
                    curve: Curves.easeOut,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(size * 0.27),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color.lerp(c, Colors.white, 0.28)!,
                            c,
                            Color.lerp(c, Colors.black, 0.18)!,
                          ],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: c.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(entry.icon, color: Colors.white, size: size * 0.52),
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: entry.selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
