import '../../../core/storage/app_database.dart';
import 'transaction_repository.dart';

/// Xoá giao dịch trùng do nhiều điện thoại cùng tài khoản cùng nhận 1 thông báo ngân hàng
/// (mã giao dịch khác nhau: máy đọc số dư khác nhau, hoặc chạy phiên bản app khác nhau).
///
/// Trùng = cùng loại + cùng số tiền, thời gian lệch nhau không quá [window] (tính theo giây).
/// Giữ bản có ảnh; cùng có/không ảnh thì giữ bản sớm hơn, rồi mã nhỏ hơn -> mọi máy chọn
/// CÙNG một bản giữ lại (không bao giờ xoá cả hai).
class DuplicateCleaner {
  DuplicateCleaner({required this.database, required this.transactions});

  static const window = Duration(seconds: 60);

  final AppDatabase database;
  final TransactionRepository transactions;

  /// Trả về số giao dịch đã xoá.
  Future<int> run() async {
    final db = database.db;
    final rows = await db.rawQuery(
      '''
      SELECT t.id, t.type, t.amount_minor, t.transaction_date AS d,
             (t.local_image_path IS NOT NULL OR t.remote_image_path IS NOT NULL) AS photo,
             (SELECT MAX(m.balance) FROM bank_messages m WHERE m.tx_id = t.id) AS bal
      FROM transactions t
      WHERE t.user_id = ? AND t.deleted_at IS NULL
      ORDER BY t.type, t.amount_minor, t.transaction_date, t.id''',
      [transactions.userId()],
    );

    var removed = 0;
    var group = <_Tx>[];
    Future<void> flush() async {
      if (group.length > 1) removed += await _resolve(group);
      group = [];
    }

    for (final r in rows) {
      final tx = _Tx(
        id: r['id'] as String,
        key: '${r['type']}|${r['amount_minor']}',
        date: r['d'] as int,
        hasPhoto: (r['photo'] as int? ?? 0) != 0,
        balance: r['bal'] as int?,
      );
      if (group.isNotEmpty &&
          (group.first.key != tx.key || tx.date - group.first.date > window.inMilliseconds)) {
        await flush();
      }
      group.add(tx);
    }
    await flush();
    return removed;
  }

  Future<int> _resolve(List<_Tx> group) async {
    // Máy này tự nhận 2 thông báo có số dư khác nhau -> 2 giao dịch thật, không phải trùng.
    final balances = {
      for (final t in group)
        if (t.balance != null && t.balance! >= 0) t.balance,
    };
    if (balances.length > 1) return 0;

    final sorted = [...group]..sort((a, b) {
        if (a.hasPhoto != b.hasPhoto) return a.hasPhoto ? -1 : 1;
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final keep = sorted.first;
    for (final t in sorted.skip(1)) {
      await transactions.delete(t.id);
      // Tin nhắn gốc chuyển sang bản giữ lại -> số dư ngân hàng không mất.
      await database.db.update(
        'bank_messages',
        {'tx_id': keep.id},
        where: 'tx_id = ?',
        whereArgs: [t.id],
      );
    }
    return sorted.length - 1;
  }
}

class _Tx {
  const _Tx({
    required this.id,
    required this.key,
    required this.date,
    required this.hasPhoto,
    required this.balance,
  });

  final String id;
  final String key;
  final int date;
  final bool hasPhoto;
  final int? balance;
}
