import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/storage/app_database.dart';

/// Key-value nội bộ cho đồng bộ (con trỏ pull, thời điểm sync cuối...).
class MetaDao {
  const MetaDao();

  Future<String?> get(DbExecutor db, String key) async {
    final r = await db.query('sync_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> set(DbExecutor db, String key, String? value) async {
    await db.insert('sync_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removePrefix(DbExecutor db, String prefix) async {
    await db.delete('sync_meta', where: 'key LIKE ?', whereArgs: ['$prefix%']);
  }

  static String pullCursorKey(String table, String userId) => 'pull_cursor:$table:$userId';

  static String lastSyncKey(String userId) => 'last_sync:$userId';
}
