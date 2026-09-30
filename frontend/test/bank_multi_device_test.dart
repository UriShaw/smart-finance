import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/logic/data/repositories/bank_message_repository.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';
import 'package:smart_finance/logic/data/repositories/transaction_repository.dart';
import 'package:smart_finance/logic/bank/bank_channel.dart';
import 'package:smart_finance/logic/bank/bank_importer.dart';

import 'helpers/fakes.dart';

/// Hàng chờ thông báo giả (thay cho Android).
class _FakeChannel extends BankChannel {
  final pending = <BankEvent>[];

  @override
  Future<List<BankEvent>> getPending() async => List.of(pending);

  @override
  Future<void> ackPending(List<String> ids) async => pending.removeWhere((e) => ids.contains(e.id));
}

/// Một điện thoại: DB riêng + bộ nhập riêng, cùng tài khoản 'u1'.
class _Phone {
  _Phone._(this.channel, this.txs, this.msgs, this.importer);

  static Future<_Phone> create({AppDatabase? db, String userId = 'u1'}) async {
    db ??= await openTestDb();
    final events = DataEvents();
    final txs = TransactionRepository(database: db, events: events, userId: () => userId);
    final msgs = BankMessageRepository(db, events);
    final ch = _FakeChannel();
    final importer = BankImporter(
      channel: ch,
      transactions: txs,
      messages: msgs,
      userId: userId,
      categoryIdForKey: (_) async => null,
      labels: const BankLabels(incomeName: 'Nhận', expenseName: 'Chi', autoNote: '{bank}'),
    );
    return _Phone._(ch, txs, msgs, importer);
  }

  final _FakeChannel channel;
  final TransactionRepository txs;
  final BankMessageRepository msgs;
  final BankImporter importer;

  Future<int> receive(BankEvent e) {
    channel.pending.add(e);
    return importer.importPending();
  }

  Future<List<String>> ids() async =>
      (await txs.page(offset: 0, limit: 100)).map((t) => t.id).toList()..sort();

  /// Mô phỏng đồng bộ: kéo mọi giao dịch của máy kia về (upsert theo id).
  Future<void> pullFrom(_Phone other) async {
    for (final t in await other.txs.page(offset: 0, limit: 100)) {
      await txs.importIfAbsent(t);
    }
  }
}

/// Mỗi máy tự sinh id thông báo khác nhau (id native gồm cả thời điểm nhận).
BankEvent ev(String id, {int dir = -1, int amount = 50000, int balance = 950000, int minute = 0}) =>
    BankEvent(
      id: id,
      pkg: 'com.VCB',
      bank: 'Vietcombank',
      direction: dir,
      amount: amount,
      balance: balance,
      content: 'THANH TOAN',
      postedAt: DateTime(2026, 9, 28, 10, minute),
    );

void main() {
  late _Phone a;
  late _Phone b;

  setUp(() async {
    a = await _Phone.create();
    b = await _Phone.create();
  });

  test('máy B nhận chậm sau khi đã đồng bộ -> không tạo giao dịch mới, vẫn có tin gốc', () async {
    expect(await a.receive(ev('a1')), 1);
    await b.pullFrom(a);
    expect(await b.receive(ev('b1', minute: 4)), 0);
    expect(await b.ids(), await a.ids());
    final id = (await b.ids()).single;
    expect((await b.msgs.byTransaction(id))?.id, 'b1');
  });

  test('hai máy cùng nhập trước khi đồng bộ -> cùng mã, đồng bộ xong vẫn 1 giao dịch', () async {
    await a.receive(ev('a1'));
    await b.receive(ev('b1', minute: 1));
    expect(await a.ids(), await b.ids());
    await b.pullFrom(a);
    expect((await b.ids()).length, 1);
  });

  test('giao dịch thật lặp lại cùng số tiền + cùng số dư (A-B-A) không bị gộp', () async {
    // +50k -> 1.000.000; -50k -> 950.000; +50k -> 1.000.000 (trùng dấu vân tay với lần 1).
    await a.receive(ev('a1', dir: 1, balance: 1000000, minute: 0));
    await a.receive(ev('a2', dir: -1, balance: 950000, minute: 5));
    await a.receive(ev('a3', dir: 1, balance: 1000000, minute: 10));
    expect((await a.ids()).length, 3);

    // B đồng bộ trước rồi mới nhận đủ 3 thông báo (chậm) -> vẫn đúng 3.
    await b.pullFrom(a);
    await b.receive(ev('b1', dir: 1, balance: 1000000, minute: 2));
    await b.receive(ev('b2', dir: -1, balance: 950000, minute: 7));
    await b.receive(ev('b3', dir: 1, balance: 1000000, minute: 12));
    expect(await b.ids(), await a.ids());

    // Máy C chưa đồng bộ gì cũng ra đúng 3 mã giống hệt.
    final c = await _Phone.create();
    await c.receive(ev('c1', dir: 1, balance: 1000000, minute: 1));
    await c.receive(ev('c2', dir: -1, balance: 950000, minute: 6));
    await c.receive(ev('c3', dir: 1, balance: 1000000, minute: 11));
    expect(await c.ids(), await a.ids());
  });

  test('nhập lại cùng một thông báo (ack lỗi) không nhân đôi', () async {
    await a.receive(ev('a1'));
    expect(await a.receive(ev('a1')), 0);
    expect((await a.ids()).length, 1);
  });

  test('không có số dư: quá 30 phút coi là giao dịch khác', () async {
    await a.receive(ev('a1', balance: -1, minute: 0));
    await b.pullFrom(a);
    expect(await b.receive(ev('b1', balance: -1, minute: 20)), 0); // trong 30 phút -> trùng
    expect(await b.receive(ev('b2', balance: -1, minute: 59)), 1); // giao dịch mới
    expect((await b.ids()).length, 2);
  });

  test('giao dịch người dùng đã xoá không bị máy nhận chậm tạo lại', () async {
    await a.receive(ev('a1'));
    final id = (await a.ids()).single;
    await a.txs.delete(id);
    // B nhận bản đã xoá (tombstone) qua đồng bộ.
    final tomb = (await a.txs.getById(id))!;
    expect(tomb.deletedAt, isNotNull);
    await b.txs.importIfAbsent(tomb);
    expect(await b.receive(ev('b1', minute: 3)), 0);
    expect(await b.ids(), isEmpty);
  });

  test('2 tài khoản trên cùng 1 máy: mã khác nhau, số dư tính riêng', () async {
    final db = await openTestDb();
    final u1 = await _Phone.create(db: db, userId: 'u1');
    final u2 = await _Phone.create(db: db, userId: 'u2');
    expect(await u1.receive(ev('x1', balance: 900000)), 1);
    // Cùng nội dung thông báo nhưng đang mở tài khoản u2 -> giao dịch riêng của u2.
    expect(await u2.receive(ev('x2', balance: 900000, minute: 1)), 1);
    final id1 = (await u1.ids()).single;
    final id2 = (await u2.ids()).single;
    expect(id1, isNot(id2));
    expect((await u1.msgs.balances(userId: 'u1')).single.balance, 900000);
    await u2.receive(ev('x3', balance: 700000, minute: 2, amount: 200000));
    expect((await u1.msgs.balances(userId: 'u1')).single.balance, 900000);
    expect((await u2.msgs.balances(userId: 'u2')).single.balance, 700000);
  });
}
