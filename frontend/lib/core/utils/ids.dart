import 'package:uuid/uuid.dart';

/// UUID sinh ở client để đảm bảo idempotency khi đồng bộ (spec H).
class Ids {
  const Ids._();

  static const Uuid _uuid = Uuid();

  /// Namespace URL chuẩn RFC 4122.
  static const String _ns = '6ba7b811-9dad-11d1-80b4-00c04fd430c8';

  static String newId() => _uuid.v4();

  /// UUID xác định (v5) - cùng input luôn ra cùng id trên mọi thiết bị.
  /// Dùng cho danh mục mặc định và giao dịch ngân hàng để chống trùng.
  static String deterministic(String name) => _uuid.v5(_ns, name);

  static String defaultCategory(String userId, String key) =>
      deterministic('smart-finance/$userId/category/$key');
}
