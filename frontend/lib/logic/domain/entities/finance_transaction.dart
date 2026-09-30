import 'common.dart';

/// Giao dịch thu/chi. [amountMinor] = số tiền x100, luôn > 0; dấu do [type] quyết định.
class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.userId,
    required this.name,
    required this.amountMinor,
    required this.type,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.note,
    this.locationName,
    this.latitude,
    this.longitude,
    this.localImagePath,
    this.remoteImagePath,
    this.recurringId,
    this.deletedAt,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String userId;
  final String name;
  final int amountMinor;
  final TxType type;
  final String? categoryId;
  final String? note;
  final DateTime date;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final String? localImagePath;
  final String? remoteImagePath;
  final String? recurringId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  bool get isIncome => type == TxType.income;
  bool get hasPhoto => localImagePath != null || remoteImagePath != null;
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Giá trị có dấu: thu dương, chi âm.
  int get signedAmount => isIncome ? amountMinor : -amountMinor;

  FinanceTransaction copyWith({
    String? userId,
    String? name,
    int? amountMinor,
    TxType? type,
    Object? categoryId = keep,
    Object? note = keep,
    DateTime? date,
    Object? locationName = keep,
    Object? latitude = keep,
    Object? longitude = keep,
    Object? localImagePath = keep,
    Object? remoteImagePath = keep,
    Object? recurringId = keep,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? deletedAt = keep,
    SyncStatus? syncStatus,
  }) {
    return FinanceTransaction(
      id: id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      amountMinor: amountMinor ?? this.amountMinor,
      type: type ?? this.type,
      categoryId: pick<String>(categoryId, this.categoryId),
      note: pick<String>(note, this.note),
      date: date ?? this.date,
      locationName: pick<String>(locationName, this.locationName),
      latitude: pick<double>(latitude, this.latitude),
      longitude: pick<double>(longitude, this.longitude),
      localImagePath: pick<String>(localImagePath, this.localImagePath),
      remoteImagePath: pick<String>(remoteImagePath, this.remoteImagePath),
      recurringId: pick<String>(recurringId, this.recurringId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: pick<DateTime>(deletedAt, this.deletedAt),
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

/// Bản ghi rút gọn dùng cho tính toán số dư/thống kê
/// (gồm cả giao dịch đã lưu trữ khỏi máy - xem tx_archive).
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.date,
    this.categoryId,
  });

  final String id;
  final TxType type;
  final int amountMinor;
  final DateTime date;
  final String? categoryId;

  int get signedAmount => type == TxType.income ? amountMinor : -amountMinor;
}
