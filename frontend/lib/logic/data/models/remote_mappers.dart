import '../../../core/utils/date_x.dart';
import 'db_mappers.dart';

/// Tên entity dùng trong outbox + ánh xạ sang bảng local/remote.
enum SyncEntity {
  categories('categories', 'categories', 0),
  recurring('recurring_rules', 'recurring_transactions', 1),
  budgets('budgets', 'budgets', 2),
  transactions('transactions', 'transactions', 3);

  const SyncEntity(this.localTable, this.remoteTable, this.priority);

  final String localTable;
  final String remoteTable;

  /// Thứ tự đẩy: danh mục trước để khóa ngoại phía server hợp lệ.
  final int priority;

  static SyncEntity byLocalTable(String t) =>
      SyncEntity.values.firstWhere((e) => e.localTable == t);
}

String _iso(Object? msValue) =>
    DateTime.fromMillisecondsSinceEpoch(msValue as int, isUtc: true).toIso8601String();

String? _isoOrNull(Object? msValue) => msValue == null ? null : _iso(msValue);

int _ms(Object? iso) => DateTime.parse(iso as String).millisecondsSinceEpoch;

int? _msOrNull(Object? iso) => iso == null ? null : _ms(iso);

String _dateOnly(Object? msValue) => DateX.ymd(DateTime.fromMillisecondsSinceEpoch(msValue as int));

String? _dateOnlyOrNull(Object? msValue) => msValue == null ? null : _dateOnly(msValue);

/// 'YYYY-MM-DD' -> ms của 00:00 giờ địa phương.
int _msFromDate(Object? s) {
  final parts = (s as String).split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]).millisecondsSinceEpoch;
}

int? _msFromDateOrNull(Object? s) => s == null ? null : _msFromDate(s);

int _int(Object? v) => (v as num).toInt();

class RemoteMapper {
  const RemoteMapper._();

  /// Dòng SQLite -> payload gửi Supabase. Không gửi đường dẫn file local.
  static Map<String, dynamic> toRemote(SyncEntity e, DbRow r) {
    switch (e) {
      case SyncEntity.transactions:
        return {
          'id': r['id'],
          'user_id': r['user_id'],
          'name': r['name'],
          'amount_minor': r['amount_minor'],
          'type': r['type'],
          'category_id': r['category_id'],
          'note': r['note'],
          'transaction_date': _iso(r['transaction_date']),
          'location_name': r['location_name'],
          'latitude': r['latitude'],
          'longitude': r['longitude'],
          'image_path': r['remote_image_path'],
          'recurring_id': r['recurring_id'],
          'created_at': _iso(r['created_at']),
          'updated_at': _iso(r['updated_at']),
          'deleted_at': _isoOrNull(r['deleted_at']),
        };
      case SyncEntity.categories:
        return {
          'id': r['id'],
          'user_id': r['user_id'],
          'name': r['name'],
          'type': r['type'],
          'icon': r['icon'],
          'color': r['color'],
          'default_key': r['default_key'],
          'sort_order': r['sort_order'],
          'created_at': _iso(r['created_at']),
          'updated_at': _iso(r['updated_at']),
          'deleted_at': _isoOrNull(r['deleted_at']),
        };
      case SyncEntity.budgets:
        return {
          'id': r['id'],
          'user_id': r['user_id'],
          'category_id': r['category_id'],
          'period': r['period'],
          'limit_minor': r['limit_minor'],
          'warn_percent': r['warn_percent'],
          'created_at': _iso(r['created_at']),
          'updated_at': _iso(r['updated_at']),
          'deleted_at': _isoOrNull(r['deleted_at']),
        };
      case SyncEntity.recurring:
        return {
          'id': r['id'],
          'user_id': r['user_id'],
          'name': r['name'],
          'amount_minor': r['amount_minor'],
          'type': r['type'],
          'category_id': r['category_id'],
          'note': r['note'],
          'frequency': r['frequency'],
          'start_date': _dateOnly(r['start_date']),
          'end_date': _dateOnlyOrNull(r['end_date']),
          'next_run_date': _dateOnly(r['next_run_date']),
          'active': (r['active'] as int?) != 0,
          'created_at': _iso(r['created_at']),
          'updated_at': _iso(r['updated_at']),
          'deleted_at': _isoOrNull(r['deleted_at']),
        };
    }
  }

  /// Payload Supabase -> dòng SQLite (sync_status = synced).
  /// [existing] để giữ local_image_path nếu ảnh chưa được dọn.
  static DbRow toLocal(SyncEntity e, Map<String, dynamic> m, {DbRow? existing}) {
    switch (e) {
      case SyncEntity.transactions:
        final remoteImage = m['image_path'] as String?;
        final keepLocal = existing != null &&
            existing['local_image_path'] != null &&
            (remoteImage == null || remoteImage == existing['remote_image_path']);
        return {
          'id': m['id'],
          'user_id': m['user_id'],
          'name': m['name'],
          'amount_minor': _int(m['amount_minor']),
          'type': m['type'],
          'category_id': m['category_id'],
          'note': m['note'],
          'transaction_date': _ms(m['transaction_date']),
          'location_name': m['location_name'],
          'latitude': (m['latitude'] as num?)?.toDouble(),
          'longitude': (m['longitude'] as num?)?.toDouble(),
          'local_image_path': keepLocal ? existing['local_image_path'] : null,
          'remote_image_path': remoteImage,
          'recurring_id': m['recurring_id'],
          'created_at': _ms(m['created_at']),
          'updated_at': _ms(m['updated_at']),
          'deleted_at': _msOrNull(m['deleted_at']),
          'sync_status': 'synced',
        };
      case SyncEntity.categories:
        return {
          'id': m['id'],
          'user_id': m['user_id'],
          'name': m['name'] ?? '',
          'type': m['type'],
          'icon': m['icon'] ?? 'category',
          'color': _int(m['color'] ?? 0xFF90A4AE),
          'default_key': m['default_key'],
          'sort_order': _int(m['sort_order'] ?? 0),
          'created_at': _ms(m['created_at']),
          'updated_at': _ms(m['updated_at']),
          'deleted_at': _msOrNull(m['deleted_at']),
          'sync_status': 'synced',
        };
      case SyncEntity.budgets:
        return {
          'id': m['id'],
          'user_id': m['user_id'],
          'category_id': m['category_id'],
          'period': m['period'],
          'limit_minor': _int(m['limit_minor']),
          'warn_percent': _int(m['warn_percent'] ?? 80),
          'created_at': _ms(m['created_at']),
          'updated_at': _ms(m['updated_at']),
          'deleted_at': _msOrNull(m['deleted_at']),
          'sync_status': 'synced',
        };
      case SyncEntity.recurring:
        return {
          'id': m['id'],
          'user_id': m['user_id'],
          'name': m['name'],
          'amount_minor': _int(m['amount_minor']),
          'type': m['type'],
          'category_id': m['category_id'],
          'note': m['note'],
          'frequency': m['frequency'],
          'start_date': _msFromDate(m['start_date']),
          'end_date': _msFromDateOrNull(m['end_date']),
          'next_run_date': _msFromDate(m['next_run_date']),
          'active': m['active'] == true ? 1 : 0,
          'created_at': _ms(m['created_at']),
          'updated_at': _ms(m['updated_at']),
          'deleted_at': _msOrNull(m['deleted_at']),
          'sync_status': 'synced',
        };
    }
  }
}
