enum TxType {
  income,
  expense;

  static TxType parse(String? s) => s == 'income' ? income : expense;
}

enum SyncStatus {
  pending,
  synced,
  failed;

  static SyncStatus parse(String? s) =>
      SyncStatus.values.firstWhere((e) => e.name == s, orElse: () => pending);
}

/// Sentinel cho copyWith để phân biệt "không đổi" và "gán null".
const Object keep = _Keep();

class _Keep {
  const _Keep();
}

T? pick<T>(Object? value, T? current) => identical(value, keep) ? current : value as T?;
