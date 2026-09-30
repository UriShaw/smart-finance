import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../../logic/state/settings_controller.dart';
import 'glass.dart';

// =====================================================================
// Bộ điều khiển "Liquid Glass" (tham khảo iOS 26):
//  - LiquidSwitch: công tắc có "giọt kính" co giãn khi bấm / kéo.
//  - LiquidTile / LiquidSwitchTile / LiquidSection: danh sách cài đặt nhóm,
//    icon vuông bo tròn nhiều màu, đường kẻ thụt vào như iOS.
//  - LiquidSegmented: thanh chọn có viên kính trượt + kéo giãn.
//  - showGlassSheet / showLiquidPicker: bảng kính nổi từ dưới lên.
//  - GlassNavBar / LiquidSidebar: điều hướng có giọt kính trượt.
// =====================================================================

/// Màu icon cho từng nhóm chức năng (tươi, dễ phân biệt).
class LiquidColors {
  const LiquidColors._();
  static const purple = AppColors.seed;
  static const blue = Color(0xFF3D7BFF);
  static const cyan = Color(0xFF00B4FF);
  static const teal = Color(0xFF14B8A6);
  static const green = AppColors.income;
  static const orange = Color(0xFFFF9F43);
  static const red = AppColors.expense;
  static const pink = Color(0xFFFF4FD8);
  static const indigo = Color(0xFF5B5FFF);
  static const gray = Color(0xFF8E8EA8);
}

// ---------------------------------------------------------------------
// Viền phản quang dùng chung (vành kính sáng góc trên-trái).
// ---------------------------------------------------------------------
class GlassRimPainter extends CustomPainter {
  const GlassRimPainter({required this.radius, this.dark = false, this.strength = 1});

  final double radius;
  final bool dark;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = math.min(radius, size.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(r));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (dark ? 0.55 : 0.95) * strength),
            Colors.white.withValues(alpha: (dark ? 0.06 : 0.20) * strength),
            Colors.white.withValues(alpha: (dark ? 0.25 : 0.55) * strength),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    final sheen = Rect.fromLTWH(r * 0.7, 1.4, size.width - r * 1.4, size.height * 0.34);
    if (sheen.width > 4 && sheen.height > 2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(sheen, Radius.circular(sheen.height / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: (dark ? 0.16 : 0.45) * strength),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(sheen),
      );
    }
  }

  @override
  bool shouldRepaint(covariant GlassRimPainter old) =>
      old.radius != radius || old.dark != dark || old.strength != strength;
}

/// Viên kính (giọt) dùng làm chỉ báo mục đang chọn.
class LiquidDroplet extends StatelessWidget {
  const LiquidDroplet({super.key, this.radius = 24, this.colors});

  final double radius;

