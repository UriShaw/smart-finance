import 'common.dart';

class TxCategory {
  const TxCategory({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.defaultKey,
    this.sortOrder = 0,
    this.deletedAt,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String userId;

  /// Với danh mục mặc định chưa đổi tên, [name] rỗng và UI hiển thị theo
  /// localization của [defaultKey].
  final String name;
  final TxType type;
  final String icon;
  final int color;
  final String? defaultKey;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  TxCategory copyWith({
    String? userId,
    String? name,
    TxType? type,
    String? icon,
    int? color,
    int? sortOrder,
    DateTime? updatedAt,
    Object? deletedAt = keep,
    SyncStatus? syncStatus,
  }) {
    return TxCategory(
      id: id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      defaultKey: defaultKey,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: pick<DateTime>(deletedAt, this.deletedAt),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

/// Danh mục mặc định: key localization, loại, icon, màu.
class DefaultCategory {
  const DefaultCategory(this.key, this.type, this.icon, this.color);
  final String key;
  final TxType type;
  final String icon;
  final int color;

  static const List<DefaultCategory> all = [
    DefaultCategory('cat_food', TxType.expense, 'restaurant', 0xFFFF9F43),
    DefaultCategory('cat_transport', TxType.expense, 'directions_car', 0xFF3D7BFF),
    DefaultCategory('cat_shopping', TxType.expense, 'shopping_bag', 0xFFFF4FD8),
    DefaultCategory('cat_bills', TxType.expense, 'receipt_long', 0xFFFFC940),
    DefaultCategory('cat_entertainment', TxType.expense, 'movie', 0xFF7C4DFF),
    DefaultCategory('cat_health', TxType.expense, 'favorite', 0xFFFF3D71),
    DefaultCategory('cat_education', TxType.expense, 'school', 0xFF00D2FF),
    DefaultCategory('cat_home', TxType.expense, 'home', 0xFF8D6E63),
    DefaultCategory('cat_other_expense', TxType.expense, 'category', 0xFF90A4AE),
    DefaultCategory('cat_salary', TxType.income, 'payments', 0xFF00C48C),
    DefaultCategory('cat_bonus', TxType.income, 'card_giftcard', 0xFF00E5A0),
    DefaultCategory('cat_investment', TxType.income, 'trending_up', 0xFF0EA5E9),
    DefaultCategory('cat_other_income', TxType.income, 'savings', 0xFF84CC16),
  ];
}
