import '../../core/utils/date_x.dart';
import '../entities/common.dart';
import '../entities/finance_transaction.dart';

enum StatPeriod { day, week, month, year, custom }

enum BucketUnit { day, month }

class StatBucket {
  const StatBucket(this.start, this.incomeMinor, this.expenseMinor);
  final DateTime start;
  final int incomeMinor;
  final int expenseMinor;
}

class CategorySlice {
  const CategorySlice(this.categoryId, this.amountMinor, this.ratio);
  final String? categoryId;
  final int amountMinor;
  final double ratio;
}

class StatisticsResult {
  const StatisticsResult({
    required this.start,
    required this.end,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.buckets,
    required this.bucketUnit,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.count,
  });

  final DateTime start;
  final DateTime end;
  final int incomeMinor;
  final int expenseMinor;
  final List<StatBucket> buckets;
  final BucketUnit bucketUnit;
  final List<CategorySlice> expenseByCategory;
  final List<CategorySlice> incomeByCategory;
  final int count;

  int get netMinor => incomeMinor - expenseMinor;
}

class StatisticsAggregator {
  const StatisticsAggregator._();

  /// [start, end) cho kỳ chứa [anchor].
  static (DateTime, DateTime) rangeFor(StatPeriod p, DateTime anchor,
      {DateTime? customStart, DateTime? customEnd}) {
    switch (p) {
      case StatPeriod.day:
        final s = DateX.startOfDay(anchor);
        return (s, DateX.nextDay(s));
      case StatPeriod.week:
        final s = DateX.startOfWeek(anchor);
        return (s, DateTime(s.year, s.month, s.day + 7));
      case StatPeriod.month:
        return (DateX.startOfMonth(anchor), DateX.startOfNextMonth(anchor));
      case StatPeriod.year:
        return (DateTime(anchor.year), DateTime(anchor.year + 1));
      case StatPeriod.custom:
        final s = DateX.startOfDay(customStart ?? anchor);
        final e = DateX.nextDay(customEnd ?? anchor);
        return (s, e);
    }
  }

  static StatisticsResult aggregate(
    Iterable<LedgerEntry> entries,
    DateTime start,
    DateTime end,
  ) {
    final days = end.difference(start).inDays;
    final unit = days > 62 ? BucketUnit.month : BucketUnit.day;

    final bucketStarts = <DateTime>[];
    var c = unit == BucketUnit.day ? start : DateX.startOfMonth(start);
    while (c.isBefore(end)) {
      bucketStarts.add(c);
      c = unit == BucketUnit.day ? DateX.nextDay(c) : DateX.startOfNextMonth(c);
    }
    final inc = List<int>.filled(bucketStarts.length, 0);
    final exp = List<int>.filled(bucketStarts.length, 0);
    final expCat = <String?, int>{};
    final incCat = <String?, int>{};
    var income = 0;
    var expense = 0;
    var count = 0;

    for (final e in entries) {
      if (e.date.isBefore(start) || !e.date.isBefore(end)) continue;
      count++;
      int safeIdx = -1;
      if (bucketStarts.isNotEmpty) {
        final idx = unit == BucketUnit.day
            ? _dayIndex(start, e.date)
            : (e.date.year - bucketStarts.first.year) * 12 +
                e.date.month -
                bucketStarts.first.month;
        safeIdx = idx < 0 ? 0 : (idx >= bucketStarts.length ? bucketStarts.length - 1 : idx);
      }
      if (e.type == TxType.income) {
        income += e.amountMinor;
        incCat[e.categoryId] = (incCat[e.categoryId] ?? 0) + e.amountMinor;
        if (safeIdx >= 0) inc[safeIdx] += e.amountMinor;
      } else {
        expense += e.amountMinor;
        expCat[e.categoryId] = (expCat[e.categoryId] ?? 0) + e.amountMinor;
        if (safeIdx >= 0) exp[safeIdx] += e.amountMinor;
      }
    }

    List<CategorySlice> slices(Map<String?, int> m, int total) {
      final list = m.entries
          .map((e) => CategorySlice(e.key, e.value, total == 0 ? 0 : e.value / total))
          .toList()
        ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
      return list;
    }

    return StatisticsResult(
      start: start,
      end: end,
      incomeMinor: income,
      expenseMinor: expense,
      buckets: [
        for (var i = 0; i < bucketStarts.length; i++) StatBucket(bucketStarts[i], inc[i], exp[i]),
      ],
      bucketUnit: unit,
      expenseByCategory: slices(expCat, expense),
      incomeByCategory: slices(incCat, income),
      count: count,
    );
  }

  /// Chỉ số ngày tính theo lịch (tránh lệch do giờ mùa hè / DST).
  static int _dayIndex(DateTime start, DateTime d) {
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(d.year, d.month, d.day);
    return b.difference(a).inDays;
  }

  /// Chênh lệch thu - chi theo ngày trong tháng (lịch). Chỉ có ngày có giao dịch.
  static Map<int, int> dailyNet(Iterable<LedgerEntry> entries, int year, int month) {
    final out = <int, int>{};
    for (final e in entries) {
      if (e.date.year != year || e.date.month != month) continue;
      final signed = e.type == TxType.income ? e.amountMinor : -e.amountMinor;
      out[e.date.day] = (out[e.date.day] ?? 0) + signed;
    }
    return out;
  }
}
