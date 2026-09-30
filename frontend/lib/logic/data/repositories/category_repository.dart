import '../../../core/errors/app_error.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/ids.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../local/entity_dao.dart';
import '../local/outbox_dao.dart';
import '../models/db_mappers.dart';
import 'data_events.dart';

class CategoryRepository {
  CategoryRepository({
    required this.database,
    required this.events,
    required this.userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final DataEvents events;
  final String Function() userId;
  final DateTime Function() _clock;

  static const _dao = EntityDao('categories');
  static const _outbox = OutboxDao();

  Db get _db => database.db;

  /// Tạo danh mục mặc định với id xác định (v5) -> nhiều thiết bị không bị trùng.
  Future<void> ensureDefaults() async {
    final uid = userId();
    // Mốc thời gian cố định (cũ) cho danh mục mặc định: thiết bị mới seed sau sẽ
    // KHÔNG ghi đè danh mục mặc định mà user đã đổi tên trên thiết bị khác (LWW).
    final seedTime = DateTime.utc(2000);
    var created = false;
    await _db.transaction((txn) async {
      final existing = await txn.query('categories',
          columns: ['id'], where: 'user_id = ?', whereArgs: [uid], limit: 1);
      if (existing.isNotEmpty) return;
      var order = 0;
      for (final d in DefaultCategory.all) {
        final c = TxCategory(
          id: Ids.defaultCategory(uid, d.key),
          userId: uid,
          name: '',
          type: d.type,
          icon: d.icon,
          color: d.color,
          defaultKey: d.key,
          sortOrder: order++,
          createdAt: seedTime,
          updatedAt: seedTime,
        );
        if (await _dao.insertIfAbsent(txn, CategoryMapper.toRow(c))) {
          await _outbox.enqueue(txn,
              entity: 'categories', entityId: c.id, userId: uid, op: 'upsert');
          created = true;
        }
      }
    });
    if (created) events.localWrite();
  }

  Future<List<TxCategory>> list({TxType? type}) async {
    final where = ['user_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[userId()];
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    final rows = await _db.query('categories',
        where: where.join(' AND '), whereArgs: args, orderBy: 'type DESC, sort_order, name');
    return rows.map(CategoryMapper.fromRow).toList();
  }

  /// Gồm cả danh mục đã xóa (để hiển thị tên cho giao dịch cũ).
  Future<Map<String, TxCategory>> mapAll() async {
    final rows = await _db.query('categories', where: 'user_id = ?', whereArgs: [userId()]);
    return {
      for (final r in rows) r['id'] as String: CategoryMapper.fromRow(r),
    };
  }

  Future<TxCategory> save(TxCategory c) async {
    if (c.name.trim().isEmpty && c.defaultKey == null) {
      throw const AppError(AppErrorType.validation, detail: 'name');
    }
    final uid = userId();
    final now = _clock();
    late TxCategory saved;
    await _db.transaction((txn) async {
      final existing = await _dao.getRaw(txn, c.id);
      saved = TxCategory(
        id: c.id,
        userId: uid,
        name: c.name.trim(),
        type: c.type,
        icon: c.icon,
        color: c.color,
        defaultKey: c.defaultKey,
        sortOrder: c.sortOrder,
        createdAt: existing == null ? now : fromMs(existing['created_at']),
        updatedAt: now,
      );
      await _dao.upsertRaw(txn, CategoryMapper.toRow(saved));
      await _outbox.enqueue(txn, entity: 'categories', entityId: c.id, userId: uid, op: 'upsert');
    });
    events.localWrite();
    return saved;
  }

  /// Xóa mềm. Giao dịch cũ giữ category_id, UI hiển thị tên cũ.
  Future<void> delete(String id) async {
    final uid = userId();
    final now = ms(_clock());
    await _db.transaction((txn) async {
      final n = await txn.update(
        'categories',
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, uid],
      );
      if (n > 0) {
        await _outbox.enqueue(txn, entity: 'categories', entityId: id, userId: uid, op: 'delete');
      }
    });
    events.localWrite();
  }
}
