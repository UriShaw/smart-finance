import 'package:flutter/foundation.dart';

/// Logger an toàn: chỉ log ở debug, không bao giờ log token/số tiền (spec E, S).
/// Truyền vào context kỹ thuật (tên bảng, id rút gọn, loại lỗi) - không dữ liệu tài chính.
class AppLogger {
  const AppLogger._();

  static void d(String tag, String message) {
    if (kReleaseMode) return;
    debugPrint('[SF][$tag] ${_redact(message)}');
  }

  static void e(String tag, String message, [Object? error]) {
    if (kReleaseMode) return;
    final err = error == null ? '' : ' | ${error.runtimeType}';
    debugPrint('[SF][$tag][ERR] ${_redact(message)}$err');
  }

  /// Rút gọn UUID để log không lộ đầy đủ id.
  static String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

  static String _redact(String s) => s
      .replaceAll(RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'), '<jwt>')
      .replaceAllMapped(RegExp(r'(access_token|refresh_token|apikey|code)=[^&\s]+'),
          (m) => '${m.group(1)}=<redacted>');
}
