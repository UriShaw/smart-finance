import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../../logic/state/settings_controller.dart';

// =====================================================================
// Nền "chất lỏng": các vệt màu tươi trôi chậm (RepaintBoundary riêng,
// không làm vẽ lại nội dung phía trên).
// =====================================================================

class GlassBackground extends ConsumerStatefulWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends ConsumerState<GlassBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 36));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = ref.watch(settingsProvider.select((s) => s.reduceEffects));
    final animate = ref.watch(settingsProvider.select((s) => s.animatedBackground)) &&
        !reduce &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _LiquidPainter(
                animation: _c,
                dark: dark,
                intensity: reduce ? 0.55 : 1,
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter({required this.animation, required this.dark, required this.intensity})
      : super(repaint: animation);

  final Animation<double> animation;
  final bool dark;
  final double intensity;

  // (tâm x, tâm y, biên độ x, biên độ y, tần số, pha, bán kính tương đối)
  static const _paths = [
    [0.15, 0.10, 0.18, 0.10, 1.0, 0.0, 0.62],
    [0.90, 0.20, 0.12, 0.16, 1.0, 1.7, 0.55],
    [0.75, 0.85, 0.16, 0.10, 1.0, 3.1, 0.66],
    [0.10, 0.80, 0.12, 0.14, 2.0, 4.4, 0.50],
    [0.50, 0.45, 0.22, 0.18, 1.0, 5.6, 0.45],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = dark ? AppColors.darkBase : AppColors.lightBase);
    final t = animation.value * 2 * math.pi;
    final side = math.max(size.width, size.height);
    final alpha = (dark ? 0.30 : 0.50) * intensity;
    for (var i = 0; i < _paths.length; i++) {
      final p = _paths[i];
      final cx = size.width * (p[0] + p[2] * math.sin(t * p[4] + p[5]));
      final cy = size.height * (p[1] + p[3] * math.cos(t * p[4] + p[5] * 0.7));
      final r = side * p[6];
      final color = AppColors.blobs[i % AppColors.blobs.length];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.35),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
    // Ánh sáng chéo nhẹ tạo cảm giác bề mặt bóng.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.03 : 0.35),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: dark ? 0.02 : 0.10),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter old) =>
      old.dark != dark || old.intensity != intensity;
}

/// Bộ lọc kính lỏng: làm mờ + tăng bão hoà màu phía sau (giống vật liệu iOS 26).
final ImageFilter kLiquidGlassFilter = ImageFilter.compose(
  outer: const ColorFilter.matrix(<double>[
    1.3937, -0.3576, -0.0361, 0, 0, //
    -0.1063, 1.1424, -0.0361, 0, 0, //
    -0.1063, -0.3576, 1.4639, 0, 0, //
    0, 0, 0, 1, 0, //
  ]),
  inner: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
);

// =====================================================================
// Bề mặt kính: nền trong suốt dạng gradient + viền phản quang + bóng mềm
// + (tùy chọn) làm mờ phía sau. Có hiệu ứng nhấn thu nhỏ mượt.
// =====================================================================

