/// Đoán danh mục mặc định từ nội dung chuyển khoản (thông báo ngân hàng), chạy offline.
/// VD: "THANH TOAN GRAB" -> cat_transport, "LUONG THANG 9" -> cat_salary.
class CategoryGuesser {
  const CategoryGuesser._();

  static const _l = r'\p{L}';

  /// Từ khoá theo danh mục, ngăn cách bằng '|'.
  static final Map<String, List<String>> _keywords = {
    for (final e in const {
      'cat_salary': 'lương|luong|salary',
      'cat_bonus': 'thưởng|thuong|bonus|lì xì|li xi',
      'cat_investment': 'lãi|cổ tức|đầu tư|dau tu|chứng khoán',
      'cat_food':
          'ăn|an sang|phở|pho|cơm|com|bún|bun|cafe|cà phê|ca phe|trà sữa|tra sua|nhậu|bánh|uống|lẩu|food|coffee|lunch|dinner',
      'cat_transport': 'xăng|xang|grab|taxi|gửi xe|vé xe|xe buýt|bus|be|gojek|đổ xăng|gas',
      'cat_bills':
          'điện|tiền điện|nước|internet|wifi|tiền nhà|thuê nhà|hóa đơn|hoa don|cước|điện thoại|bill',
      'cat_shopping': 'mua|quần|áo|giày|shopee|lazada|tiki|siêu thị|shopping',
      'cat_entertainment': 'phim|game|du lịch|karaoke|netflix',
      'cat_health': 'thuốc|bệnh viện|khám|nha khoa|gym',
      'cat_education': 'học phí|sách|khóa học|học|course',
    }.entries)
      e.key: e.value.split('|'),
  };

  static bool _hasWord(String text, String word) {
    final re =
        RegExp('(^|[^$_l])${RegExp.escape(word)}(\$|[^$_l])', unicode: true, caseSensitive: false);
    return re.hasMatch(text);
  }

  /// Khóa danh mục mặc định (vd. 'cat_food') hoặc null nếu không nhận ra.
  static String? guessKey(String text) {
    final lower = text.toLowerCase();
    for (final e in _keywords.entries) {
      if (e.value.any((w) => _hasWord(lower, w))) return e.key;
    }
    return null;
  }
}
