import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/utils/date_x.dart';
import 'package:smart_finance/core/utils/ids.dart';
import 'package:smart_finance/core/utils/money.dart';
import 'package:smart_finance/logic/domain/entities/common.dart';
import 'package:smart_finance/logic/domain/entities/finance_transaction.dart';
import 'package:smart_finance/logic/domain/usecases/balance_calculator.dart';
import 'package:smart_finance/logic/domain/usecases/conflict_resolver.dart';
import 'package:smart_finance/logic/domain/usecases/category_guesser.dart';
import 'package:smart_finance/logic/domain/usecases/statistics_aggregator.dart';

LedgerEntry e(TxType t, int vnd, DateTime d, [String? cat]) =>
    LedgerEntry(id: Ids.newId(), type: t, amountMinor: vnd * 100, date: d, categoryId: cat);

void main() {
  group('Money', () {
    test('parse VND (0 decimals)', () {
      expect(Money.parse('50000', Currency.vnd), 5000000);
      expect(Money.parse('50.000', Currency.vnd), 5000000);
      expect(Money.parse('1,250,000', Currency.vnd), 125000000);
      expect(Money.parse('0', Currency.vnd), isNull);
      expect(Money.parse('abc', Currency.vnd), isNull);
      expect(Money.parse('', Currency.vnd), isNull);
    });

    test('parse USD (2 decimals)', () {
      expect(Money.parse('12.5', Currency.usd), 1250);
      expect(Money.parse('12,50', Currency.usd), 1250);
      expect(Money.parse('1,234.56', Currency.usd), 123456);
      expect(Money.parse('1.234,56', Currency.usd), 123456);
      expect(Money.parse('1,000', Currency.usd), 100000);
    });

    test('toInput round-trip', () {
      expect(Money.toInput(5000000, Currency.vnd), '50000');
      expect(Money.toInput(1250, Currency.usd), '12.50');
      expect(Money.toInput(1200, Currency.usd), '12');
    });
  });

  group('Balance calculation', () {
    test('income - expense', () {
      final d = DateTime(2026, 1, 1);
      final s = BalanceCalculator.summarize([
        e(TxType.income, 10000000, d),
        e(TxType.expense, 250000, d),
        e(TxType.expense, 50000, d),
      ]);
      expect(s.incomeMinor, 1000000000);
      expect(s.expenseMinor, 30000000);
      expect(s.balanceMinor, 970000000);
    });

    test('empty ledger', () {
      expect(BalanceCalculator.summarize(const []).balanceMinor, 0);
    });
  });

  group('Conflict resolution', () {
    final t1 = DateTime.utc(2026, 1, 1, 10);
    final t2 = DateTime.utc(2026, 1, 1, 11);
    test('no pending local -> take remote', () {
      expect(
          ConflictResolver.resolve(
              localUpdatedAt: t2,
              localPending: false,
              localDeleted: false,
              remoteUpdatedAt: t1,
              remoteDeleted: false),
          ConflictDecision.takeRemote);
    });
    test('pending newer local wins', () {
      expect(
          ConflictResolver.resolve(
              localUpdatedAt: t2,
              localPending: true,
              localDeleted: false,
              remoteUpdatedAt: t1,
              remoteDeleted: false),
          ConflictDecision.keepLocal);
    });
    test('remote newer wins over pending local', () {
      expect(
          ConflictResolver.resolve(
              localUpdatedAt: t1,
              localPending: true,
              localDeleted: false,
              remoteUpdatedAt: t2,
              remoteDeleted: false),
          ConflictDecision.takeRemote);
    });
    test('tie: local tombstone wins', () {
      expect(
          ConflictResolver.resolve(
              localUpdatedAt: t1,
              localPending: true,
              localDeleted: true,
              remoteUpdatedAt: t1,
              remoteDeleted: false),
          ConflictDecision.keepLocal);
    });
  });

  group('Statistics', () {
    test('month buckets by day + category breakdown', () {
      final (s, end) = StatisticsAggregator.rangeFor(StatPeriod.month, DateTime(2026, 2, 10));
      expect(DateX.daysInMonth(2026, 2), 28);
      final r = StatisticsAggregator.aggregate([
        e(TxType.expense, 100, DateTime(2026, 2, 1), 'a'),
        e(TxType.expense, 300, DateTime(2026, 2, 28, 22), 'b'),
        e(TxType.income, 1000, DateTime(2026, 2, 5)),
        e(TxType.expense, 999, DateTime(2026, 3, 1), 'a'),
      ], s, end);
      expect(r.buckets.length, 28);
      expect(r.expenseMinor, 40000);
      expect(r.incomeMinor, 100000);
      expect(r.buckets.last.expenseMinor, 30000);
      expect(r.expenseByCategory.first.categoryId, 'b');
      expect(r.expenseByCategory.first.ratio, closeTo(0.75, 1e-9));
      expect(r.count, 3);
    });

    test('year uses month buckets', () {
      final (s, end) = StatisticsAggregator.rangeFor(StatPeriod.year, DateTime(2026, 6, 1));
      final r = StatisticsAggregator.aggregate([], s, end);
      expect(r.bucketUnit, BucketUnit.month);
      expect(r.buckets.length, 12);
    });

    test('lịch: chênh lệch thu - chi theo ngày, ngày trống không có', () {
      final m = StatisticsAggregator.dailyNet([
        e(TxType.expense, 10, DateTime(2026, 4, 3, 8)),
        e(TxType.expense, 20, DateTime(2026, 4, 3, 20)),
        e(TxType.income, 50, DateTime(2026, 4, 3)),
        e(TxType.expense, 70, DateTime(2026, 4, 5)),
        e(TxType.income, 90, DateTime(2026, 5, 1)),
      ], 2026, 4);
      expect(m, {3: 2000, 5: -7000});
    });

    test('rút gọn có dấu cho ô lịch', () {
      expect(Money.shortSigned(15000000, locale: 'vi'), '+150k');
      expect(Money.shortSigned(-4550000, locale: 'vi'), '−45,5k');
      expect(Money.shortSigned(120000000, locale: 'vi'), '+1,2tr');
      expect(Money.shortSigned(-200000000000, locale: 'vi'), '−2tỷ');
      expect(Money.shortSigned(120000000, locale: 'en'), '+1.2M');
      expect(Money.shortSigned(50000, locale: 'vi'), '+500');
      expect(Money.shortSigned(0, locale: 'vi'), '0');
    });
  });

  group('Category guesser', () {
    test('nhận ra danh mục từ nội dung chuyển khoản', () {
      expect(CategoryGuesser.guessKey('Ăn phở sáng'), 'cat_food');
      expect(CategoryGuesser.guessKey('THANH TOAN GRAB'), 'cat_transport');
      expect(CategoryGuesser.guessKey('LUONG THANG 9'), 'cat_salary');
      expect(CategoryGuesser.guessKey('tiền điện tháng 9'), 'cat_bills');
    });

    test('không nhầm từ nằm trong từ khác, không rõ thì null', () {
      expect(CategoryGuesser.guessKey('chuyen khoan'), isNull);
      expect(CategoryGuesser.guessKey('MB 123456'), isNull);
    });
  });
}
