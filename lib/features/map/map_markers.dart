import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Vẽ điểm đánh dấu kiểu Google Photos: ảnh vuông bo góc viền trắng, góc có số
/// lượng khi là nhóm. Không có ảnh -> ô màu danh mục + biểu tượng.
/// Trả về PNG để dùng chung cho mọi thư viện bản đồ (OSM hiện Image.memory,
/// Google Maps dùng BitmapDescriptor.bytes).
class MarkerIcons {
  const MarkerIcons._();

  /// Kích thước logic của cả biểu tượng (gồm chỗ cho số đếm).
  static const double size = 60;

  static const _box = Rect.fromLTWH(2, 8, 50, 50);
  static const _badgeRadius = 10.0;

  static Future<Uint8List> render({
    ui.Image? photo,
    required Color color,
    required int count,
    IconData icon = Icons.receipt_long_rounded,
    required double dpr,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);

    final outer = RRect.fromRectAndRadius(_box, const Radius.circular(12));
    canvas.drawShadow(Path()..addRRect(outer), Colors.black, 3, false);
    canvas.drawRRect(outer, Paint()..color = Colors.white);
    final inner = outer.deflate(3);
    if (photo != null) {
      canvas.save();
      canvas.clipRRect(inner);
      paintImage(
        canvas: canvas,
        rect: inner.outerRect,
        image: photo,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawRRect(inner, Paint()..color = color);
      _text(
          canvas,
          String.fromCharCode(icon.codePoint),
          inner.center,
          TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 24,
            color: Colors.white,
          ));
    }

    if (count > 1) {
      final c = Offset(_box.right - 2, _box.top + 2);
      canvas.drawCircle(c, _badgeRadius + 1.5, Paint()..color = Colors.white);
      canvas.drawCircle(c, _badgeRadius, Paint()..color = const Color(0xFF1A73E8));
      _text(
          canvas,
          count > 99 ? '99+' : '$count',
          c,
          TextStyle(
            fontSize: count > 99 ? 8.5 : 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ));
    }

    final px = (size * dpr).ceil();
    final image = await recorder.endRecording().toImage(px, px);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static void _text(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    tp.dispose();
  }

  /// Giải mã ảnh (đã thu nhỏ còn [px] điểm ảnh) để vẽ lên biểu tượng.
  /// Lỗi / quá 15 giây -> null (vẽ ô màu thay ảnh).
  static Future<ui.Image?> load(ImageProvider provider, int px) {
    final completer = Completer<ui.Image?>();
    final stream = ResizeImage(provider, width: px).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(ui.Image? img) {
      if (completer.isCompleted) {
        img?.dispose(); // đã hết giờ chờ
      } else {
        completer.complete(img);
      }
      stream.removeListener(listener);
    }

    listener = ImageStreamListener(
      (info, _) {
        final img = info.image.clone();
        info.dispose();
        finish(img);
      },
      onError: (_, __) => finish(null),
    );
    stream.addListener(listener);
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () {
      stream.removeListener(listener);
      return null;
    });
  }
}
