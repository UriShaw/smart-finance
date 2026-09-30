import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';
import 'package:smart_finance/logic/data/repositories/transaction_repository.dart';
import 'package:smart_finance/logic/bank/bank_channel.dart';
import 'package:smart_finance/logic/bank/bank_importer.dart';

import 'helpers/fakes.dart';

class _FakeChannel extends BankChannel {
  final pending = <BankEvent>[];

  @override
  Future<List<BankEvent>> getPending() async => List.of(pending);

  @override
  Future<void> ackPending(List<String> ids) async => pending.removeWhere((e) => ids.contains(e.id));
}

BankEvent ev(String id, {double? lat, double? lng, Duration ago = Duration.zero}) => BankEvent(
      id: id,
      pkg: 'com.VCB',
      bank: 'Vietcombank',
      direction: -1,
      amount: 50000,
      balance: 950000 + id.hashCode % 1000,
      content: 'THANH TOAN',
      postedAt: DateTime.now().subtract(ago),
      lat: lat,
      lng: lng,
    );

void main() {
  late TransactionRepository txs;
  late _FakeChannel ch;
  var gpsCalls = 0;

  Future<BankImporter> importer({bool locate = true}) async {
    final db = await openTestDb();
    txs = TransactionRepository(database: db, events: DataEvents(), userId: () => 'u1');
    ch = _FakeChannel();
    gpsCalls = 0;
    return BankImporter(
      channel: ch,
      transactions: txs,
      userId: 'u1',
      categoryIdForKey: (_) async => null,
      labels: const BankLabels(incomeName: 'Nhận', expenseName: 'Chi', autoNote: '{bank}'),
      locate: locate
          ? () async {
              gpsCalls++;
              return (lat: 21.0285, lng: 105.8542);
            }
          : null,
      placeName: (lat, lng) async => 'Hoàn Kiếm, Hà Nội',
    );
  }

  Future<dynamic> only() async => (await txs.page(offset: 0, limit: 10)).single;

  test('thông báo đã kèm vị trí (điện thoại lấy lúc nhận) -> dùng luôn + tên địa điểm', () async {
    final imp = await importer();
    ch.pending.add(ev('a', lat: 10.7769, lng: 106.7009));
    await imp.importPending();
    final t = await only();
    expect(t.latitude, 10.7769);
    expect(t.longitude, 106.7009);
    expect(t.locationName, 'Hoàn Kiếm, Hà Nội');
    expect(gpsCalls, 0);
  });

  test('vừa nhận, chưa có vị trí, app đang mở -> lấy GPS ngay', () async {
    final imp = await importer();
    ch.pending.add(ev('b', ago: const Duration(seconds: 20)));
    await imp.importPending();
    expect((await only()).latitude, 21.0285);
    expect(gpsCalls, 1);
  });

  test('thông báo cũ (mở app sau 1 tiếng) -> không gắn vị trí hiện tại cho sai chỗ', () async {
    final imp = await importer();
    ch.pending.add(ev('c', ago: const Duration(hours: 1)));
    await imp.importPending();
    expect((await only()).latitude, isNull);
    expect(gpsCalls, 0);
  });

  test('tắt gắn vị trí -> không có vị trí dù thông báo có kèm', () async {
    final imp = await importer(locate: false);
    ch.pending.add(ev('d', lat: 10.7, lng: 106.7));
    await imp.importPending();
    expect((await only()).latitude, isNull);
  });

  test('BankEvent đọc lat/lng từ Android (int hoặc double)', () {
    final e = BankEvent.tryParse({
      'id': 'x',
      'amount': 5000,
      'direction': 1,
      'postedAt': 0,
      'lat': 10,
      'lng': 106.5,
    })!;
    expect(e.lat, 10.0);
    expect(e.lng, 106.5);
    expect(e.hasLocation, isTrue);
  });
}
