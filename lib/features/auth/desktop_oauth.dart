import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/errors/app_error.dart';

/// Google OAuth cho Windows/macOS/Linux bằng loopback redirect + PKCE:
/// mở trình duyệt -> Google -> Supabase -> http://localhost:PORT/auth-callback?code=...
/// -> đổi code lấy session. Cần thêm redirect URL này vào Supabase Auth.
class DesktopOAuth {
  const DesktopOAuth._();

  static Future<void> signInWithGoogle(sb.SupabaseClient client) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, Env.oauthDesktopPort);
    } catch (e) {
      throw AppError(AppErrorType.auth, detail: 'port_${Env.oauthDesktopPort}_busy', cause: e);
    }
    try {
      final res = await client.auth.getOAuthSignInUrl(
        provider: sb.OAuthProvider.google,
        redirectTo: Env.desktopRedirect,
        queryParams: const {'prompt': 'select_account'},
      );
      final launched = await launchUrl(
        Uri.parse(res.url.toString()),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const AppError(AppErrorType.provider, detail: 'browser');
      }
      final req = await server
          .firstWhere((r) => r.uri.path == '/auth-callback')
          .timeout(const Duration(minutes: 3));
      final code = req.uri.queryParameters['code'];
      final ok = code != null && code.isNotEmpty;
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_page(ok));
      await req.response.close();
      if (!ok) {
        throw AppError(AppErrorType.auth, detail: req.uri.queryParameters['error'] ?? 'no_code');
      }
      await client.auth.exchangeCodeForSession(code);
    } on TimeoutException {
      throw const AppError(AppErrorType.auth, detail: 'timeout');
    } finally {
      await server.close(force: true);
    }
  }

  static String _page(bool ok) => '''
<!doctype html><html><head><meta charset="utf-8"><title>Smart Finance</title>
<style>body{font-family:system-ui,Segoe UI,sans-serif;display:flex;height:100vh;align-items:center;justify-content:center;background:#eef2ff;color:#1e293b}
.card{background:#fff;padding:32px 40px;border-radius:24px;box-shadow:0 10px 30px rgba(0,0,0,.08);text-align:center}</style></head>
<body><div class="card"><h2>${ok ? '✅ Đăng nhập thành công' : '❌ Đăng nhập thất bại'}</h2>
<p>${ok ? 'Bạn có thể đóng tab này và quay lại Smart Finance.' : 'Vui lòng quay lại ứng dụng và thử lại.'}</p></div></body></html>
''';
}