  /// null = kính trong (trắng mờ); có màu = viên gradient rực rỡ.
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colored = colors != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: colored
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors!,
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: dark ? 0.24 : 0.92),
                  Colors.white.withValues(alpha: dark ? 0.10 : 0.60),
                ],
              ),
        boxShadow: [
          BoxShadow(
            color: (colored ? colors!.first : AppColors.seed)
                .withValues(alpha: colored ? 0.38 : (dark ? 0.30 : 0.16)),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: GlassRimPainter(radius: radius, dark: dark && !colored),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// =====================================================================
// LiquidSwitch
// =====================================================================

class LiquidSwitch extends StatefulWidget {
  const LiquidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.colors = AppColors.accentGradient,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final List<Color> colors;

  static const double width = 60;
  static const double height = 32;

  @override
  State<LiquidSwitch> createState() => _LiquidSwitchState();
}

class _LiquidSwitchState extends State<LiquidSwitch> with TickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 480, damping: 22);

  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: widget.value ? 1.0 : 0.0);
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    reverseDuration: const Duration(milliseconds: 320),
  );
  bool _dragging = false;
  Timer? _settle;

  bool get _enabled => widget.onChanged != null;
  double get _travel => LiquidSwitch.width - _SwitchGeom.thumbW - _SwitchGeom.pad * 2;

  @override
  void didUpdateWidget(covariant LiquidSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_dragging) _animateTo(widget.value);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _pos.dispose();
    _press.dispose();
    super.dispose();
  }

  void _animateTo(bool on, [double velocity = 0]) {
    _pos.animateWith(SpringSimulation(_spring, _pos.value, on ? 1.0 : 0.0, velocity));
  }

  void _commit(bool on) {
    if (on != widget.value) {
      HapticFeedback.lightImpact();
      widget.onChanged?.call(on);
    }
    // Nơi gọi có thể từ chối (VD: huỷ nhập PIN) -> đưa công tắc về đúng giá trị thật.
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 650), () {
      if (mounted && !_dragging) _animateTo(widget.value);
    });
  }

  void _toggle() {
    if (!_enabled) return;
    final target = !widget.value;
    _animateTo(target, target ? 6 : -6);
    _commit(target);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget body = CustomPaint(
      size: const Size(LiquidSwitch.width, LiquidSwitch.height),
      painter: _LiquidSwitchPainter(
        pos: _pos,
        press: _press,
        colors: widget.colors,
        dark: dark,
      ),
    );
    if (_enabled) {
      body = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _press.forward(),
          onTapCancel: () => _press.reverse(),
          onTapUp: (_) {
            _press.reverse();
            _toggle();
          },
          onHorizontalDragStart: (_) {
            _dragging = true;
            _pos.stop();
            _press.forward();
          },
          onHorizontalDragUpdate: (d) {
            _pos.value =
                (_pos.value + (d.primaryDelta ?? 0) / _travel).clamp(-0.12, 1.12).toDouble();
          },
          onHorizontalDragEnd: (d) {
            _dragging = false;
            _press.reverse();
            final v = d.primaryVelocity ?? 0;
            final target = v.abs() > 250 ? v > 0 : _pos.value > 0.5;
            _animateTo(target, v / _travel);
            _commit(target);
          },
          onHorizontalDragCancel: () {
            _dragging = false;
            _press.reverse();
            _animateTo(widget.value);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: body,
          ),
        ),
      );
    } else {
      body = Opacity(
        opacity: 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: body,
        ),
      );
    }
    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      onTap: _enabled ? _toggle : null,
      child: body,
    );
  }
}

class _SwitchGeom {
  static const double pad = 3;
  static const double thumbW = 34;
  static const double thumbH = 26;
}

class _LiquidSwitchPainter extends CustomPainter {
  _LiquidSwitchPainter({
    required this.pos,
    required this.press,
    required this.colors,
    required this.dark,
  }) : super(repaint: Listenable.merge([pos, press]));

  final AnimationController pos;
  final Animation<double> press;
  final List<Color> colors;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = pos.value;
    final t = raw.clamp(0.0, 1.0).toDouble();
    final over = (raw - t).abs();
    final p = Curves.easeOut.transform(press.value.clamp(0.0, 1.0).toDouble());
    final bounds = Offset.zero & size;
    final track = RRect.fromRectAndRadius(bounds, Radius.circular(size.height / 2));

