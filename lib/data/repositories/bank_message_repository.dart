import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/storage/app_database.dart';
import 'data_events.dart';

/// Thông báo ngân hàng gốc (chỉ lưu trên máy nhận thông báo).
class BankMessage {
  const BankMessage({
    required this.id,
    required this.txId,
    required this.pkg,
    required this.bank,
    required this.account,
    required this.title,
    required this.body,
    required this.direction,
    required this.amount,
    required this.balance,
    required this.postedAt,
  });

  final String id;
  final String? txId;
  final String pkg;
  final String bank;

  /// 4 số cuối tài khoản ("" nếu không rõ).
  final String account;
  final String title;
  final String body;

  /// 1 tiền vào, -1 tiền ra.
  final int direction;

  /// Đồng (không nhân 100).
  final int amount;

  /// Số dư sau giao dịch theo ngân hàng (đồng), -1 nếu thông báo không ghi.
  final int balance;
  final DateTime postedAt;

  Map<String, Object?> toRow() => {
        'id': id,
        'tx_id': txId,
        'pkg': pkg,
        'bank': bank,
        'account': account,
        'title': title,
        'body': body,
        'direction': direction,
        'amount': amount,
        'balance': balance,
        'posted_at': postedAt.millisecondsSinceEpoch,
      };

  static BankMessage fromRow(Map<String, Object?> r) => BankMessage(
        id: r['id'] as String,
        txId: r['tx_id'] as String?,
        pkg: (r['pkg'] as String?) ?? '',
        bank: (r['bank'] as String?) ?? '',
        account: (r['account'] as String?) ?? '',
        title: (r['title'] as String?) ?? '',
        body: (r['body'] as String?) ?? '',
        direction: (r['direction'] as int?) ?? 0,
        amount: (r['amount'] as int?) ?? 0,
        balance: (r['balance'] as int?) ?? -1,
        postedAt: DateTime.fromMillisecondsSinceEpoch((r['posted_at'] as int?) ?? 0),
      );
}

/// Số dư một tài khoản theo thông báo ngân hàng mới nhất.
class AccountBalance {
  const AccountBalance({
    required this.bank,
    required this.account,
    required this.balance,
    required this.updatedAt,
    required this.fromNotification,
  });

  final String bank;
  final String account;

  /// Đồng.
  final int balance;
  final DateTime updatedAt;

  /// true = đúng con số ngân hàng báo; false = đã cộng/trừ thêm các giao dịch
  /// sau đó mà thông báo không ghi số dư.
  final bool fromNotification;

  String get label => account.isEmpty ? bank : '$bank ••$account';
}

class BankMessageRepository {
  BankMessageRepository(this.database, this.events);

  final AppDatabase database;
  final DataEvents events;

  Future<void> save(BankMessage m) async {
    await database.db
        .insert('bank_messages', m.toRow(), conflictAlgorithm: ConflictAlgorithm.ignore);
    events.bump();
  }

  Future<bool> exists(String id) async {
    final rows = await database.db
        .query('bank_messages', columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  Future<BankMessage?> byTransaction(String txId) async {
    final rows = await database.db.query('bank_messages',
        where: 'tx_id = ?', whereArgs: [txId], orderBy: 'posted_at DESC', limit: 1);
    return rows.isEmpty ? null : BankMessage.fromRow(rows.first);
  }

  Future<int> deleteAll() async {
    final n = await database.db.delete('bank_messages');
    events.bump();
    return n;
  }

  /// Số dư từng tài khoản: lấy số dư ngân hàng báo gần nhất; các thông báo sau đó
  /// không ghi số dư thì cộng/trừ theo số tiền. Tài khoản chưa từng có số dư -> bỏ qua.
  ///
  /// [userId]: chỉ tính thông báo đã ghi vào tài khoản đó (nhiều tài khoản trên 1 máy).
  Future<List<AccountBalance>> balances({String? userId}) async {
    // Bỏ qua thông báo của giao dịch người dùng đã xoá (vd. nhận nhầm tin khuyến mãi).
    final rows = userId == null ? await database.db.rawQuery('''
      SELECT m.* FROM bank_messages m
      LEFT JOIN transactions t ON t.id = m.tx_id
      WHERE t.id IS NULL OR t.deleted_at IS NULL
      ORDER BY m.posted_at ASC''') : await database.db.rawQuery('''
      SELECT m.* FROM bank_messages m
      JOIN transactions t ON t.id = m.tx_id
      WHERE t.user_id = ? AND t.deleted_at IS NULL
      ORDER BY m.posted_at ASC''', [userId]);
    final msgs = rows.map(BankMessage.fromRow).toList();
    // Các tài khoản đã biết của mỗi ngân hàng (để gán thông báo không ghi số TK).
    final known = <String, Set<String>>{};
    for (final m in msgs) {
      if (m.account.isNotEmpty) {
        known.putIfAbsent(m.bank.toLowerCase(), () => <String>{}).add(m.account);
      }
    }
    final state = <String, _Acc>{};
    for (final m in msgs) {
      final bankKey = m.bank.toLowerCase();
      var account = m.account;
      if (account.isEmpty) {
        final ks = known[bankKey];
        if (ks != null && ks.length == 1) {
          account = ks.first; // ngân hàng chỉ có 1 TK -> chắc chắn là TK đó
        } else if (ks != null && ks.length > 1) {
          continue; // không biết TK nào -> không đoán để tránh sai số dư
        }
      }
      final key = '$bankKey|$account';
      final acc = state.putIfAbsent(key, () => _Acc(m.bank, account));
      if (m.balance >= 0) {
        acc
          ..balance = m.balance
          ..exact = true
          ..updatedAt = m.postedAt;
      } else if (acc.balance != null) {
        acc
          ..balance = acc.balance! + m.direction * m.amount
          ..exact = false
          ..updatedAt = m.postedAt;
      }
    }
    final out = <AccountBalance>[
      for (final a in state.values)
        if (a.balance != null)
          AccountBalance(
            bank: a.bank,
            account: a.account,
            balance: a.balance!,
            updatedAt: a.updatedAt!,
            fromNotification: a.exact,
          ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
}

class _Acc {
  _Acc(this.bank, this.account);
  final String bank;
  final String account;
  int? balance;
  bool exact = false;
  DateTime? updatedAt;
}
