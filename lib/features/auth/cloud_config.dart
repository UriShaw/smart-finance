import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/env.dart';
import '../../core/errors/app_error.dart';
import '../../core/security/app_logger.dart';

/// Kết nối máy chủ Supabase ngay trong app (không cần build lại):
/// lưu Project URL + publishable/anon key (khóa công khai, được RLS bảo vệ)
/// vào bộ nhớ app. KHÔNG bao giờ nhận service-role / secret key.
class CloudConfig {
  const CloudConfig._();

  static const _kUrl = 'cloud_url';
  static const _kKey = 'cloud_key';

  /// Gọi trong main() trước Supabase.initialize: dùng máy chủ đã lưu (nếu có).
  static void applySaved(SharedPreferences prefs) {
    final url = prefs.getString(_kUrl) ?? '';
    final key = prefs.getString(_kKey) ?? '';
    if (url.isNotEmpty && key.isNotEmpty) Env.useServer(url, key);
  }

  static bool hasSaved(SharedPreferences prefs) => (prefs.getString(_kUrl) ?? '').isNotEmpty;

  /// Chấp nhận: "https://abc.supabase.co", "abc.supabase.co", mã project "abc",
  /// hoặc URL có đuôi /rest/v1.
  static String normalizeUrl(String input) {
    var s = input.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    for (final tail in ['/rest/v1', '/auth/v1']) {
      if (s.endsWith(tail)) s = s.substring(0, s.length - tail.length);
    }
    if (RegExp(r'^[a-z0-9]{15,30}$').hasMatch(s)) s = '$s.supabase.co';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    return s;
  }

  static String? hostOf(String url) => Uri.tryParse(url)?.host;

  /// Khóa bí mật tuyệt đối không được đưa vào app.
  static bool looksSecret(String key) {
    final k = key.trim();
    if (k.startsWith('sb_secret_')) return true;
    // Khóa JWT kiểu cũ: phần payload chứa role service_role.
    final parts = k.split('.');
    if (parts.length == 3) {
      try {
        var p = parts[1].replaceAll('-', '+').replaceAll('_', '/');
        while (p.length % 4 != 0) {
          p += '=';
        }
        final json = utf8.decode(base64.decode(p), allowMalformed: true);
        if (json.contains('service_role')) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Kiểm tra URL + khóa bằng endpoint công khai /auth/v1/settings.
  static Future<void> verify(String url, String key) async {
    final uri = Uri.tryParse('$url/auth/v1/settings');
    if (uri == null || uri.host.isEmpty) {
      throw const AppError(AppErrorType.validation, detail: 'bad_url');
    }
    if (key.trim().isEmpty) {
      throw const AppError(AppErrorType.validation, detail: 'bad_key');
    }
    if (looksSecret(key)) {
      throw const AppError(AppErrorType.validation, detail: 'secret_key');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      req.headers.set('apikey', key.trim());
      final res = await req.close().timeout(const Duration(seconds: 15));
      await res.drain<void>();
      if (res.statusCode == 200) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw const AppError(AppErrorType.validation, detail: 'bad_key');
      }
      if (res.statusCode == 404) {
        throw const AppError(AppErrorType.validation, detail: 'bad_url');
      }
      throw AppError(AppErrorType.provider, detail: 'http_${res.statusCode}');
    } on SocketException catch (e) {
      // Không phân giải được tên miền -> thường là gõ sai URL (hoặc mất mạng).
      throw AppError(AppErrorType.network, detail: 'unreachable', cause: e);
    } on TimeoutException catch (e) {
      throw AppError(AppErrorType.network, detail: 'timeout', cause: e);
    } finally {
      client.close(force: true);
    }
  }

  /// Kiểm tra, lưu và khởi tạo kết nối. Trả về true nếu dùng được ngay,
  /// false nếu cần mở lại app để áp dụng.
  static Future<bool> connect(SharedPreferences prefs, String rawUrl, String rawKey) async {
    final url = normalizeUrl(rawUrl);
    final key = rawKey.trim();
    await verify(url, key);
    await prefs.setString(_kUrl, url);
    await prefs.setString(_kKey, key);
    return _reinit(url, key);
  }

  /// Bỏ máy chủ đã nhập trong app (quay về máy chủ lúc build, nếu có).
  static Future<bool> disconnect(SharedPreferences prefs) async {
    await prefs.remove(_kUrl);
    await prefs.remove(_kKey);
    return _reinit(Env.buildUrl, Env.buildKey);
  }

  static Future<bool> _reinit(String url, String key) async {
    try {
      if (Env.cloudReady) {
        await sb.Supabase.instance.dispose();
        Env.cloudReady = false;
      }
      Env.useServer(url, key);
      if (url.isEmpty || key.isEmpty) return true;
      await sb.Supabase.initialize(url: url, publishableKey: key, debug: false);
      Env.cloudReady = true;
      return true;
    } catch (e) {
      AppLogger.e('cloud', 'reinit failed', e);
      return false;
    }
  }
}
