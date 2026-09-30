import 'package:flutter/material.dart';

/// Logo chuông "ting ting" của app cũ (vẽ bằng code, không cần file ảnh).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
              blurRadius: size * 0.3,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: CustomPaint(painter: _LogoPainter()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 100;
    canvas.save();
    canvas.scale(k, k);

    final disc = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF60A5FA), Color(0xFF3B82F6), Color(0xFF2563EB)],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    canvas.drawCircle(const Offset(50, 50), 50, disc);

    final white = Paint()..color = Colors.white;
    // Thân chuông.
    final dome = Path()
      ..moveTo(50, 23)
      ..cubicTo(40.61, 23, 33, 30.61, 33, 40)
      ..lineTo(33, 52)
      ..lineTo(67, 52)
      ..lineTo(67, 40)
      ..cubicTo(67, 30.61, 59.39, 23, 50, 23)
      ..close();
    canvas.drawPath(dome, white);
    // Vành chuông.
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(25, 56, 50, 8), const Radius.circular(4)),
      white,
    );
    // Quả lắc.
    canvas.drawArc(const Rect.fromLTWH(44, 64, 12, 12), 3.14159, 3.14159, true, white);
    // Chấm thông báo xanh lá.
    canvas.drawCircle(const Offset(66, 30), 6, Paint()..color = const Color(0xFF10B981));
    // Hai vệt âm thanh.
    final wave = Paint()
      ..color = const Color(0xFF93C5FD)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(28, 83)
          ..cubicTo(31, 83, 33, 81, 35, 80),
        wave);
    canvas.drawPath(
        Path()
          ..moveTo(65, 83)
          ..cubicTo(68, 83, 70, 81, 72, 80),
        wave);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}
