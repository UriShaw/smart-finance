import '../../core/constants/app_constants.dart';
import '../../core/storage/app_database.dart';
import '../../core/utils/ids.dart';
import '../local/outbox_dao.dart';
import 'data_events.dart';

/// Khi user dùng offline (user_id = 'local') rồi đăng nhập Google, chuyển toàn bộ
/// dữ liệu local sang Supabase user id để đồng bộ. Danh mục mặc định được đổi id
/// sang id xác định của user thật để không trùng với thiết bị khác.
class LocalDataClaimer {
  LocalDataClaimer(this.database, this.events);

  final AppDatabase database;
  final DataEvents events;
  static const _outbox = OutboxDao();

  Future<int> claim(String newUserId) async {
    const from = AppConstants.localUserId;
    if (newUserId == from) return 0;
    var moved = 0;
    await database.db.transaction((txn) async {
      // 1) Đổi id danh mục mặc định.
      final defaults = await txn
          .query('categories', where: 'user_id = ? AND default_key IS NOT NULL', whereArgs: [from]);
      for (final c in defaults) {
        final oldId = c['id'] as String;
        final newId = Ids.defaultCategory(newUserId, c['default_key'] as String);
        final clash = await txn.query('categories',
            columns: ['id'], where: 'id = ?', whereArgs: [newId], limit: 1);
        if (clash.isEmpty) {
          await txn.update('categories', {'id': newId}, where: 'id = ?', whereArgs: [oldId]);
        } else {
          await txn.delete('categories', where: 'id = ?', whereArgs: [oldId]);
        }
        for (final t in ['transactions', 'budgets', 'recurring_rules', 'tx_archive']) {
          await txn.update(t, {'category_id': newId}, where: 'category_id = ?', whereArgs: [oldId]);
        }
        await txn.delete('outbox',
            where: 'entity = ? AND entity_id = ?', whereArgs: ['categories', oldId]);
        if (clash.isEmpty) {
          await _outbox.enqueue(txn,
              entity: 'categories', entityId: newId, userId: newUserId, op: 'upsert');
        }
      }
      // 2) Chuyển user_id.
      for (final t in [
        'categories',
        'transactions',
        'budgets',
        'recurring_rules',
        'tx_archive',
      ]) {
        moved +=
            await txn.update(t, {'user_id': newUserId}, where: 'user_id = ?', whereArgs: [from]);
      }
      // 3) Outbox: sau khi đổi user_id, mọi thay đổi pending vẫn được đẩy.
      await _outbox.reassignUser(txn, from, newUserId);
      // Các giao dịch có danh mục vừa đổi id cần đẩy lại.
      final txs = await txn.query('transactions',
          columns: ['id'],
          where: "user_id = ? AND sync_status != 'synced'",
          whereArgs: [newUserId]);
      for (final r in txs) {
        await _outbox.enqueue(txn,
            entity: 'transactions', entityId: r['id'] as String, userId: newUserId, op: 'upsert');
      }
    });
    if (moved > 0) events.localWrite();
    return moved;
  }
}
