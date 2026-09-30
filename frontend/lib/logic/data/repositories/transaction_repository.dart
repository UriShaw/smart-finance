import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/errors/app_error.dart';
import '../../../core/storage/app_database.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../local/entity_dao.dart';
import '../local/outbox_dao.dart';
import '../models/db_mappers.dart';
import '../models/remote_mappers.dart';
import 'data_events.dart';

class TxQuery {
  const TxQuery({
    this.search,
    this.type,
    this.categoryId,
    this.from,
    this.to,
    this.minMinor,
    this.maxMinor,
  });

  final String? search;
  final TxType? type;
  final String? categoryId;
  final DateTime? from;
  final DateTime? to;

  /// Lọc theo mức tiền (đơn vị x100): >= [minMinor], < [maxMinor].
  final int? minMinor;
  final int? maxMinor;

  bool get isEmpty =>
      (search == null || search!.trim().isEmpty) &&
      type == null &&
      categoryId == null &&
      from == null &&
      to == null &&
      minMinor == null &&
      maxMinor == null;
}

/// Tổng hợp nhanh cho một bộ lọc (thẻ tóm tắt ở Lịch sử).
class TxSummary {
  const TxSummary({required this.count, required this.incomeMinor, required this.expenseMinor});
  static const empty = TxSummary(count: 0, incomeMinor: 0, expenseMinor: 0);
  final int count;
  final int incomeMinor;
  final int expenseMinor;
  int get netMinor => incomeMinor - expenseMinor;
}