class GlassCard extends ConsumerStatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.radius = AppRadius.md,
    this.onTap,
    this.tint,
    this.blur,
    this.opacity = 1,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? tint;

  /// null = theo cài đặt "làm mờ mọi thẻ"; true = luôn làm mờ (thanh điều hướng, thẻ chính).
  final bool? blur;

  /// Hệ số độ đậm của lớp kính (0..1.5).
  final double opacity;

  @override
  ConsumerState<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends ConsumerState<GlassCard> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null || _pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = ref.watch(settingsProvider.select((s) => s.reduceEffects));
    final blurAll = ref.watch(settingsProvider.select((s) => s.glassBlurAll));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final useBlur = !reduce && (widget.blur ?? blurAll);
    final br = BorderRadius.circular(widget.radius);
    final k = widget.opacity;

    final fill = reduce
        ? [
            (dark ? const Color(0xFF15203A) : Colors.white).withValues(alpha: 0.96),
            (dark ? const Color(0xFF15203A) : Colors.white).withValues(alpha: 0.92),
          ]
        : [
            Colors.white.withValues(alpha: ((dark ? 0.12 : 0.86) * k).clamp(0.0, 1.0).toDouble()),
            Colors.white.withValues(alpha: ((dark ? 0.05 : 0.62) * k).clamp(0.0, 1.0).toDouble()),
          ];

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: fill,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: widget.tint == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.tint!.withValues(alpha: dark ? 0.28 : 0.22),
                    widget.tint!.withValues(alpha: 0.06),
                  ],
                ),
        ),
        child: CustomPaint(
          foregroundPainter: reduce ? null : _GlassEdgePainter(radius: widget.radius, dark: dark),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: br,
              onTap: widget.onTap,
              onHighlightChanged: _setPressed,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );

    if (useBlur) {
      surface = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: kLiquidGlassFilter,
          child: surface,
        ),
      );
    } else {
      surface = ClipRRect(borderRadius: br, child: surface);
    }

    return AnimatedScale(
      scale: _pressed ? 0.975 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          boxShadow: reduce
              ? null
              : [
                  BoxShadow(
                    color: (widget.tint ?? AppColors.primary).withValues(alpha: dark ? 0.22 : 0.08),
                    blurRadius: 28,
                    spreadRadius: -6,
                    offset: const Offset(0, 14),
                  ),
                ],
        ),
        child: surface,
      ),
    );
  }
}

/// Viền phản quang: sáng ở góc trên-trái, mờ dần xuống dưới-phải + vệt sáng mép trên.
class _GlassEdgePainter extends CustomPainter {
  _GlassEdgePainter({required this.radius, required this.dark});

  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(radius));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.45 : 0.95),
          Colors.white.withValues(alpha: dark ? 0.06 : 0.25),
          Colors.white.withValues(alpha: dark ? 0.22 : 0.60),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, stroke);

    // Vệt sáng mép trên (specular).
    final sheenRect = Rect.fromLTWH(radius * 0.6, 1.2, size.width - radius * 1.2, 1.4);
    if (sheenRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(sheenRect, const Radius.circular(1)),
        Paint()
          ..shader = LinearGradient(colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: dark ? 0.35 : 0.9),
            Colors.white.withValues(alpha: 0),
          ]).createShader(sheenRect),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassEdgePainter old) => old.radius != radius || old.dark != dark;
}

/// Thẻ kính màu gradient rực rỡ (thẻ số dư, thẻ giới thiệu).
class GradientGlassCard extends ConsumerWidget {
  const GradientGlassCard({
    super.key,
    required this.child,
    this.colors = AppColors.heroGradient,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.radius = AppRadius.lg,
    this.onTap,
  });

  final Widget child;
  final List<Color> colors;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reduce = ref.watch(settingsProvider.select((s) => s.reduceEffects));
    final br = BorderRadius.circular(radius);
    final body = Stack(
      children: [
        // Hai quầng sáng mềm tạo chiều sâu.
        Positioned(
          right: -40,
          top: -60,
          child: _Glow(color: Colors.white.withValues(alpha: 0.28), size: 180),
        ),
        Positioned(
          left: -50,
          bottom: -70,
          child: _Glow(color: Colors.white.withValues(alpha: 0.16), size: 200),
        ),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: br,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: reduce
            ? null
            : [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.40),
                  blurRadius: 32,
                  spreadRadius: -8,
                  offset: const Offset(0, 18),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [for (final c in colors) c.withValues(alpha: 0.92)],
            ),
          ),
          child: CustomPaint(
            foregroundPainter: _GlassEdgePainter(radius: radius, dark: false),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

/// Icon tròn nền gradient tươi (nút tắt nhanh, danh mục).
class GradientIcon extends StatelessWidget {
  const GradientIcon({
    super.key,
    required this.icon,
    required this.colors,
    this.size = 44,
  });

  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.5),
    );
  }
}

/// Số tiền "chạy" mượt khi thay đổi.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  final int value;
  final String Function(int) format;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
        format(v.round()),
        maxLines: 1,
        style: style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
