import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Một tài khoản đã đăng nhập trên máy này (để chuyển nhanh như Gmail).
class SavedAccount {
  const SavedAccount({
    required this.userId,
    required this.refreshToken,
    this.email,
    this.name,
    this.avatarUrl,
    required this.lastUsed,
  });

  final String userId;

  /// Refresh token của phiên Supabase — dùng setSession để vào lại không cần mật khẩu.
  /// Lưu cùng chỗ và cùng mức bảo vệ như phiên Supabase mặc định (SharedPreferences).
  final String refreshToken;
  final String? email;
  final String? name;
  final String? avatarUrl;
  final DateTime lastUsed;

  String get label => (name ?? '').trim().isNotEmpty ? name!.trim() : (email ?? userId);

  Map<String, Object?> toJson() => {
        'userId': userId,
        'refreshToken': refreshToken,
        'email': email,
        'name': name,
        'avatarUrl': avatarUrl,
        'lastUsed': lastUsed.millisecondsSinceEpoch,
      };

  static SavedAccount? fromJson(Object? o) {
    if (o is! Map) return null;
    final id = o['userId'], token = o['refreshToken'];
    if (id is! String || token is! String || id.isEmpty || token.isEmpty) return null;
    return SavedAccount(
      userId: id,
      refreshToken: token,
      email: o['email'] as String?,
      name: o['name'] as String?,
      avatarUrl: o['avatarUrl'] as String?,
      lastUsed: DateTime.fromMillisecondsSinceEpoch((o['lastUsed'] as int?) ?? 0),
    );
  }
}

/// Danh sách tài khoản đã đăng nhập trên máy (mới dùng gần nhất trước).
class AccountVault {
  AccountVault([Future<SharedPreferences> Function()? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance;

  static const _key = 'sf_saved_accounts_v1';
  final Future<SharedPreferences> Function() _prefs;

  Future<List<SavedAccount>> list() async {
    final raw = (await _prefs()).getString(_key);
    if (raw == null) return const [];
    try {
      final out = (jsonDecode(raw) as List)
          .map(SavedAccount.fromJson)
          .whereType<SavedAccount>()
          .toList()
        ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<SavedAccount> accounts) async {
    await (await _prefs()).setString(_key, jsonEncode([for (final a in accounts) a.toJson()]));
  }

  /// Thêm hoặc cập nhật (refresh token đổi sau mỗi lần làm mới phiên).
  Future<void> save(SavedAccount a) async {
    final all = [...await list()]..removeWhere((x) => x.userId == a.userId);
    await _write([a, ...all]);
  }

  Future<void> remove(String userId) async {
    final all = [...await list()]..removeWhere((x) => x.userId == userId);
    await _write(all);
  }

  Future<SavedAccount?> find(String userId) async {
    for (final a in await list()) {
      if (a.userId == userId) return a;
    }
    return null;
  }
}
