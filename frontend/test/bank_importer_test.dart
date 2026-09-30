import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/logic/domain/entities/common.dart';
import 'package:smart_finance/logic/bank/bank_channel.dart';
import 'package:smart_finance/logic/bank/bank_importer.dart';

void main() {
  const labels = BankLabels(
    incomeName: 'Nhận tiền',
    expenseName: 'Chi tiêu',
    autoNote: 'Tự động từ thông báo {bank}',
  );
  BankEvent ev({int dir = 1, String content = '', int amount = 500000}) => BankEvent(
        id: 'abc123',
        pkg: 'com.VCB',
        bank: 'Vietcombank',
        direction: dir,
        amount: amount,
        balance: 1000000,
        content: content,
        postedAt: DateTime(2026, 9, 23, 20, 15),
      );

  test('event -> transaction (income, deterministic id, amount x100)', () {
    final e = ev(content: 'LUONG THANG 9');
    final t = BankImporter.toTransaction(e, userId: 'u', categoryId: 'c', labels: labels);
    expect(t.type, TxType.income);
    expect(t.amountMinor, 50000000);
    expect(t.name, 'LUONG THANG 9');
    expect(t.note, 'Tự động từ thông báo Vietcombank');
    expect(t.date, DateTime(2026, 9, 23, 20, 15));
    expect(t.id, BankImporter.transactionId(e));
    expect(BankImporter.transactionId(ev()), BankImporter.transactionId(ev()));
  });

  test('empty content -> generic name with bank', () {
    final t =
        BankImporter.toTransaction(ev(dir: -1), userId: 'u', categoryId: null, labels: labels);
    expect(t.type, TxType.expense);
    expect(t.name, 'Chi tiêu · Vietcombank');
  });

  test('category guess respects income/expense', () {
    expect(BankImporter.guessCategoryKey(ev(content: 'lương tháng 9')), 'cat_salary');
    expect(BankImporter.guessCategoryKey(ev(dir: -1, content: 'cà phê sáng')), 'cat_food');
    // Từ khóa chi tiêu nhưng là tiền vào -> không gán nhầm danh mục chi.
    expect(BankImporter.guessCategoryKey(ev(content: 'tiền cà phê')), 'cat_other_income');
    expect(BankImporter.guessCategoryKey(ev(dir: -1)), 'cat_other_expense');
  });

  test('BankEvent.tryParse rejects malformed maps', () {
    expect(BankEvent.tryParse({'id': 'x', 'amount': 0, 'direction': 1}), isNull);
    expect(BankEvent.tryParse({'amount': 5, 'direction': 1}), isNull);
    final ok = BankEvent.tryParse({
      'id': 'x',
      'amount': 5000,
      'direction': -1,
      'bank': 'MB Bank',
      'postedAt': 0,
    });
    expect(ok!.isIncome, isFalse);
    expect(ok.balance, -1);
  });

  test('income with sender name -> name shows sender, content kept in note', () {
    final e = BankEvent(
      id: 'x2',
      pkg: 'com.VCB',
      bank: 'Vietcombank',
      direction: 1,
      amount: 150000,
      balance: -1,
      content: 'NGUYEN VAN A chuyen tien',
      sender: 'Nguyen Van A',
      postedAt: DateTime(2026, 9, 24, 8),
    );
    final t = BankImporter.toTransaction(e, userId: 'u', categoryId: null, labels: labels);
    expect(t.name, 'Nhận tiền · Nguyen Van A');
    expect(t.note, contains('NGUYEN VAN A chuyen tien'));
  });
}