/// Mọi ghi dữ liệu: Local DB trước -> UI cập nhật ngay -> Outbox -> Cloud (spec H).
class TransactionRepository {
  TransactionRepository({
    required this.database,
    required this.events,
    required this.userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final DataEvents events;
  final String Function() userId;
  final DateTime Function() _clock;

  static const _dao = EntityDao('transactions');
  static const _outbox = OutboxDao();
  static final _entity = SyncEntity.transactions.localTable;

  Db get _db => database.db;

  void _validate(FinanceTransaction t) {
    if (t.name.trim().isEmpty) {
      throw const AppError(AppErrorType.validation, detail: 'name');
    }
    if (t.amountMinor <= 0) {
      throw const AppError(AppErrorType.validation, detail: 'amount');
    }
    if ((t.latitude == null) != (t.longitude == null)) {
      throw const AppError(AppErrorType.validation, detail: 'coordinates');
    }
    if (t.latitude != null && (t.latitude!.abs() > 90 || t.longitude!.abs() > 180)) {
      throw const AppError(AppErrorType.validation, detail: 'coordinates');
    }
  }

  /// Tạo mới hoặc cập nhật (id do client sinh).
  Future<FinanceTransaction> save(FinanceTransaction t) async {
    _validate(t);
    final now = _clock();
    final uid = userId();
    late FinanceTransaction saved;
    await _db.transaction((txn) async {
      final existing = await _dao.getRaw(txn, t.id);
      saved = t.copyWith(
        userId: uid,
        name: t.name.trim(),
        createdAt: existing == null ? now : fromMs(existing['created_at']),
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      );
      await _dao.upsertRaw(txn, TxMapper.toRow(saved));
      await _outbox.enqueue(txn, entity: _entity, entityId: t.id, userId: uid, op: 'upsert');
    });
    events.localWrite();
    return saved;
  }

  /// Thêm giao dịch có id xác định nếu chưa tồn tại (kể cả đã bị xóa mềm).
  /// Dùng cho giao dịch tự động (thông báo ngân hàng) -> không bao giờ tạo trùng.
  Future<bool> importIfAbsent(FinanceTransaction t) async {
    _validate(t);
    final uid = userId();
    var inserted = false;
    await _db.transaction((txn) async {
      final row = TxMapper.toRow(t.copyWith(userId: uid, syncStatus: SyncStatus.pending));
      inserted = await _dao.insertIfAbsent(txn, row);
      if (inserted) {
        await _outbox.enqueue(txn, entity: _entity, entityId: t.id, userId: uid, op: 'upsert');
      }
    });
    if (inserted) events.localWrite();
    return inserted;
  }

  /// Xóa mềm (tombstone) để thiết bị khác biết bản ghi đã bị xóa.
  Future<void> delete(String id) async {
    final now = ms(_clock());
    final uid = userId();
    await _db.transaction((txn) async {
      final n = await txn.update(
        'transactions',
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, uid],
      );
      if (n > 0) {
        await _outbox.enqueue(txn, entity: _entity, entityId: id, userId: uid, op: 'delete');
      }
    });
    events.localWrite();
  }

  Future<FinanceTransaction?> getById(String id) async {
    final r = await _dao.getRaw(_db, id);
    return r == null ? null : TxMapper.fromRow(r);
  }

  Future<List<FinanceTransaction>> recent({int limit = 8}) => page(offset: 0, limit: limit);

  (String, List<Object?>) _where(TxQuery query) {
    final where = <String>['user_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[userId()];
    final s = query.search?.trim();
    if (s != null && s.isNotEmpty) {
      where.add('(name LIKE ? OR note LIKE ? OR location_name LIKE ?)');
      final like = '%$s%';
      args.addAll([like, like, like]);
    }
    if (query.type != null) {
      where.add('type = ?');
      args.add(query.type!.name);
    }
    if (query.categoryId != null) {
      where.add('category_id = ?');
      args.add(query.categoryId);
    }
    if (query.from != null) {
      where.add('transaction_date >= ?');
      args.add(ms(query.from!));
    }
    if (query.to != null) {
      where.add('transaction_date < ?');
      args.add(ms(query.to!));
    }
    if (query.minMinor != null) {
      where.add('amount_minor >= ?');
      args.add(query.minMinor);
    }
    if (query.maxMinor != null) {
      where.add('amount_minor < ?');
      args.add(query.maxMinor);
    }
    return (where.join(' AND '), args);
  }

  Future<List<FinanceTransaction>> page({
    required int offset,
    required int limit,
    TxQuery query = const TxQuery(),
  }) async {
    final (where, args) = _where(query);
    final rows = await _db.query(
      'transactions',
      where: where,
      whereArgs: args,
      orderBy: 'transaction_date DESC, created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(TxMapper.fromRow).toList();
  }

  /// Số giao dịch + tổng thu/chi theo cùng bộ lọc với [page].
  Future<TxSummary> summary(TxQuery query) async {
    final (where, args) = _where(query);
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS n, '
      "COALESCE(SUM(CASE WHEN type = 'income' THEN amount_minor END), 0) AS inc, "
      "COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor END), 0) AS exp "
      'FROM transactions WHERE $where',
      args,
    );
    if (rows.isEmpty) return TxSummary.empty;
    final r = rows.first;
    int n(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    return TxSummary(count: n(r['n']), incomeMinor: n(r['inc']), expenseMinor: n(r['exp']));
  }

  /// "Xóa hết" (tính năng app cũ): xóa mềm mọi giao dịch của người dùng, đồng bộ lên cloud.
  Future<int> deleteAll() async {
    final now = ms(_clock());
    final uid = userId();
    var count = 0;
    await _db.transaction((txn) async {
      final rows = await txn.query('transactions',
          columns: ['id'], where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [uid]);
      for (final r in rows) {
        final id = r['id'] as String;
        await txn.update(
          'transactions',
          {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _outbox.enqueue(txn, entity: _entity, entityId: id, userId: uid, op: 'delete');
        count++;
      }
      // Giao dịch cũ đã dọn khỏi máy (tx_archive): tạo bản ghi "đã xoá" để cloud cũng xoá theo.
      final archived = await txn.query('tx_archive', where: 'user_id = ?', whereArgs: [uid]);
      for (final a in archived) {
        final id = a['id'] as String;
        await txn.insert(
            'transactions',
            {
              'id': id,
              'user_id': uid,
              'name': '-',
              'amount_minor': a['amount_minor'],
              'type': a['type'],
              'category_id': a['category_id'],
              'transaction_date': a['transaction_date'],
              'created_at': now,
              'updated_at': now,
              'deleted_at': now,
              'sync_status': 'pending',
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await _outbox.enqueue(txn, entity: _entity, entityId: id, userId: uid, op: 'delete');
        count++;
      }
      await txn.delete('tx_archive', where: 'user_id = ?', whereArgs: [uid]);
    });
    events.localWrite();
    return count;
  }

  Future<List<FinanceTransaction>> inRange(DateTime from, DateTime to) =>
      page(offset: 0, limit: 100000, query: TxQuery(from: from, to: to));

  /// Sổ cái rút gọn (gồm cả tx_archive) để tính số dư / thống kê offline.
  Future<List<LedgerEntry>> ledger({DateTime? from, DateTime? to}) async {
    final where = <String>['user_id = ?'];
    final args = <Object?>[userId()];
    if (from != null) {
      where.add('transaction_date >= ?');
      args.add(ms(from));
    }
    if (to != null) {
      where.add('transaction_date < ?');
      args.add(ms(to));
    }
    final rows = await _db.query('v_ledger', where: where.join(' AND '), whereArgs: args);
    return rows.map(TxMapper.ledgerFromRow).toList();
  }

  Future<List<FinanceTransaction>> withLocation() async {
    final rows = await _db.query(
      'transactions',
      where: 'user_id = ? AND deleted_at IS NULL AND '
          '(latitude IS NOT NULL OR location_name IS NOT NULL)',
      whereArgs: [userId()],
      orderBy: 'transaction_date DESC',
      limit: 2000,
    );
    return rows.map(TxMapper.fromRow).toList();
  }

  /// Giao dịch có ảnh khoảnh khắc (mới nhất trước).
  Future<List<FinanceTransaction>> withPhoto({int limit = 20}) async {
    final rows = await _db.query(
      'transactions',
      where: 'user_id = ? AND deleted_at IS NULL AND '
          '(local_image_path IS NOT NULL OR remote_image_path IS NOT NULL)',
      whereArgs: [userId()],
      orderBy: 'transaction_date DESC',
      limit: limit,
    );
    return rows.map(TxMapper.fromRow).toList();
  }

  Future<int> archivedCount() async {
    final r =
        await _db.rawQuery('SELECT COUNT(*) AS c FROM tx_archive WHERE user_id = ?', [userId()]);
    return (r.first['c'] as int?) ?? 0;
  }

  /// Chuyển dữ liệu remote (từ "tải thêm từ cloud") thành entity chỉ để hiển thị.
  static FinanceTransaction fromRemote(Map<String, dynamic> m) =>
      TxMapper.fromRow(RemoteMapper.toLocal(SyncEntity.transactions, m));
}
