import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/constants/app_constants.dart';
import 'package:smart_finance/core/errors/app_error.dart';
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/core/utils/ids.dart';
import 'package:smart_finance/data/local/outbox_dao.dart';
import 'package:smart_finance/data/repositories/category_repository.dart';
import 'package:smart_finance/data/repositories/data_events.dart';
import 'package:smart_finance/data/repositories/local_data_claimer.dart';
import 'package:smart_finance/data/repositories/transaction_repository.dart';
import 'package:smart_finance/domain/entities/common.dart';
import 'package:smart_finance/domain/entities/finance_transaction.dart';

import 'helpers/fakes.dart';

FinanceTransaction newTx({
  String name = 'Phở',
  int minor = 5000000,
  TxType type = TxType.expense,
  DateTime? date,
  String userId = 'u1',
}) {
  final now = DateTime.now();
  return FinanceTransaction(
    id: Ids.newId(),
    userId: userId,
    name: name,
    amountMinor: minor,
    type: type,
    date: date ?? now,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late DataEvents events;
  late TransactionRepository repo;
  const outbox = OutboxDao();

  setUp(() async {
    db = await openTestDb();
    events = DataEvents();
    repo = TransactionRepository(database: db, events: events, userId: () => 'u1');
  });

  tearDown(() async {
    await db.close();
  });

  test('offline create: saved locally + queued in outbox', () async {
    final t = await repo.save(newTx());
    final got = await repo.getById(t.id);
    expect(got, isNotNull);
    expect(got!.syncStatus, SyncStatus.pending);
    expect(await outbox.count(db.db, 'u1'), 1);
  });

  test('edit coalesces into one outbox entry, bumps revision', () async {
    final t = await repo.save(newTx());
    await repo.save(t.copyWith(name: 'Bún bò', amountMinor: 6000000));
    final entries = await outbox.due(db.db, 'u1', DateTime.now().millisecondsSinceEpoch);
    expect(entries.length, 1);
    expect(entries.single.revision, 2);
    expect((await repo.getById(t.id))!.name, 'Bún bò');
  });

  test('offline delete uses tombstone (soft delete)', () async {
    final t = await repo.save(newTx());
    await repo.delete(t.id);
    final got = await repo.getById(t.id);
    expect(got!.deletedAt, isNotNull);
    expect(await repo.recent(), isEmpty);
    final e = await outbox.find(db.db, 'transactions', t.id);
    expect(e!.op, 'delete');
  });

  test('validation rejects empty name / zero amount / half coordinates', () async {
    expect(() => repo.save(newTx(name: '  ')), throwsA(isA<AppError>()));
    expect(() => repo.save(newTx(minor: 0)), throwsA(isA<AppError>()));
    expect(() => repo.save(newTx().copyWith(latitude: 10.0)), throwsA(isA<AppError>()));
  });

  test('search / filter / pagination', () async {
    for (var i = 0; i < 45; i++) {
      await repo.save(newTx(
        name: i.isEven ? 'Cà phê $i' : 'Lương $i',
        type: i.isEven ? TxType.expense : TxType.income,
        date: DateTime(2026, 1, 1).add(Duration(hours: i)),
      ));
    }
    final p1 = await repo.page(offset: 0, limit: 30);
    final p2 = await repo.page(offset: 30, limit: 30);
    expect(p1.length, 30);
    expect(p2.length, 15);
    expect(p1.first.date.isAfter(p1.last.date), isTrue);
    final incomes =
        await repo.page(offset: 0, limit: 100, query: const TxQuery(type: TxType.income));
    expect(incomes.length, 22);
    final search = await repo.page(offset: 0, limit: 100, query: const TxQuery(search: 'Cà phê 1'));
    expect(search.every((t) => t.name.startsWith('Cà phê 1')), isTrue);
  });

  test('ledger includes archived rows (balance correct after cleanup)', () async {
    await repo.save(newTx(minor: 100, type: TxType.income));
    await db.db.insert('tx_archive', {
      'id': 'old-1',
      'user_id': 'u1',
      'type': 'income',
      'amount_minor': 900,
      'transaction_date': DateTime(2020).millisecondsSinceEpoch,
      'category_id': null,
    });
    final ledger = await repo.ledger();
    expect(ledger.fold<int>(0, (a, e) => a + e.signedAmount), 1000);
  });

  test('default categories are deterministic and seeded once', () async {
    final cats = CategoryRepository(database: db, events: events, userId: () => 'u1');
    await cats.ensureDefaults();
    await cats.ensureDefaults();
    final list = await cats.list();
    expect(list.length, 13);
    expect(list.any((c) => c.id == Ids.defaultCategory('u1', 'cat_food')), isTrue);
  });

  test('claim local data moves offline records to the signed-in user', () async {
    final local =
        TransactionRepository(database: db, events: events, userId: () => AppConstants.localUserId);
    final cats =
        CategoryRepository(database: db, events: events, userId: () => AppConstants.localUserId);
    await cats.ensureDefaults();
    final food = Ids.defaultCategory(AppConstants.localUserId, 'cat_food');
    final t = await local.save(newTx(userId: AppConstants.localUserId).copyWith(categoryId: food));

    await LocalDataClaimer(db, events).claim('real-user');

    final moved =
        await TransactionRepository(database: db, events: events, userId: () => 'real-user')
            .getById(t.id);
    expect(moved!.userId, 'real-user');
    expect(moved.categoryId, Ids.defaultCategory('real-user', 'cat_food'));
    expect(await outbox.count(db.db, AppConstants.localUserId), 0);
    expect(await outbox.count(db.db, 'real-user'), greaterThan(0));
  });
}
