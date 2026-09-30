import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/core/storage/file_paths.dart';
import 'package:smart_finance/core/utils/ids.dart';
import 'package:smart_finance/logic/data/local/outbox_dao.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';
import 'package:smart_finance/logic/data/repositories/transaction_repository.dart';
import 'package:smart_finance/logic/data/sync/sync_engine.dart';
import 'package:smart_finance/logic/domain/entities/common.dart';
import 'package:smart_finance/logic/domain/entities/finance_transaction.dart';

import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late DataEvents events;
  late FakeRemoteGateway remote;
  late TransactionRepository repo;
  late SyncEngine engine;
  var retention = 0;
  var keepPhotos = false;
  const outbox = OutboxDao();
  const uid = 'user-a';

  FinanceTransaction tx({String name = 'Cơm', int minor = 4000000, DateTime? date, String? photo}) {
    final now = DateTime.now();
    return FinanceTransaction(
      id: Ids.newId(),
      userId: uid,
      name: name,
      amountMinor: minor,
      type: TxType.expense,
      date: date ?? now,
      createdAt: now,
      updatedAt: now,
      localImagePath: photo,
    );
  }

  Future<String> fakePhoto() async {
    final dir = await FilePaths.photosDir();
    final f = File(p.join(dir.path, '${Ids.newId()}.jpg'));
    await f.writeAsBytes(Uint8List.fromList(List<int>.generate(2048, (i) => i % 256)));
    return f.path;
  }

  setUp(() async {
    db = await openTestDb();
    events = DataEvents();
    remote = FakeRemoteGateway();
    retention = 0;
    keepPhotos = false;
    repo = TransactionRepository(database: db, events: events, userId: () => uid);
    engine = SyncEngine(
      database: db,
      remote: remote,
      events: events,
      userId: () => uid,
      isCloudUser: () => true,
      isOnline: () async => !remote.offline,
      settings: () => SyncSettings(retentionDays: retention, keepLocalPhotos: keepPhotos),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('push: offline -> nothing lost; online -> synced and outbox emptied', () async {
    remote.offline = true;
    final t = await repo.save(tx());
    final r1 = await engine.syncNow();
    expect(r1.skippedReason, 'offline');
    expect(await outbox.count(db.db, uid), 1);

    remote.offline = false;
    await engine.syncNow(force: true);
    expect(remote.table('transactions').containsKey(t.id), isTrue);
    expect(await outbox.count(db.db, uid), 0);
    expect((await repo.getById(t.id))!.syncStatus, SyncStatus.synced);
  });

  test('retry with backoff on server error, idempotent upsert', () async {
    final t = await repo.save(tx());
    remote.failNextUpserts = 1;
    final r = await engine.syncNow(force: true);
    expect(r.failed, 1);
    final e = await outbox.find(db.db, 'transactions', t.id);
    expect(e!.attempts, 1);
    expect(e.nextAttemptAt, greaterThan(DateTime.now().millisecondsSinceEpoch));

    // Không force -> chưa tới hạn retry.
    await engine.syncNow();
    expect(remote.table('transactions').containsKey(t.id), isFalse);

    await engine.syncNow(force: true);
    await engine.syncNow(force: true); // chạy lại không tạo bản ghi trùng
    expect(remote.table('transactions').length, 1);
    expect(await outbox.count(db.db, uid), 0);
  });

  test('photo upload fails -> metadata synced, row NOT marked synced, retried later', () async {
    final photo = await fakePhoto();
    final t = await repo.save(tx(photo: photo));
    remote.failUploads = true;
    await engine.syncNow(force: true);

    expect(remote.table('transactions').containsKey(t.id), isTrue); // metadata đã lên
    expect((await repo.getById(t.id))!.syncStatus, isNot(SyncStatus.synced));
    expect(await outbox.count(db.db, uid), 1);
    expect(File(photo).existsSync(), isTrue); // không xóa ảnh khi chưa upload

    remote.failUploads = false;
    await engine.syncNow(force: true);
    final after = (await repo.getById(t.id))!;
    expect(after.syncStatus, SyncStatus.synced);
    expect(after.remoteImagePath, '$uid/${t.id}.jpg');
    expect(remote.storage.containsKey('$uid/${t.id}.jpg'), isTrue);
    // Ảnh tạm được dọn sau khi đã lên cloud.
    expect(after.localImagePath, isNull);
    expect(File(photo).existsSync(), isFalse);
  });

  test('keepLocalPhotos = true keeps the local file', () async {
    keepPhotos = true;
    final photo = await fakePhoto();
    final t = await repo.save(tx(photo: photo));
    await engine.syncNow(force: true);
    expect((await repo.getById(t.id))!.localImagePath, photo);
    expect(File(photo).existsSync(), isTrue);
  });

  test('delete propagates as tombstone and local tombstone is purged', () async {
    final t = await repo.save(tx());
    await engine.syncNow(force: true);
    await repo.delete(t.id);
    await engine.syncNow(force: true);
    expect(remote.table('transactions')[t.id]!['deleted_at'], isNotNull);
    expect(await repo.getById(t.id), isNull); // đã dọn khỏi máy
    expect(await outbox.count(db.db, uid), 0);
  });

  test('pull: other device changes arrive; remote tombstone removes local', () async {
    final t = await repo.save(tx(name: 'A'));
    await engine.syncNow(force: true);

    final row = Map<String, dynamic>.of(remote.table('transactions')[t.id]!);
    final later = DateTime.now().toUtc().add(const Duration(minutes: 5));
    remote
        .serverWrite('transactions', {...row, 'name': 'B', 'updated_at': later.toIso8601String()});
    await engine.syncNow(force: true);
    expect((await repo.getById(t.id))!.name, 'B');

    remote.serverWrite('transactions', {
      ...row,
      'updated_at': later.add(const Duration(minutes: 1)).toIso8601String(),
      'deleted_at': later.toIso8601String(),
    });
    await engine.syncNow(force: true);
    expect(await repo.getById(t.id), isNull);
  });

  test('conflict: newer pending local edit is not overwritten by older remote', () async {
    final t = await repo.save(tx(name: 'Local v1'));
    await engine.syncNow(force: true);
    final row = Map<String, dynamic>.of(remote.table('transactions')[t.id]!);

    remote.offline = true;
    await repo.save((await repo.getById(t.id))!.copyWith(name: 'Local v2'));
    remote.offline = false;
    // Thiết bị khác ghi bản CŨ hơn.
    remote.serverWrite('transactions', {
      ...row,
      'name': 'Remote old',
      'updated_at': DateTime.utc(2020).toIso8601String(),
    });
    await engine.syncNow(force: true);
    expect((await repo.getById(t.id))!.name, 'Local v2');
    expect(remote.table('transactions')[t.id]!['name'], 'Local v2');
  });

  test('retention: old synced rows move to archive, balance unchanged', () async {
    retention = 30;
    final old =
        await repo.save(tx(minor: 1000, date: DateTime.now().subtract(const Duration(days: 90))));
    await repo.save(tx(minor: 500));
    final before = (await repo.ledger()).fold<int>(0, (a, e) => a + e.amountMinor);
    await engine.syncNow(force: true);
    expect(await repo.getById(old.id), isNull);
    expect(await repo.archivedCount(), 1);
    final after = (await repo.ledger()).fold<int>(0, (a, e) => a + e.amountMinor);
    expect(after, before);
  });

  test('new device pull: everything arrives (rehydrate)', () async {
    for (var i = 0; i < 5; i++) {
      final now = DateTime.now().toUtc();
      remote.serverWrite('transactions', {
        'id': Ids.newId(),
        'user_id': uid,
        'name': 'Remote $i',
        'amount_minor': 1000 + i,
        'type': 'expense',
        'category_id': null,
        'note': null,
        'transaction_date': now.toIso8601String(),
        'location_name': null,
        'latitude': null,
        'longitude': null,
        'image_path': null,
        'recurring_id': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'deleted_at': null,
      });
    }
    // Bản ghi của user khác không bao giờ được áp dụng.
    remote.serverWrite('transactions', {
      'id': Ids.newId(),
      'user_id': 'user-b',
      'name': 'Not mine',
      'amount_minor': 1,
      'type': 'expense',
      'transaction_date': DateTime.now().toUtc().toIso8601String(),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    final r = await engine.rehydrateFromCloud();
    expect(r.pulled, 5);
    expect((await repo.recent(limit: 100)).length, 5);
  });
  test('late bank import on 2nd phone does not overwrite photo/location from other phone',
      () async {
    // Máy khác đã nhập + gắn ảnh + vị trí nơi giao dịch, đẩy lên server.
    final id = Ids.newId();
    final posted = DateTime.now().toUtc().subtract(const Duration(hours: 1));
    remote.serverWrite('transactions', {
      'id': id,
      'user_id': uid,
      'name': 'Chuyển tiền',
      'amount_minor': 5000000,
      'type': 'expense',
      'category_id': null,
      'note': null,
      'transaction_date': posted.toIso8601String(),
      'location_name': 'Quán cà phê',
      'latitude': 10.5,
      'longitude': 106.5,
      'image_path': '$uid/$id.jpg',
      'recurring_id': null,
      'created_at': posted.toIso8601String(),
      'updated_at': posted.add(const Duration(minutes: 5)).toIso8601String(),
      'deleted_at': null,
    });

    // Máy này nhận thông báo muộn (updated_at mới hơn), đang ở nhà.
    final late = DateTime.now();
    await db.db.insert('bank_messages', {
      'id': 'msg-1',
      'tx_id': id,
      'direction': -1,
      'amount': 50000,
      'posted_at': late.millisecondsSinceEpoch,
    });
    await repo.importIfAbsent(FinanceTransaction(
      id: id,
      userId: uid,
      name: 'Chuyển tiền',
      amountMinor: 5000000,
      type: TxType.expense,
      date: posted.toLocal(),
      latitude: 21.0,
      longitude: 105.8,
      locationName: 'Nhà',
      createdAt: late,
      updatedAt: late,
    ));
    await engine.syncNow(force: true);

    final server = remote.table('transactions')[id]!;
    expect(server['image_path'], '$uid/$id.jpg');
    expect(server['location_name'], 'Quán cà phê');
    final local = (await repo.getById(id))!;
    expect(local.remoteImagePath, '$uid/$id.jpg');
    expect(local.locationName, 'Quán cà phê');
    expect(local.latitude, 10.5);
    expect(local.syncStatus, SyncStatus.synced);
    expect(await outbox.count(db.db, uid), 0);
  });

  test('bank import pushes normally when server has no copy yet', () async {
    final t = tx(name: 'Nhận tiền');
    await db.db.insert('bank_messages', {
      'id': 'msg-2',
      'tx_id': t.id,
      'direction': 1,
      'amount': 40000,
      'posted_at': t.date.millisecondsSinceEpoch,
    });
    await repo.importIfAbsent(t);
    await engine.syncNow(force: true);
    expect(remote.table('transactions')[t.id]!['name'], 'Nhận tiền');
    expect((await repo.getById(t.id))!.syncStatus, SyncStatus.synced);
  });
}
