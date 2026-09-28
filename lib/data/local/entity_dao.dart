import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/storage/app_database.dart';
import '../models/db_mappers.dart';

/// Thao tác chung cho mọi bảng có id TEXT + updated_at + sync_status.
class EntityDao {
  const EntityDao(this.table);

  final String table;

  Future<DbRow?> getRaw(DbExecutor db, String id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertRaw(DbExecutor db, DbRow row) async {
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> insertIfAbsent(DbExecutor db, DbRow row) async {
    final exists = await getRaw(db, row['id'] as String);
    if (exists != null) return false;
    await db.insert(table, row);
    return true;
  }

  /// Chỉ đánh dấu synced nếu bản ghi chưa bị sửa kể từ lúc đọc (tránh race).
  Future<int> markSynced(DbExecutor db, String id, int updatedAtMs) {
    return db.update(
      table,
      {'sync_status': 'synced'},
      where: 'id = ? AND updated_at = ?',
      whereArgs: [id, updatedAtMs],
    );
  }

  Future<int> markStatus(DbExecutor db, String id, String status) {
    return db.update(table, {'sync_status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> hardDelete(DbExecutor db, String id) =>
      db.delete(table, where: 'id = ?', whereArgs: [id]);
}