    // Rãnh tắt: xám trong suốt.
    canvas.drawRRect(
      track,
      Paint()
        ..color = dark
            ? Colors.white.withValues(alpha: 0.16)
            : const Color(0xFF787890).withValues(alpha: 0.22),
    );
    // Rãnh bật: gradient tươi, hiện dần theo vị trí.
    if (t > 0.001) {
      canvas.drawRRect(
        track,
        Paint()
          ..shader = LinearGradient(
            colors: [for (final c in colors) c.withValues(alpha: t)],
          ).createShader(bounds),
      );
    }
    // Bóng trong + vành sáng của rãnh.
    canvas.drawRRect(
      track.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
            Colors.white.withValues(alpha: dark ? 0.14 : 0.70),
          ],
        ).createShader(bounds),
    );

    // Giọt kính: giãn theo tốc độ + khi bấm; hơi dẹt khi giãn (cảm giác chất lỏng).
    final vel = pos.isAnimating ? pos.velocity.abs() : 0.0;
    final stretch = (vel * 0.018).clamp(0.0, 0.30).toDouble() + math.min(over * 1.6, 0.25);
    final w = _SwitchGeom.thumbW * (1 + 0.30 * p + stretch);
    final h = _SwitchGeom.thumbH * (1 + 0.20 * p) * (1 - stretch * 0.22);
    final travel = size.width - _SwitchGeom.thumbW - _SwitchGeom.pad * 2;
    final cx =
        _SwitchGeom.pad + _SwitchGeom.thumbW / 2 + travel * raw.clamp(-0.08, 1.08).toDouble();
    final thumbRect = Rect.fromCenter(center: Offset(cx, size.height / 2), width: w, height: h);
    final thumb = RRect.fromRectAndRadius(thumbRect, Radius.circular(h / 2));

    canvas.drawRRect(
      thumb.shift(const Offset(0, 1.6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20 * (1 - p * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
    );
    // Trắng đặc khi nghỉ -> kính trong khi đang bấm/kéo.
    canvas.drawRRect(thumb, Paint()..color = Colors.white.withValues(alpha: 1 - 0.74 * p));
    if (p > 0.01) {
      canvas.drawRRect(
        thumb.deflate(0.7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.95 * p),
              Colors.white.withValues(alpha: 0.18 * p),
              colors.last.withValues(alpha: 0.70 * p),
            ],
          ).createShader(thumbRect),
      );
      canvas.drawRRect(
        thumb.deflate(3.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.28 * p)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
    final hl = Rect.fromLTWH(thumbRect.left + w * 0.2, thumbRect.top + h * 0.12, w * 0.6, h * 0.3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, Radius.circular(hl.height / 2)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(hl),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidSwitchPainter old) =>
      old.dark != dark || old.colors != colors || old.pos != pos || old.press != press;
}

// =====================================================================
// Danh sách cài đặt kiểu nhóm
// =====================================================================

/// Icon trong ô vuông bo tròn, nền gradient (giống ứng dụng Cài đặt iOS).
class LiquidIconBadge extends StatelessWidget {
  const LiquidIconBadge({
    super.key,
    required this.icon,
    this.color = LiquidColors.purple,
    this.size = 32,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final light = hsl.withLightness((hsl.lightness + 0.13).clamp(0.0, 0.88).toDouble()).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(
        painter: GlassRimPainter(radius: size * 0.3, strength: 0.6),
        child: Icon(icon, size: size * 0.56, color: Colors.white),
      ),
    );
  }
}

class LiquidTile extends StatelessWidget {
  const LiquidTile({
    super.key,
    required this.title,
    this.icon,
    this.iconColor = LiquidColors.purple,
    this.leading,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
    this.showChevron,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final EdgeInsetsGeometry padding;
  final String title;
  final IconData? icon;
  final Color iconColor;
  final Widget? leading;
  final String? subtitle;
  final int subtitleMaxLines;

  /// Giá trị hiện tại hiển thị mờ ở bên phải (VD: "Tiếng Việt").
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;
  final bool destructive;
  final bool? showChevron;
  final bool selected;

  bool get hasLead => icon != null || leading != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    final lead = leading ?? (icon == null ? null : LiquidIconBadge(icon: icon!, color: iconColor));
    final dim = enabled ? 1.0 : 0.45;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (lead != null) ...[
              Opacity(opacity: dim, child: lead),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Opacity(
                opacity: dim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: destructive ? AppColors.expense : (selected ? scheme.primary : null),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            if (chevron) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.7 * dim)),
            ],
          ],
        ),
      ),
    );

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: enabled ? onTap : null,
        highlightColor: scheme.primary.withValues(alpha: 0.08),
        splashColor: scheme.primary.withValues(alpha: 0.10),
        child: content,
      ),
    );
  }
}

