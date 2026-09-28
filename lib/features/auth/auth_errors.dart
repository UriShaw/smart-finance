import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/errors/app_error.dart';

/// Đổi lỗi đăng nhập / kết nối máy chủ thành khóa chuỗi dễ hiểu (đã dịch).
String authErrorKey(Object e) {
  if (e is sb.AuthException) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    bool has(String s) => code.contains(s) || msg.contains(s);
    if (has('invalid_credentials') || has('invalid login')) return 'auth_invalid_login';
    if (has('email_not_confirmed') || has('not confirmed')) return 'auth_email_not_confirmed';
    if (has('user_already_exists') || has('already registered') || has('email_exists')) {
      return 'auth_user_exists';
    }
    if (has('weak_password') || has('password should')) return 'auth_weak_password';
    if (has('rate_limit') || has('rate limit') || e.statusCode == '429') {
      return 'auth_rate_limit';
    }
    if (has('otp_expired') || has('token has expired') || has('invalid token') || has('otp')) {
      return 'auth_bad_code';
    }
    if (has('signup_disabled') || has('signups not allowed')) return 'auth_signup_disabled';
    if (has('email_address_invalid') || has('invalid email') || has('validate email')) {
      return 'auth_bad_email';
    }
    if (has('provider is not enabled') || has('provider_disabled')) {
      return 'auth_provider_disabled';
    }
    return 'error_auth';
  }
  if (e is AppError) {
    switch (e.detail) {
      case 'bad_url':
        return 'server_bad_url';
      case 'bad_key':
        return 'server_bad_key';
      case 'secret_key':
        return 'server_secret_key';
      case 'unreachable':
        return 'server_unreachable';
      case 'no_server':
        return 'server_not_connected';
      case 'account_expired':
        return 'account_expired';
    }
    return 'error_${e.type.name}';
  }
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return 'error_network';
  }
  return 'error_${AppError.from(e).type.name}';
}
