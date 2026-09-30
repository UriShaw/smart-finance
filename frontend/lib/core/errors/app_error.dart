import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Phân loại lỗi theo spec S.
enum AppErrorType {
  validation,
  auth,
  network,
  database,
  storage,
  sync,
  provider,
  unexpected,
}

class AppError implements Exception {
  const AppError(this.type, {this.detail, this.cause});

  final AppErrorType type;

  /// Chi tiết kỹ thuật cho log dev - KHÔNG chứa token/số tiền.
  final String? detail;
  final Object? cause;

  /// Khóa localization cho thông báo thân thiện.
  String get messageKey => 'error_${type.name}';

  static AppError from(Object e) {
    if (e is AppError) return e;
    if (e is SocketException ||
        e is TimeoutException ||
        e is HttpException ||
        e is HandshakeException) {
      return AppError(AppErrorType.network, detail: e.runtimeType.toString());
    }
    if (e is sb.AuthException) {
      return AppError(AppErrorType.auth, detail: e.statusCode, cause: e);
    }
    if (e is sb.StorageException) {
      return AppError(AppErrorType.storage, detail: e.statusCode, cause: e);
    }
    if (e is sb.PostgrestException) {
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('socket')) {
        return AppError(AppErrorType.network, detail: e.code, cause: e);
      }
      return AppError(AppErrorType.database, detail: e.code, cause: e);
    }
    if (e is DatabaseException) {
      return AppError(AppErrorType.database, detail: 'sqlite', cause: e);
    }
    if (e is FormatException) {
      return AppError(AppErrorType.validation, detail: e.message, cause: e);
    }
    final s = e.toString().toLowerCase();
    if (s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection refused') ||
        s.contains('clientexception')) {
      return AppError(AppErrorType.network, detail: 'client', cause: e);
    }
    return AppError(AppErrorType.unexpected, detail: e.runtimeType.toString(), cause: e);
  }

  @override
  String toString() => 'AppError(${type.name}${detail == null ? '' : ': $detail'})';
}
