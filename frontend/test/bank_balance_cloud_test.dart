import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/logic/bank/bank_balance_cloud.dart';
import 'package:smart_finance/logic/data/repositories/bank_message_repository.dart';

AccountBalance bal(String bank, String acc, int balance, DateTime at, {bool exact = true}) =>
    AccountBalance(
      bank: bank,
      account: acc,
      balance: balance,
      updatedAt: at,
      fromNotification: exact,
    );

void main() {
  final t0 = DateTime(2026, 9, 30, 9, 20);

  test('metadata round-trip keeps bank, account, balance, time, exact flag', () {
    final list = [bal('MB Bank', '9393', 3998756, t0), bal('VCB', '', 120000, t0, exact: false)];
    final back =
        BankBalanceCloud.fromMetadata({BankBalanceCloud.key: BankBalanceCloud.toMetadata(list)});
    expect(back.length, 2);
    expect(back[0].label, 'MB Bank ••9393');
    expect(back[0].balance, 3998756);
    expect(back[0].updatedAt.isAtSameMomentAs(t0), isTrue);
    expect(back[1].fromNotification, isFalse);
  });

  test('missing or malformed metadata -> empty, never throws', () {
    expect(BankBalanceCloud.fromMetadata(null), isEmpty);
    expect(BankBalanceCloud.fromMetadata({'full_name': 'A'}), isEmpty);
    expect(
      BankBalanceCloud.fromMetadata({
        BankBalanceCloud.key: [
          'rác',
          {'bank': 'MB', 'balance': 'x', 'updated_at': 'y'},
        ],
      }),
      isEmpty,
    );
  });

  test('merge: same account -> newer wins; different accounts kept; newest first', () {
    final cloud = [bal('MB Bank', '9393', 100, t0), bal('VCB', '11', 50, t0)];
    final local = [bal('mb bank', '9393', 600, t0.add(const Duration(minutes: 5)))];
    final merged = BankBalanceCloud.merge(cloud, local);
    expect(merged.length, 2);
    expect(merged.first.balance, 600);
    expect(merged.last.bank, 'VCB');
  });

  test('merge: older phone data does not overwrite newer cloud balance', () {
    final cloud = [bal('MB Bank', '9393', 900, t0)];
    final local = [bal('MB Bank', '9393', 100, t0.subtract(const Duration(hours: 1)))];
    expect(BankBalanceCloud.merge(cloud, local).single.balance, 900);
  });
}