class LiquidSwitchTile extends StatelessWidget {
  const LiquidSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.iconColor = LiquidColors.purple,
    this.subtitle,
  });

  final String title;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Color iconColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return LiquidTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      enabled: onChanged != null,
      showChevron: false,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: LiquidSwitch(value: value, onChanged: onChanged),
    );
  }
}

/// Nhóm cài đặt: tiêu đề nhỏ + thẻ kính + đường kẻ thụt vào giữa các dòng.
class LiquidSection extends StatelessWidget {
  const LiquidSection({
    super.key,
    required this.children,
    this.title,
    this.footer,
    this.trailing,
  });

  final String? title;
  final String? footer;
  final Widget? trailing;
  final List<Widget> children;

  static double _indent(Widget w) {
    if (w is LiquidTile && w.hasLead) return 62;
    if (w is LiquidSwitchTile && w.icon != null) return 62;
    if (w is LiquidSelectTile && w.icon != null) return 62;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final line = dark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          )
        else
          const SizedBox(height: 14),
        GlassCard(
          padding: EdgeInsets.zero,
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 0.6, indent: _indent(children[i]), color: line),
                children[i],
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// =====================================================================
// Chọn một giá trị: dòng hiển thị giá trị -> bảng kính chọn
// =====================================================================

class LiquidOption<T> {
  const LiquidOption(this.value, this.label, {this.icon, this.leading, this.child});
  final T value;
  final String label;
  final IconData? icon;
  final Widget? leading;

  /// Nội dung tuỳ biến thay cho [label] (VD: icon danh mục + tên).
  final Widget? child;
}

class LiquidSelectTile<T> extends StatelessWidget {
  const LiquidSelectTile({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.iconColor = LiquidColors.purple,
    this.subtitle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final EdgeInsetsGeometry padding;
  final String title;
  final T value;
  final List<LiquidOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final Color iconColor;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    var current = '';
    for (final o in options) {
      if (o.value == value) current = o.label;
    }
    return LiquidTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      value: current,
      padding: padding,
      showChevron: true,
      onTap: () async {
        final picked = await showLiquidPicker<T>(
          context: context,
          title: title,
          options: options,
          selected: value,
        );
        if (picked != null) onChanged(picked.value);
      },
    );
  }
}

/// Bảng kính nổi từ dưới lên (bo góc lớn, làm mờ nền phía sau).
Future<R?> showGlassSheet<R>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<R>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (ctx) => GlassSheet(child: builder(ctx)),
  );
}

class GlassSheet extends ConsumerWidget {
  const GlassSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce = ref.watch(settingsProvider.select((s) => s.reduceEffects));
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = 32.0;
    final colors = reduce
        ? [
            dark ? const Color(0xFF1B1A36) : Colors.white,
            dark ? const Color(0xFF15142E) : const Color(0xFFF7F5FF),
          ]
        : [
            (dark ? const Color(0xFF232046) : Colors.white).withValues(alpha: dark ? 0.80 : 0.78),
            (dark ? const Color(0xFF141330) : const Color(0xFFF4F2FF))
                .withValues(alpha: dark ? 0.88 : 0.86),
          ];
    Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: CustomPaint(
        foregroundPainter: GlassRimPainter(radius: radius, dark: dark),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
    if (!reduce) {
      panel = BackdropFilter(filter: kLiquidGlassFilter, child: panel);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: panel),
    );
  }
}

