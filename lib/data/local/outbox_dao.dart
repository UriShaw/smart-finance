import '../../core/storage/app_database.dart';

class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.entity,
    required this.entityId,
    required this.userId,
    required this.op,
    required this.revision,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
  });

  final int id;
  final String entity;
  final String entityId;
  final String userId;
  final String op;
  final int revision;
  final int attempts;
  final int nextAttemptAt;
  final String? lastError;

  static OutboxEntry fromRow(Map<String, Object?> r) => OutboxEntry(
        id: r['id'] as int,
        entity: r['entity'] as String,
        entityId: r['entity_id'] as String,
        userId: r['user_id'] as String,
        op: r['op'] as String,
        revision: r['revision'] as int,
        attempts: r['attempts'] as int,
        nextAttemptAt: r['next_attempt_at'] as int,
        lastError: r['last_error'] as String?,
      );
}

/// Hàng đợi đồng bộ (outbox). Đây là "bộ nhớ tạm" của các thay đổi chưa lên cloud;
/// mỗi dòng bị xóa ngay khi đồng bộ thành công.
class OutboxDao {
  const OutboxDao();

  static const table = 'outbox';

  /// Gộp thay đổi: 1 entity chỉ 1 dòng; enqueue lại sẽ reset attempts và tăng revision.
  Future<void> enqueue(
    DbExecutor db, {
    required String entity,
    required String entityId,
    required String userId,
    required String op,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    // Không dùng UPSERT (ON CONFLICT DO UPDATE) vì SQLite trên Android cũ < 3.24.
    final updated = await db.rawUpdate('''
      UPDATE outbox SET
        op = ?, user_id = ?, revision = revision + 1,
        attempts = 0, next_attempt_at = 0, last_error = NULL
      WHERE entity = ? AND entity_id = ?
    ''', [op, userId, entity, entityId]);
    if (updated == 0) {
      await db.insert(table, {
        'entity': entity,
        'entity_id': entityId,
        'user_id': userId,
        'op': op,
        'revision': 1,
        'attempts': 0,
        'next_attempt_at': 0,
        'created_at': now,
      });
    }
  }

  Future<List<OutboxEntry>> due(DbExecutor db, String userId, int nowMs,
      {bool ignoreBackoff = false}) async {
    final rows = await db.rawQuery('''
      SELECT * FROM outbox
      WHERE user_id = ? ${ignoreBackoff ? '' : 'AND next_attempt_at <= ?'}
      ORDER BY
        CASE entity
          WHEN 'categories' THEN 0
          WHEN 'recurring_rules' THEN 1
          WHEN 'budgets' THEN 2
          ELSE 3
        END, id
    ''', ignoreBackoff ? [userId] : [userId, nowMs]);
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<OutboxEntry?> find(DbExecutor db, String entity, String entityId) async {
    final rows = await db.query(table,
        where: 'entity = ? AND entity_id = ?', whereArgs: [entity, entityId], limit: 1);
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  /// Xóa chỉ khi revision không đổi (không có thay đổi mới trong lúc đẩy).
  Future<bool> complete(DbExecutor db, OutboxEntry e) async {
    final n =
        await db.delete(table, where: 'id = ? AND revision = ?', whereArgs: [e.id, e.revision]);
    return n > 0;
  }

  Future<void> remove(DbExecutor db, String entity, String entityId) async {
    await db.delete(table, where: 'entity = ? AND entity_id = ?', whereArgs: [entity, entityId]);
  }

  Future<void> fail(DbExecutor db, OutboxEntry e,
      {required int nextAttemptAt, required String error}) async {
    await db.update(
      table,
      {
        'attempts': e.attempts + 1,
        'next_attempt_at': nextAttemptAt,
        'last_error': error.length > 200 ? error.substring(0, 200) : error,
      },
      where: 'id = ? AND revision = ?',
      whereArgs: [e.id, e.revision],
    );
  }

  Future<int> count(DbExecutor db, String userId) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM outbox WHERE user_id = ?', [userId]);
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> reassignUser(DbExecutor db, String from, String to) async {
    await db.update(table, {'user_id': to}, where: 'user_id = ?', whereArgs: [from]);
  }
}
