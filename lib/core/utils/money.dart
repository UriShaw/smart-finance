import 'package:intl/intl.dart';

/// Tiền tệ hiển thị. Số tiền luôn lưu dạng số nguyên "minor units" = giá trị x100
/// (DEC-006) để tránh sai số dấu phẩy động và thống nhất giữa các loại tiền.
class Currency {
  const Currency(this.code, this.symbol, this.decimals);

  final String code;
  final String symbol;
  final int decimals;

  static const vnd = Currency('VND', '₫', 0);
  static const usd = Currency('USD', r'$', 2);
  static const eur = Currency('EUR', '€', 2);
  static const cny = Currency('CNY', '¥', 2);
  static const twd = Currency('TWD', r'NT$', 0);
  static const jpy = Currency('JPY', '¥', 0);

  static const List<Currency> all = [vnd, usd, eur, cny, twd, jpy];

  static Currency byCode(String? code) => all.firstWhere((c) => c.code == code, orElse: () => vnd);
}

class Money {
  const Money._();

  /// minor (x100) -> chuỗi hiển thị theo locale.
  static String format(int minor, Currency c, {String? locale, bool signed = false}) {
    final value = minor / 100.0;
    final f = NumberFormat.currency(
      locale: locale,
      name: c.code,
      symbol: c.symbol,
      decimalDigits: c.decimals,
    );
    final s = f.format(value.abs());
    if (!signed) return value < 0 ? '-$s' : s;
    return value < 0 ? '-$s' : '+$s';
  }

  /// Dạng rút gọn cho biểu đồ: 1,2 tr / 350 N / 1.5M ...
  static String compact(int minor, {String? locale}) {
    final f = NumberFormat.compact(locale: locale);
    return f.format(minor / 100.0);
  }

  /// Chuỗi người dùng nhập -> minor units. Trả null nếu không hợp lệ hoặc <= 0.
  ///
  /// Chấp nhận: "50000", "50.000", "50,000", "12.5", "12,50", "1.234,56".
  static int? parse(String input, Currency c) {
    var s = input.trim().replaceAll(RegExp(r'[\s₫$€¥]'), '');
    s = s.replaceAll(RegExp(r'[A-Za-z]'), '');
    if (s.isEmpty) return null;
    if (!RegExp(r'^[0-9.,]+$').hasMatch(s)) return null;

    String intPart;
    String fracPart = '';

    if (c.decimals == 0) {
      intPart = s.replaceAll(RegExp(r'[.,]'), '');
    } else {
      final lastDot = s.lastIndexOf('.');
      final lastComma = s.lastIndexOf(',');
      final lastSep = lastDot > lastComma ? lastDot : lastComma;
      if (lastSep < 0) {
        intPart = s;
      } else {
        final tail = s.substring(lastSep + 1);
        final bothUsed = lastDot >= 0 && lastComma >= 0;
        if (bothUsed || (tail.isNotEmpty && tail.length <= 2)) {
          intPart = s.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
          fracPart = tail;
        } else {
          intPart = s.replaceAll(RegExp(r'[.,]'), '');
        }
      }
    }
    if (intPart.isEmpty) intPart = '0';
    if (intPart.length > 13) return null; // chặn số quá lớn
    final whole = int.tryParse(intPart);
    if (whole == null) return null;
    final frac = fracPart.isEmpty ? 0 : int.parse(fracPart.padRight(2, '0'));
    final minor = whole * 100 + frac;
    return minor > 0 ? minor : null;
  }

  /// minor -> chuỗi để điền lại vào ô nhập khi sửa.
  static String toInput(int minor, Currency c) {
    if (c.decimals == 0) return (minor ~/ 100).toString();
    final whole = minor ~/ 100;
    final frac = minor % 100;
    return frac == 0 ? '$whole' : '$whole.${frac.toString().padLeft(2, '0')}';
  }
}
