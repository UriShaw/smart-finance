import 'dart:async';
import 'dart:math';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/security/app_logger.dart';
import '../../core/storage/app_database.dart';
import '../../domain/repositories/remote_gateway.dart';
import '../../domain/usecases/conflict_resolver.dart';
import '../local/entity_dao.dart';
import '../local/meta_dao.dart';
import '../local/outbox_dao.dart';
import '../models/db_mappers.dart';
import '../models/remote_mappers.dart';
import '../repositories/data_events.dart';
import 'cache_janitor.dart';
import 'photo_service.dart';

enum SyncPhase { idle, syncing, offline, disabled, error }

class SyncSnapshot {
  const SyncSnapshot({
    required this.phase,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.lastError,
  });

  final SyncPhase phase;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final AppErrorType? lastError;

  static const initial = SyncSnapshot(phase: SyncPhase.idle);
}

class SyncSettings {
  const SyncSettings({
    required this.retentionDays,
    required this.keepLocalPhotos,
  });

  final int retentionDays;
  final bool keepLocalPhotos;
}

class SyncResult {
  const SyncResult({
    this.pushed = 0,
    this.failed = 0,
    this.pulled = 0,
    this.skippedReason,
    this.cleanup = const CleanupReport(),
  });

  final int pushed;
  final int failed;
  final int pulled;
  final String? skippedReason;
  final CleanupReport cleanup;

  bool get skipped => skippedReason != null;
}

/// Sync Engine offline-first (spec H + I):
/// push outbox (retry + exponential backoff + idempotent upsert) -> pull theo
/// server_updated_at -> giải quyết xung đột -> dọn bộ nhớ tạm.
class SyncEngine {
  SyncEngine({
    required this.database,
    required this.remote,
    required this.events,
    required this.userId,
    required this.isCloudUser,
    required this.isOnline,
    required this.settings,
    this.afterPull,
    PhotoService? photos,
    CacheJanitor? janitor,
    DateTime Function()? clock,
    Random? random,
  })  : photos = photos ?? const PhotoService(),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random() {
    this.janitor = janitor ??
        CacheJanitor(database: database, userId: userId, photos: this.photos, clock: _clock);
  }

  final AppDatabase database;
  final RemoteGateway? remote;
  final DataEvents events;
  final String Function() userId;
  final bool Function() isCloudUser;
  final Future<bool> Function() isOnline;
  final SyncSettings Function() settings;

  /// Chạy sau khi kéo được bản ghi mới từ máy khác (vd. dọn giao dịch trùng).
  final Future<void> Function()? afterPull;
  final PhotoService photos;
  late final CacheJanitor janitor;
  final DateTime Function() _clock;
  final Random _random;

  static const _outbox = OutboxDao();
  static const _meta = MetaDao();

  final _status = StreamController<SyncSnapshot>.broadcast();
  SyncSnapshot _last = SyncSnapshot.initial;
  Future<SyncResult>? _inFlight;
  bool _again = false;
  Timer? _debounce;
  Timer? _periodic;
  StreamSubscription<void>? _writesSub;
  bool _disposed = false;

  Stream<SyncSnapshot> get status => _status.stream;
  SyncSnapshot get last => _last;

  Db get _db => database.db;

  void start() {
    _writesSub ??= events.localWrites.listen((_) => requestSoon());
    _periodic ??= Timer.periodic(AppConstants.syncPeriodic, (_) => syncNow());
    unawaited(refreshStatus());
  }

