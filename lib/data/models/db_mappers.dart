import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';

typedef DbRow = Map<String, Object?>;

int ms(DateTime d) => d.millisecondsSinceEpoch;
int? msOrNull(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime fromMs(Object? v) => DateTime.fromMillisecondsSinceEpoch(v as int);
DateTime? fromMsOrNull(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);
double? toDouble(Object? v) => v == null ? null : (v as num).toDouble();

class TxMapper {
  const TxMapper._();

  static DbRow toRow(FinanceTransaction t) => {
        'id': t.id,
        'user_id': t.userId,
        'name': t.name,
        'amount_minor': t.amountMinor,
        'type': t.type.name,
        'category_id': t.categoryId,
        'note': t.note,
        'transaction_date': ms(t.date),
        'location_name': t.locationName,
        'latitude': t.latitude,
        'longitude': t.longitude,
        'local_image_path': t.localImagePath,
        'remote_image_path': t.remoteImagePath,
        'recurring_id': t.recurringId,
        'created_at': ms(t.createdAt),
        'updated_at': ms(t.updatedAt),
        'deleted_at': msOrNull(t.deletedAt),
        'sync_status': t.syncStatus.name,
      };

  static FinanceTransaction fromRow(DbRow r) => FinanceTransaction(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        name: r['name'] as String,
        amountMinor: r['amount_minor'] as int,
        type: TxType.parse(r['type'] as String?),
        categoryId: r['category_id'] as String?,
        note: r['note'] as String?,
        date: fromMs(r['transaction_date']),
        locationName: r['location_name'] as String?,
        latitude: toDouble(r['latitude']),
        longitude: toDouble(r['longitude']),
        localImagePath: r['local_image_path'] as String?,
        remoteImagePath: r['remote_image_path'] as String?,
        recurringId: r['recurring_id'] as String?,
        createdAt: fromMs(r['created_at']),
        updatedAt: fromMs(r['updated_at']),
        deletedAt: fromMsOrNull(r['deleted_at']),
        syncStatus: SyncStatus.parse(r['sync_status'] as String?),
      );

  static LedgerEntry ledgerFromRow(DbRow r) => LedgerEntry(
        id: r['id'] as String,
        type: TxType.parse(r['type'] as String?),
        amountMinor: r['amount_minor'] as int,
        date: fromMs(r['transaction_date']),
        categoryId: r['category_id'] as String?,
      );
}

class CategoryMapper {
  const CategoryMapper._();

  static DbRow toRow(TxCategory c) => {
        'id': c.id,
        'user_id': c.userId,
        'name': c.name,
        'type': c.type.name,
        'icon': c.icon,
        'color': c.color,
        'default_key': c.defaultKey,
        'sort_order': c.sortOrder,
        'created_at': ms(c.createdAt),
        'updated_at': ms(c.updatedAt),
        'deleted_at': msOrNull(c.deletedAt),
        'sync_status': c.syncStatus.name,
      };

  static TxCategory fromRow(DbRow r) => TxCategory(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        name: r['name'] as String,
        type: TxType.parse(r['type'] as String?),
        icon: r['icon'] as String,
        color: r['color'] as int,
        defaultKey: r['default_key'] as String?,
        sortOrder: (r['sort_order'] as int?) ?? 0,
        createdAt: fromMs(r['created_at']),
        updatedAt: fromMs(r['updated_at']),
        deletedAt: fromMsOrNull(r['deleted_at']),
        syncStatus: SyncStatus.parse(r['sync_status'] as String?),
      );
}
