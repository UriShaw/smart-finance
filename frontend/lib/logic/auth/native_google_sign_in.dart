import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/env.dart';

/// Đăng nhập Google kiểu gốc Android: bảng chọn tài khoản của hệ thống trượt lên ngay
/// trong app ("Tiếp tục tới Smart Finance"), không mở trình duyệt với tên miền Supabase.
/// Google trả ID token (audience = Web client) -> Supabase đổi thành phiên đăng nhập.
class NativeGoogleSignIn {
  const NativeGoogleSignIn._();

  static bool get supported => Platform.isAndroid && Env.googleWebClientId.isNotEmpty;

  static Future<void>? _init;

  /// true = đã đăng nhập, false = người dùng tự huỷ.
  /// Ném lỗi khi không dùng được (chưa tạo client Android / SHA-1 trên Google Cloud,
  /// Supabase từ chối token...) -> nơi gọi chuyển sang đăng nhập qua trình duyệt.
  static Future<bool> signIn(sb.SupabaseClient client) async {
    final g = GoogleSignIn.instance;
    await (_init ??= g.initialize(serverClientId: Env.googleWebClientId));
    // Bỏ lựa chọn lần trước để lần nào cũng hiện bảng chọn (dùng nhiều tài khoản).
    try {
      await g.signOut();
    } catch (_) {}

    final GoogleSignInAccount account;
    try {
      account = await g.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return false;
      }
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw StateError('google_no_id_token');
    await client.auth.signInWithIdToken(provider: sb.OAuthProvider.google, idToken: idToken);
    return true;
  }

  /// Mã lỗi ngắn để người dùng chụp màn hình gửi lại (không chứa token).
  static String describe(Object e) {
    if (e is GoogleSignInException) {
      final d = e.description;
      return 'google/${e.code.name}${d == null || d.isEmpty ? '' : ': $d'}';
    }
    if (e is sb.AuthException) return 'supabase/${e.statusCode ?? '-'}: ${e.message}';
    return '${e.runtimeType}: $e';
  }
}