  void requestSoon() {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.syncDebounce, () => syncNow());
  }

  void onConnectivityChanged(bool online) {
    if (online) {
      syncNow(force: true);
    } else {
      _emit(SyncSnapshot(
        phase: isCloudUser() ? SyncPhase.offline : SyncPhase.disabled,
        pendingCount: _last.pendingCount,
        lastSyncAt: _last.lastSyncAt,
      ));
    }
  }

  /// Chạy đồng bộ; nếu đang chạy thì gộp yêu cầu và chạy thêm 1 lượt sau đó.
  Future<SyncResult> syncNow({bool force = false}) {
    if (_disposed) return Future.value(const SyncResult(skippedReason: 'disposed'));
    if (_inFlight != null) {
      _again = true;
      return _inFlight!;
    }
    final f = _loop(force);
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  Future<SyncResult> _loop(bool force) async {
    SyncResult result;
    do {
      _again = false;
      result = await _runOnce(force);
    } while (_again && !_disposed && !result.skipped);
    return result;
  }

  Future<void> refreshStatus() async {
    final uid = userId();
    final pending = await _outbox.count(_db, uid);
    final lastStr = await _meta.get(_db, MetaDao.lastSyncKey(uid));
    final phase = (remote == null || !isCloudUser())
        ? SyncPhase.disabled
        : (_last.phase == SyncPhase.syncing ? SyncPhase.syncing : _last.phase);
    _emit(SyncSnapshot(
      phase: phase,
      pendingCount: pending,
      lastSyncAt: lastStr == null ? null : DateTime.tryParse(lastStr),
      lastError: _last.lastError,
    ));
  }

  Future<SyncResult> _runOnce(bool force) async {
    final uid = userId();
    final gw = remote;
    if (gw == null || !isCloudUser() || uid == AppConstants.localUserId) {
      await refreshStatus();
      return const SyncResult(skippedReason: 'cloud_disabled');
    }
    if (!await isOnline()) {
      _emit(SyncSnapshot(
          phase: SyncPhase.offline,
          pendingCount: await _outbox.count(_db, uid),
          lastSyncAt: _last.lastSyncAt));
      return const SyncResult(skippedReason: 'offline');
    }

    _emit(SyncSnapshot(
        phase: SyncPhase.syncing, pendingCount: _last.pendingCount, lastSyncAt: _last.lastSyncAt));

    var pushed = 0;
    var failed = 0;
    var pulled = 0;
    AppErrorType? error;
    var cleanup = const CleanupReport();

    try {
      final p = await _push(gw, uid, force: force);
      pushed = p.$1;
      failed = p.$2;
      error = p.$3;
      if (error != AppErrorType.network && error != AppErrorType.auth) {
        pulled = await _pull(gw, uid);
        if (pulled > 0) await afterPull?.call();
      }
      final s = settings();
      cleanup = await janitor.run(
        cloudActive: true,
        retentionDays: s.retentionDays,
        keepLocalPhotos: s.keepLocalPhotos,
      );
      if (error == null) {
        await _meta.set(_db, MetaDao.lastSyncKey(uid), _clock().toUtc().toIso8601String());
      }
    } catch (e) {
      error = AppError.from(e).type;
      AppLogger.e('sync', 'sync run failed', e);
    }

    if (pulled > 0 || cleanup.changed || pushed > 0) events.bump();

    final pending = await _outbox.count(_db, uid);
    final lastStr = await _meta.get(_db, MetaDao.lastSyncKey(uid));
    _emit(SyncSnapshot(
      phase: error == null ? SyncPhase.idle : SyncPhase.error,
      pendingCount: pending,
      lastSyncAt: lastStr == null ? null : DateTime.tryParse(lastStr),
      lastError: error,
    ));
    return SyncResult(pushed: pushed, failed: failed, pulled: pulled, cleanup: cleanup);
  }

  // ---------------------------------------------------------------- PUSH

  Future<(int, int, AppErrorType?)> _push(RemoteGateway gw, String uid,
      {required bool force}) async {
    final entries = await _outbox.due(_db, uid, ms(_clock()), ignoreBackoff: force);
    var ok = 0;
    var failed = 0;
    AppErrorType? firstError;
    for (final e in entries) {
      try {
        final done = await _pushOne(gw, uid, e);
        if (done) {
          ok++;
        } else {
          failed++;
          firstError ??= AppErrorType.storage;
        }
      } catch (err) {
        final type = AppError.from(err).type;
        failed++;
        firstError ??= type;
        await _outbox.fail(_db, e,
            nextAttemptAt: _nextAttempt(e.attempts), error: '${type.name}:${err.runtimeType}');
        if (e.attempts + 1 >= AppConstants.syncFailedAfterAttempts) {
          await EntityDao(e.entity).markStatus(_db, e.entityId, 'failed');
        }
        AppLogger.e('sync', 'push ${e.entity}/${AppLogger.shortId(e.entityId)}', err);
        // Mất mạng / hết phiên -> dừng lượt này, giữ nguyên hàng đợi.
        if (type == AppErrorType.network || type == AppErrorType.auth) break;
      }
    }
    return (ok, failed, firstError);
  }

  int _nextAttempt(int attempts) {
    final base = 5 * pow(2, min(attempts, 12)).toInt();
    final capped = min(base, AppConstants.syncMaxBackoffSeconds);
    final jitter = (capped * 0.2 * _random.nextDouble()).round();
    return ms(_clock()) + (capped + jitter) * 1000;
  }

  /// true = hoàn tất; false = metadata đã lên nhưng ảnh chưa (sẽ retry).
  Future<bool> _pushOne(RemoteGateway gw, String uid, OutboxEntry e) async {
    final entity = SyncEntity.byLocalTable(e.entity);
    final dao = EntityDao(e.entity);
    final row = await dao.getRaw(_db, e.entityId);
    if (row == null) {
      await _outbox.complete(_db, e);
      return true;
    }
    final r = Map<String, Object?>.of(row);
    final deleted = r['deleted_at'] != null;

    var photoFailed = false;
    var photoUploaded = false;
    if (entity == SyncEntity.transactions &&
        !deleted &&
        r['local_image_path'] != null &&
        r['remote_image_path'] == null) {
      try {
        final bytes = await photos.read(r['local_image_path'] as String?);
        if (bytes != null) {
          final path = PhotoService.remotePath(uid, e.entityId);
          await gw.uploadPhoto(path, bytes);
          await _db.update('transactions', {'remote_image_path': path},
              where: 'id = ?', whereArgs: [e.entityId]);
          r['remote_image_path'] = path;
          photoUploaded = true;
        } else {
          // File local đã mất -> bỏ tham chiếu để không kẹt hàng đợi.
          await _db.update('transactions', {'local_image_path': null},
              where: 'id = ?', whereArgs: [e.entityId]);
          r['local_image_path'] = null;
        }
      } catch (err) {
        final type = AppError.from(err).type;
        if (type == AppErrorType.network || type == AppErrorType.auth) rethrow;
        photoFailed = true;
        AppLogger.e('sync', 'photo upload ${AppLogger.shortId(e.entityId)}', err);
      }
    }

    // Metadata vẫn được đẩy kể cả khi ảnh lỗi -> thiết bị khác thấy giao dịch.
    await gw.upsert(entity.remoteTable, RemoteMapper.toRemote(entity, r));

    if (photoFailed) {
      await _outbox.fail(_db, e, nextAttemptAt: _nextAttempt(e.attempts), error: 'storage:photo');
      return false;
    }

    var completed = false;
    await _db.transaction((txn) async {
      completed = await _outbox.complete(txn, e);
      if (completed) {
        await dao.markSynced(txn, e.entityId, r['updated_at'] as int);
      }
    });
    if (!completed) return true; // có thay đổi mới hơn, sẽ đẩy ở lượt sau

    if (deleted) {
      // Tombstone đã lên cloud: xóa ảnh cloud (best-effort) và file local.
      final remotePath = r['remote_image_path'] as String?;
      if (remotePath != null) {
        try {
          await gw.deletePhoto(remotePath);
        } catch (_) {}
      }
      await photos.deleteLocal(r['local_image_path'] as String?);
    } else if (photoUploaded && !settings().keepLocalPhotos) {
      // Ảnh đã an toàn trên cloud -> xóa bản tạm để tiết kiệm bộ nhớ máy.
      await photos.deleteLocal(r['local_image_path'] as String?);
      await _db.update('transactions', {'local_image_path': null},
          where: 'id = ? AND updated_at = ?', whereArgs: [e.entityId, r['updated_at']]);
    }
    return true;
  }

  // ---------------------------------------------------------------- PULL

  Future<int> _pull(RemoteGateway gw, String uid) async {
    var changed = 0;
    final entities = [...SyncEntity.values]..sort((a, b) => a.priority.compareTo(b.priority));
    for (final entity in entities) {
      final key = MetaDao.pullCursorKey(entity.remoteTable, uid);
      var since = await _meta.get(_db, key);
      while (true) {
        final rows = await gw.fetchChanges(entity.remoteTable,
            userId: uid, since: since, limit: AppConstants.pullPageSize);
        for (final m in rows) {
          if (await _applyRemote(entity, m, uid)) changed++;
        }
        if (rows.isNotEmpty) {
          since = rows.last['server_updated_at'] as String?;
          await _meta.set(_db, key, since);
        }
        if (rows.length < AppConstants.pullPageSize) break;
      }
    }
    return changed;
  }

  Future<bool> _applyRemote(SyncEntity entity, Map<String, dynamic> m, String uid) async {
    if (m['user_id'] != uid) return false; // phòng thủ, RLS đã chặn
    final id = m['id'] as String;
    final dao = EntityDao(entity.localTable);
    final local = await dao.getRaw(_db, id);
    final remoteUpdated = DateTime.parse(m['updated_at'] as String);
    final remoteDeleted = m['deleted_at'] != null;
    final isTx = entity == SyncEntity.transactions;

    if (local == null) {
      if (isTx) {
        final inArchive = await _db.query('tx_archive',
            columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (remoteDeleted) {
          if (inArchive.isNotEmpty) {
            await _db.delete('tx_archive', where: 'id = ?', whereArgs: [id]);
            return true;
          }
          return false;
        }
        final retention = settings().retentionDays;
        final txDate = DateTime.parse(m['transaction_date'] as String);
        final cutoff = _clock().subtract(Duration(days: retention));
        if (retention > 0 && txDate.isBefore(cutoff)) {
          await _db.rawInsert(
            'INSERT OR REPLACE INTO tx_archive (id, user_id, type, amount_minor, transaction_date, category_id) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            [
              id,
              uid,
              m['type'],
              (m['amount_minor'] as num).toInt(),
              txDate.millisecondsSinceEpoch,
              m['category_id'],
            ],
          );
          return true;
        }
        if (inArchive.isNotEmpty) {
          await _db.delete('tx_archive', where: 'id = ?', whereArgs: [id]);
        }
      }
      if (remoteDeleted) return false;
      await dao.upsertRaw(_db, RemoteMapper.toLocal(entity, m));
      return true;
    }

    final pending = await _outbox.find(_db, entity.localTable, id);
    final decision = ConflictResolver.resolve(
      localUpdatedAt: fromMs(local['updated_at']),
      localPending: pending != null,
      localDeleted: local['deleted_at'] != null,
      remoteUpdatedAt: remoteUpdated,
      remoteDeleted: remoteDeleted,
    );
    if (decision == ConflictDecision.keepLocal) return false;

    // Không ghi đè nếu dữ liệu giống hệt (tránh làm mới UI vô ích).
    if (pending == null &&
        local['sync_status'] == 'synced' &&
        local['updated_at'] == remoteUpdated.millisecondsSinceEpoch &&
        !remoteDeleted &&
        (!isTx || local['remote_image_path'] == m['image_path'])) {
      return false;
    }

    String? fileToDelete;
    await _db.transaction((txn) async {
      if (pending != null) {
        await _outbox.remove(txn, entity.localTable, id);
      }
      if (remoteDeleted) {
        fileToDelete = isTx ? local['local_image_path'] as String? : null;
        await dao.hardDelete(txn, id);
      } else {
        final row = RemoteMapper.toLocal(entity, m, existing: local);
        if (isTx && local['local_image_path'] != null && row['local_image_path'] == null) {
          fileToDelete = local['local_image_path'] as String?;
        }
        await dao.upsertRaw(txn, row);
      }
    });
    await photos.deleteLocal(fileToDelete);
    return true;
  }

  /// Khôi phục toàn bộ từ cloud: reset con trỏ pull rồi đồng bộ lại.
  Future<SyncResult> rehydrateFromCloud() async {
    final uid = userId();
    await _meta.removePrefix(_db, 'pull_cursor:');
    AppLogger.d('sync', 'rehydrate for ${AppLogger.shortId(uid)}');
    return syncNow(force: true);
  }

  void _emit(SyncSnapshot s) {
    _last = s;
    if (!_status.isClosed) _status.add(s);
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    _periodic?.cancel();
    await _writesSub?.cancel();
    await _status.close();
  }
}
