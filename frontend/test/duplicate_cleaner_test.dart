import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/logic/data/repositories/bank_message_repository.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';
import 'package:smart_finance/logic/data/repositories/duplicate_cleaner.dart';
import 'package:smart_finance/logic/data/repositories/transaction_repository.dart';
import 'package:smart_finance/logic/domain/entities/common.dart';
import 'package:smart_finance/logic/domain/entities/finance_transaction.dart';

import 'helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late TransactionRepository repo;
  late BankMessageRepository msgs;
  late DuplicateCleaner cleaner;
  final t0 = DateTime(2026, 9, 29, 10, 15, 20);

  setUp(() async {
    db = await openTestDb();
    final events = DataEvents();
    repo = TransactionRepository(database: db, events: events, userId: () => 'u1');
    msgs = BankMessageRepository(db, events);
    cleaner = DuplicateCleaner(database: db, transactions: repo);
  });

  Future<void> add(
    String id, {
    int seconds = 0,
    int amount = 5000000,
    TxType type = TxType.expense,
    bool photo = false,
  }) =>
      repo.save(
        FinanceTransaction(
          id: id,
          userId: 'u1',
          name: 'THANH TOAN',
          amountMinor: amount,
          type: type,
          date: t0.add(Duration(seconds: seconds)),
          localImagePath: photo ? 'moment_$id.jpg' : null,
          createdAt: t0,
          updatedAt: t0,
        ),
      );

  Future<void> msg(String id, String txId, int balance) => msgs.save(
        BankMessage(
          id: id,
          txId: txId,
          pkg: 'com.VCB',
          bank: 'Vietcombank',
          account: '',
          title: 'VCB',
          body: '-50,000 VND. SD $balance',
          direction: -1,
          amount: 50000,
          balance: balance,
          postedAt: t0,
        ),
      );

  Future<List<String>> alive() async =>
      (await repo.page(offset: 0, limit: 100)).map((t) => t.id).toList()..sort();

  test('2 máy cùng nhận: giữ bản có ảnh, xoá bản chưa có ảnh', () async {
    await add('b-phone-b', seconds: 4);
    await add('a-phone-a', photo: true);
    expect(await cleaner.run(), 1);
    expect(await alive(), ['a-phone-a']);
  });

  test('không ảnh: giữ bản sớm hơn (mọi máy chọn giống nhau)', () async {
    await add('zzz', seconds: 0);
    await add('aaa', seconds: 12);
    expect(await cleaner.run(), 1);
    expect(await alive(), ['zzz']);
  });

  test('lệch hơn 60 giây, khác số tiền, khác loại -> không phải trùng', () async {
    await add('x1');
    await add('x2', seconds: 61);
    await add('x3', seconds: 5, amount: 7000000);
    await add('x4', seconds: 5, type: TxType.income);
    expect(await cleaner.run(), 0);
    expect((await alive()).length, 4);
  });

  test('máy này tự nhận 2 thông báo khác số dư -> 2 giao dịch thật, giữ cả hai', () async {
    await add('g1');
    await add('g2', seconds: 20);
    await msg('m1', 'g1', 950000);
    await msg('m2', 'g2', 900000);
    expect(await cleaner.run(), 0);
    expect((await alive()).length, 2);
  });

  test('tin nhắn gốc của bản bị xoá chuyển sang bản giữ lại (số dư không mất)', () async {
    await add('keep', photo: true);
    await add('drop', seconds: 3);
    await msg('m-drop', 'drop', 950000);
    await cleaner.run();
    expect((await msgs.byTransaction('keep'))?.id, 'm-drop');
    expect((await msgs.balances(userId: 'u1')).single.balance, 950000);
  });

  test('chạy lại không xoá thêm', () async {
    await add('a', photo: true);
    await add('b', seconds: 1);
    expect(await cleaner.run(), 1);
    expect(await cleaner.run(), 0);
  });
}
