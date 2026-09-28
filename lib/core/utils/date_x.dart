/// Tiện ích ngày tháng thuần Dart (dễ test).
class DateX {
  const DateX._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  /// Tuần bắt đầu từ thứ Hai.
  static DateTime startOfWeek(DateTime d) {
    final s = startOfDay(d);
    return s.subtract(Duration(days: s.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