/// Chọn 1 trong danh sách bằng bảng kính. Trả về null nếu người dùng đóng bảng.
Future<LiquidOption<T>?> showLiquidPicker<T>({
  required BuildContext context,
  required String title,
  required List<LiquidOption<T>> options,
  required T selected,
}) {
  return showGlassSheet<LiquidOption<T>>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
          child: Text(
            title,
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
            children: [
              for (final o in options)
                _PickerRow<T>(
                  option: o,
                  selected: o.value == selected,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({required this.option, required this.selected, required this.onTap});
  final LiquidOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: selected
                  ? Colors.white.withValues(alpha: dark ? 0.12 : 0.75)
                  : Colors.transparent,
              border: selected
                  ? Border.all(color: Colors.white.withValues(alpha: dark ? 0.18 : 0.9))
                  : null,
            ),
            child: Row(
              children: [
                if (option.leading != null) ...[
                  option.leading!,
                  const SizedBox(width: 12)
                ] else if (option.icon != null) ...[
                  Icon(option.icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: DefaultTextStyle.merge(
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    ),
                    child: option.child ?? Text(option.label),
                  ),
                ),
                if (selected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: AppColors.accentGradient),
                    ),
                    child: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// LiquidSegmented: thay SegmentedButton, cùng tên tham số để đổi dễ.
// =====================================================================

class LiquidSegmented<T> extends StatelessWidget {
  const LiquidSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.showSelectedIcon = false,
    this.height = 42,
    this.segmentWidth,
    this.colors = AppColors.accentGradient,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final ValueChanged<Set<T>> onSelectionChanged;

  /// Giữ để tương thích với SegmentedButton (không dùng).
  final bool showSelectedIcon;
  final double height;
  final double? segmentWidth;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    var idx = 0;
    for (var i = 0; i < segments.length; i++) {
      if (selected.contains(segments[i].value)) idx = i;
    }
    return LayoutBuilder(builder: (context, c) {
      final segW = segmentWidth ?? (c.maxWidth.isFinite ? c.maxWidth / segments.length : 88.0);
      final totalW = segW * segments.length;
      final r = height / 2;
      return SizedBox(
        width: totalW,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            color:
                dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.50),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.12 : 0.85)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(end: idx.toDouble()),
                duration: const Duration(milliseconds: 460),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) {
                  final frac = v - v.floorToDouble();
                  final stretch = math.sin(frac * math.pi) * 0.22;
                  final baseW = segW - 6;
                  final w = baseW * (1 + stretch);
                  return Positioned(
                    left: 3 + v * segW - (w - baseW) / 2,
                    top: 3,
                    bottom: 3,
                    width: w,
                    child: LiquidDroplet(radius: r - 3, colors: colors),
                  );
                },
              ),
              Row(
                children: [
                  for (var i = 0; i < segments.length; i++)
                    SizedBox(
                      width: segW,
                      height: height,
                      child: _SegmentButton<T>(
                        segment: segments[i],
                        selected: i == idx,
                        onTap: () {
                          if (i == idx) return;
                          HapticFeedback.selectionClick();
                          onSelectionChanged({segments[i].value});
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({required this.segment, required this.selected, required this.onTap});
  final ButtonSegment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: segment.enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14,
                  ),
                  child: IconTheme.merge(
                    data: IconThemeData(color: color, size: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (segment.icon != null) ...[
                          segment.icon!,
                          if (segment.label != null) const SizedBox(width: 6),
                        ],
                        if (segment.label != null) segment.label!,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Điều hướng: thanh dưới (điện thoại) + thanh bên (máy tính/tablet)
// =====================================================================

class GlassNavItem {
  const GlassNavItem({required this.icon, required this.selectedIcon, required this.label});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Icon mục điều hướng: đang chọn thì trắng (nằm trên giọt kính xanh).
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.item, required this.selected});
  final GlassNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: selected ? 1.08 : 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          selected ? item.selectedIcon : item.icon,
          key: ValueKey(selected),
          size: 24,
          color: selected ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Giọt kính xanh trượt ngang giữa các vị trí, kéo giãn khi di chuyển (cảm giác chất lỏng).
class _SlidingDroplet extends StatelessWidget {
  const _SlidingDroplet({
    required this.index,
    required this.slot,
    required this.size,
    this.vertical = false,
    this.offset = Offset.zero,
  });

  final int index;

  /// Kích thước mỗi ô (ngang: chiều rộng; dọc: chiều cao).
  final double slot;
  final Size size;
  final bool vertical;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: index.toDouble()),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final frac = v - v.floorToDouble();
        final k = 1 + math.sin(frac * math.pi) * 0.45;
        if (vertical) {
          final h = size.height * k;
          return Positioned(
            left: offset.dx,
            width: size.width,
            top: offset.dy + v * slot + (slot - size.height) / 2 - (h - size.height) / 2,
            height: h,
            child: LiquidDroplet(radius: size.width / 2, colors: AppColors.accentGradient),
          );
        }
        final w = size.width * k;
        return Positioned(
          top: offset.dy,
          height: size.height,
          left: offset.dx + v * slot + (slot - size.width) / 2 - (w - size.width) / 2,
          width: w,
          child: LiquidDroplet(radius: size.height / 2, colors: AppColors.accentGradient),
        );
      },
    );
  }
}

/// Thanh điều hướng kính nổi (điện thoại): giọt kính xanh trượt sau icon, nhãn xanh bên dưới.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: GlassCard(
        blur: true,
        radius: 32,
        opacity: 1.1,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: SizedBox(
          height: 58,
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth / items.length;
            return Stack(
              children: [
                _SlidingDroplet(
                  index: index,
                  slot: w,
                  size: const Size(58, 32),
                  offset: const Offset(0, 2),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      SizedBox(
                        width: w,
                        child: Semantics(
                          selected: i == index,
                          button: true,
                          label: items[i].label,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (i != index) HapticFeedback.selectionClick();
                              onSelect(i);
                            },
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: Center(
                                    child: _NavIcon(item: items[i], selected: i == index),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 220),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                        color:
                                            i == index ? scheme.primary : scheme.onSurfaceVariant,
                                      ),
                                      child: Text(items[i].label, maxLines: 1),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Thanh bên kính (Windows / tablet): giọt kính xanh trượt dọc.
class LiquidSidebar extends StatelessWidget {
  const LiquidSidebar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    this.extended = false,
    this.header,
    this.footer,
  });

  final List<GlassNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final bool extended;
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemH = extended ? 50.0 : 66.0;
    final width = extended ? 220.0 : 84.0;
    return GlassCard(
      blur: true,
      radius: 30,
      opacity: 1.1,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            if (header != null) header!,
            Expanded(
              child: SingleChildScrollView(
                child: Stack(
                  children: [
                    if (extended)
                      _SlidingDroplet(
                        index: index,
                        slot: itemH,
                        size: Size(width, itemH - 6),
                        vertical: true,
                      )
                    else
                      _SlidingDroplet(
                        index: index,
                        slot: itemH,
                        size: const Size(52, 32),
                        vertical: true,
                        offset: Offset((width - 52) / 2, -9),
                      ),
                    Column(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          SizedBox(
                            height: itemH,
                            child: Semantics(
                              selected: i == index,
                              button: true,
                              label: items[i].label,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => onSelect(i),
                                  child: extended
                                      ? Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          child: Row(
                                            children: [
                                              _NavIcon(item: items[i], selected: i == index),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Text(
                                                  items[i].label,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontWeight: i == index
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                    color: i == index
                                                        ? Colors.white
                                                        : scheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              height: 32,
                                              child: Center(
                                                child:
                                                    _NavIcon(item: items[i], selected: i == index),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 2),
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  items[i].label,
                                                  maxLines: 1,
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: i == index
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                    color: i == index
                                                        ? scheme.primary
                                                        : scheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

/// Chip lọc kiểu kính: chọn = viên xanh gradient chữ trắng; không chọn = kính trắng viền mảnh.
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.expand = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: selected ? const LinearGradient(colors: AppColors.accentGradient) : null,
              color: selected
                  ? null
                  : (dark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.75)),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.5)
                    : (dark ? Colors.white.withValues(alpha: 0.14) : AppColors.border),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút tròn kính (menu, đóng, tác vụ nhanh trên thanh tiêu đề).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: size,
      height: size,
      child: GlassCard(
        blur: true,
        radius: size / 2,
        padding: EdgeInsets.zero,
        onTap: onPressed,
        child: Center(child: Icon(icon, size: size * 0.5)),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
