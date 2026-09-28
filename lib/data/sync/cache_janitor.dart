import 'dart:io';

import '../../core/storage/app_database.dart';
import '../../core/storage/file_paths.dart';
import '../models/db_mappers.dart';
import 'photo_service.dart';

class CleanupReport {
  const CleanupReport({
    this.tombstonesPurged = 0,
    this.photosDeleted = 0,
    this.archived = 0,
    this.bytesFreed = 0,
  });

  final int tombstonesPurged;
  final int photosDeleted;
  final int archived;
  final int bytesFreed;

  bool get changed => tombstonesPurged + photosDeleted + archived > 0;
}

class StorageUsage {
  const StorageUsage({
    required this.dbBytes,
    required this.photoBytes,
    required this.pendingChanges,
    required this.localTransactions,
    required this.archivedTransactions,
  });

  final int dbBytes;
  final int photoBytes;
  final int pendingChanges;
  final int localTransactions;
  final int archivedTransactions;

  int get totalBytes => dbBytes + photoBytes;
}

/// Dọn "bộ nhớ tạm" sau khi dữ liệu đã an toàn trên cloud:
/// 1. Xóa tombstone đã đồng bộ.
/// 2. Xóa file ảnh local đã upload thành công.
/// 3. Xóa file ảnh mồ côi.
/// 4. (Tùy chọn) Chuyển giao dịch cũ hơn N ngày sang tx_archive rút gọn.
/// Không bao giờ xóa bản ghi còn nằm trong outbox (chưa lên cloud).
class CacheJanitor {
  CacheJanitor({
    required this.database,
    required this.userId,
    this.photos = const PhotoService(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final String Function() userId;
  final PhotoService photos;
  final DateTime Function() _clock;

  Db get _db => database.db;

  static const _notInOutbox =
      'NOT EXISTS (SELECT 1 FROM outbox o WHERE o.entity = ? AND o.entity_id = t.id)';

  Future<CleanupReport> run({
    required bool cloudActive,
    required int retentionDays,
    required bool keepLocalPhotos,
  }) async {
    if (!cloudActive) return const CleanupReport();
    final uid = userId();
    var tombstones = 0;
    var photosDeleted = 0;
    var archived = 0;
    var bytes = 0;

    // 1) Tombstone đã đồng bộ.
    for (final table in ['transactions', 'categories', 'budgets', 'recurring_rules']) {
      if (table == 'transactions') {
        final rows = await _db.rawQuery(
          "SELECT id, local_image_path FROM transactions t WHERE user_id = ? "
          "AND deleted_at IS NOT NULL AND sync_status = 'synced' AND $_notInOutbox",
          [uid, 'transactions'],
        );
        for (final r in rows) {
          bytes += await _deleteFile(r['local_image_path'] as String?);
        }
      }
      tombstones += await _db.rawDelete(
        "DELETE FROM $table WHERE id IN (SELECT id FROM $table t WHERE user_id = ? "
        "AND deleted_at IS NOT NULL AND sync_status = 'synced' AND $_notInOutbox)",
        [uid, table],
      );
    }

    // 2) Ảnh đã lên cloud.
    if (!keepLocalPhotos) {
      final rows = await _db.rawQuery(
        "SELECT id, local_image_path FROM transactions t WHERE user_id = ? "
        "AND local_image_path IS NOT NULL AND remote_image_path IS NOT NULL "
        "AND sync_status = 'synced' AND $_notInOutbox",
        [uid, 'transactions'],
      );
      for (final r in rows) {
        bytes += await _deleteFile(r['local_image_path'] as String?);
        await _db.update('transactions', {'local_image_path': null},
            where: 'id = ?', whereArgs: [r['id']]);
        photosDeleted++;
      }
    }

    // 3) Retention: giao dịch cũ đã đồng bộ -> tx_archive.
    if (retentionDays > 0) {
      final cutoff = ms(_clock().subtract(Duration(days: retentionDays)));
      await _db.transaction((txn) async {
        final rows = await txn.rawQuery(
          "SELECT id, local_image_path FROM transactions t WHERE user_id = ? "
          "AND deleted_at IS NULL AND sync_status = 'synced' "
          "AND transaction_date < ? AND $_notInOutbox",
          [uid, cutoff, 'transactions'],
        );
        if (rows.isEmpty) return;
        await txn.rawInsert(
          "INSERT OR REPLACE INTO tx_archive (id, user_id, type, amount_minor, transaction_date, category_id) "
          "SELECT id, user_id, type, amount_minor, transaction_date, category_id FROM transactions t "
          "WHERE user_id = ? AND deleted_at IS NULL AND sync_status = 'synced' "
          "AND transaction_date < ? AND $_notInOutbox",
          [uid, cutoff, 'transactions'],
        );
        archived = await txn.rawDelete(
          "DELETE FROM transactions WHERE id IN (SELECT id FROM transactions t WHERE user_id = ? "
          "AND deleted_at IS NULL AND sync_status = 'synced' "
          "AND transaction_date < ? AND $_notInOutbox)",
          [uid, cutoff, 'transactions'],
        );
        for (final r in rows) {
          bytes += await _deleteFile(r['local_image_path'] as String?);
        }
      });
    }

    // 4) Ảnh mồ côi (không còn giao dịch nào tham chiếu, cũ hơn 1 giờ).
    bytes += await _deleteOrphanPhotos();

    if (tombstones + archived > 200) {
      try {
        await _db.execute('VACUUM');
      } catch (_) {}
    }

    return CleanupReport(
      tombstonesPurged: tombstones,
      photosDeleted: photosDeleted,
      archived: archived,
      bytesFreed: bytes,
    );
  }

  Future<int> _deleteFile(String? path) async {
    if (path == null) return 0;
    try {
      final f = File(path);
      if (!await f.exists()) return 0;
      final size = await f.length();
      await photos.deleteLocal(path);
      return size;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _deleteOrphanPhotos() async {
    final dir = await FilePaths.photosDir();
    final rows = await _db
        .rawQuery('SELECT local_image_path FROM transactions WHERE local_image_path IS NOT NULL');
    final referenced = rows.map((r) => r['local_image_path'] as String).toSet();
    final threshold = _clock().subtract(const Duration(hours: 1));
    var bytes = 0;
    await for (final e in dir.list(followLinks: false)) {
      if (e is! File) continue;
      if (referenced.contains(e.path)) continue;
      try {
        final stat = await e.stat();
        if (stat.modified.isAfter(threshold)) continue;
        bytes += stat.size;
        await e.delete();
      } catch (_) {}
    }
    return bytes;
  }

  Future<StorageUsage> usage() async {
    final uid = userId();
    var dbBytes = 0;
    try {
      final f = File(database.path);
      if (await f.exists()) dbBytes = await f.length();
      final wal = File('${database.path}-wal');
      if (await wal.exists()) dbBytes += await wal.length();
    } catch (_) {}
    final photoBytes = await FilePaths.directorySize(await FilePaths.photosDir());
    int count(List<Map<String, Object?>> r) => (r.first['c'] as int?) ?? 0;
    final pending =
        count(await _db.rawQuery('SELECT COUNT(*) AS c FROM outbox WHERE user_id = ?', [uid]));
    final local = count(await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM transactions WHERE user_id = ? AND deleted_at IS NULL', [uid]));
    final archived =
        count(await _db.rawQuery('SELECT COUNT(*) AS c FROM tx_archive WHERE user_id = ?', [uid]));
    return StorageUsage(
      dbBytes: dbBytes,
      photoBytes: photoBytes,
      pendingChanges: pending,
      localTransactions: local,
      archivedTransactions: archived,
    );
  }
}
