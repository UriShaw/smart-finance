import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../data/repositories/bank_message_repository.dart';

/// Số dư ngân hàng dùng chung giữa các máy qua user_metadata của Supabase (không cần bảng mới).
///
/// Điện thoại (có thông báo gốc) ghi lên; máy không nhận thông báo (Windows) đọc về để hiện
/// thẻ "Số dư tài khoản". Chỉ gửi tên ngân hàng, số cuối tài khoản, số dư và thời điểm —
/// nội dung thông báo gốc vẫn chỉ nằm trên điện thoại.
class BankBalanceCloud {
  const BankBalanceCloud._();

  static const key = 'bank_balances';

  static List<AccountBalance> fromMetadata(Map<String, dynamic>? meta) {
    final raw = meta?[key];
    if (raw is! List) return const [];
    final out = <AccountBalance>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final balance = e['balance'];
      final at = DateTime.tryParse('${e['updated_at']}');
      if (balance is! num || at == null) continue;
      out.add(AccountBalance(
        bank: '${e['bank'] ?? ''}',
        account: '${e['account'] ?? ''}',
        balance: balance.toInt(),
        updatedAt: at.toLocal(),
        fromNotification: e['exact'] != false,
      ));
    }
    return out;
  }

  static List<Map<String, Object>> toMetadata(List<AccountBalance> list) => [
        for (final a in list)
          {
            'bank': a.bank,
            'account': a.account,
            'balance': a.balance,
            'updated_at': a.updatedAt.toUtc().toIso8601String(),
            'exact': a.fromNotification,
          },
      ];

  /// Gộp theo (ngân hàng, tài khoản): bản cập nhật sau thắng. Mới nhất lên đầu.
  static List<AccountBalance> merge(List<AccountBalance> a, List<AccountBalance> b) {
    final byKey = <String, AccountBalance>{};
    for (final x in [...a, ...b]) {
      final k = '${x.bank.toLowerCase()}|${x.account}';
      final cur = byKey[k];
      if (cur == null || x.updatedAt.isAfter(cur.updatedAt)) byKey[k] = x;
    }
    return byKey.values.toList()..sort((x, y) => y.updatedAt.compareTo(x.updatedAt));
  }

  static bool _same(List<AccountBalance> a, List<AccountBalance> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i], y = b[i];
      if (x.bank != y.bank ||
          x.account != y.account ||
          x.balance != y.balance ||
          x.fromNotification != y.fromNotification ||
          !x.updatedAt.isAtSameMomentAs(y.updatedAt)) {
        return false;
      }
    }
    return true;
  }

  /// Số dư đang lưu trên cloud (đọc mới từ server; lỗi mạng -> dùng bản trong phiên).
  static Future<List<AccountBalance>> fetch(sb.SupabaseClient client) async {
    try {
      final res = await client.auth.getUser().timeout(const Duration(seconds: 10));
      return fromMetadata(res.user?.userMetadata);
    } catch (_) {
      return fromMetadata(client.auth.currentUser?.userMetadata);
    }
  }

  /// Đẩy số dư máy này lên (gộp với bản cloud); không đổi gì thì không gửi.
  static Future<void> publish(
    sb.SupabaseClient client,
    List<AccountBalance> local,
    List<AccountBalance> cloud,
  ) async {
    if (local.isEmpty) return;
    final merged = merge(cloud, local);
    if (_same(merged, cloud)) return;
    await client.auth.updateUser(sb.UserAttributes(data: {key: toMetadata(merged)}));
  }
}
