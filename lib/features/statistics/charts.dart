import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class DonutSlice {
  const DonutSlice(this.value, this.color, this.label);
  final double value;
  final Color color;
  final String label;
}

/// Biểu đồ tròn rỗng - vẽ bằng CustomPainter, không cần package ngoài.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, this.center, this.size = 200});

  final List<DonutSlice> slices;
  final Widget? center;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: slices.map((s) => s.label).join(', '),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size),
              painter: _DonutPainter(
                  slices, Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            if (center != null) Padding(padding: EdgeInsets.all(size * 0.22), child: center),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.track);
  final List<DonutSlice> slices;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    const gap = 0.02;
    for (final s in slices) {
      final sweep = (s.value / total) * math.pi * 2;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = s.color;
      canvas.drawArc(
          rect, start + gap / 2, math.max(0.0, sweep - (slices.length > 1 ? gap : 0)), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices || old.track != track;
}

class BarPoint {
  const BarPoint(this.label, this.income, this.expense);
  final String label;
  final double income;
  final double expense;
}

/// Biểu đồ cột đôi thu/chi, tự co giãn theo chiều rộng.
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars({super.key, required this.points, this.height = 200});

  final List<BarPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: outline) ??
        TextStyle(fontSize: 10, color: outline);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarsPainter(points, labelStyle, outline.withValues(alpha: 0.25)),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.points, this.labelStyle, this.grid);
  final List<BarPoint> points;
  final TextStyle labelStyle;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = points.fold<double>(0, (m, p) => math.max(m, math.max(p.income, p.expense)));
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartH * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (maxV <= 0) return;
    final slot = size.width / points.length;
    final barW = math.max(1.5, math.min(14.0, slot * 0.32));
    final inc = Paint()..color = AppColors.income;
    final exp = Paint()..color = AppColors.expense;
    // Nhãn thưa để không chồng chữ trên màn nhỏ.
    final every = math.max(1, (points.length / math.max(1, size.width / 42)).ceil());

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final cx = slot * i + slot / 2;
      final hi = chartH * (p.income / maxV);
      final he = chartH * (p.expense / maxV);
      final r = Radius.circular(barW / 2);
      if (hi > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(cx - barW - 1, chartH - hi, barW, hi),
                topLeft: r, topRight: r),
            inc);
      }
      if (he > 0) {
        canvas.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTWH(cx + 1, chartH - he, barW, he),
                topLeft: r, topRight: r),
            exp);
      }
      if (i % every == 0) {
        final tp = TextPainter(
          text: TextSpan(text: p.label, style: labelStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: slot * every);
        tp.paint(canvas, Offset(cx - tp.width / 2, chartH + 3));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) =>
      old.points != points || old.labelStyle != labelStyle;
}
