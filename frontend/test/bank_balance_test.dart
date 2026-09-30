import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/logic/data/repositories/bank_message_repository.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';

import 'helpers/fakes.dart';

BankMessage msg(String id, String bank, String acc, int dir, int amount, int balance, int minute) =>
    BankMessage(
      id: id,
      txId: 'tx-$id',
      pkg: 'com.bank',
      bank: bank,
      account: acc,
      title: 'Biến động số dư',
      body: 'TK $acc ${dir > 0 ? '+' : '-'}$amount VND. SD $balance VND',
      direction: dir,
      amount: amount,
      balance: balance,
      postedAt: DateTime(2026, 9, 27, 10, minute),
    );

void main() {
  late AppDatabase db;
  late BankMessageRepository repo;

  setUp(() async {
    db = await openTestDb();
    repo = BankMessageRepository(db, DataEvents());
  });

  tearDown(() => db.close());

  test('balance follows the latest bank-reported balance, not a computed sum', () async {
    await repo.save(msg('1', 'VCB', '7890', 1, 500000, 1500000, 0));
    await repo.save(msg('2', 'VCB', '7890', -1, 200000, 1300000, 5));
    final b = await repo.balances();
    expect(b, hasLength(1));
    expect(b.first.balance, 1300000);
    expect(b.first.fromNotification, isTrue);
  });

  test('later notification without balance adjusts by amount', () async {
    await repo.save(msg('1', 'MB', '3789', 1, 100000, 900000, 0));
    await repo.save(msg('2', 'MB', '', -1, 50000, -1, 3)); // không ghi TK, không ghi số dư
    final b = await repo.balances();
    expect(b.single.balance, 850000);
    expect(b.single.fromNotification, isFalse);
  });

  test('separate accounts and banks are summed separately', () async {
    await repo.save(msg('1', 'VCB', '7890', 1, 1, 1000000, 0));
    await repo.save(msg('2', 'VCB', '1111', 1, 1, 2000000, 1));
    await repo.save(msg('3', 'MB', '3789', 1, 1, 500000, 2));
    // Không rõ TK nào của VCB -> bỏ qua thay vì đoán.
    await repo.save(msg('4', 'VCB', '', -1, 300000, -1, 3));
    final b = await repo.balances();
    expect(b.fold<int>(0, (a, e) => a + e.balance), 3500000);
  });

  test('original message is found by transaction id; duplicate ids ignored', () async {
    await repo.save(msg('1', 'VCB', '7890', 1, 500000, 1500000, 0));
    await repo.save(msg('1', 'VCB', '7890', 1, 500000, 1500000, 0));
    final m = await repo.byTransaction('tx-1');
    expect(m, isNotNull);
    expect(m!.body, contains('SD 1500000'));
    expect(await repo.deleteAll(), 1);
    expect(await repo.balances(), isEmpty);
  });
}
