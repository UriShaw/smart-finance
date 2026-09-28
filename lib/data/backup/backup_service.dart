import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/config/env.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_error.dart';
import '../../core/storage/app_database.dart';
import '../../domain/entities/finance_transaction.dart';
import '../local/entity_dao.dart';
import '../local/outbox_dao.dart';
import '../models/db_mappers.dart';
import '../repositories/data_events.dart';

class ImportReport {
  const ImportReport({
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.invalid = 0,
  });

  final int inserted;
  final int updated;
  final int skipped;
  final int invalid;

  int get total => inserted + updated + skipped + invalid;
}

/// Backup / Restore / Export (spec Q).
/// File JSON có version, schema_version, exported_at, user, checksum SHA-256.
/// Import có validation và không tạo duplicate (so theo id + updated_at).
class BackupService {
  BackupService({
    required this.database,
    required this.events,
    required this.userId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final DataEvents events;
  final String Function() userId;
  final DateTime Function() _clock;

  static const _outbox = OutboxDao();

  /// Bảng -> cột bắt buộc để validate.
  static const Map<String, List<String>> _required = {
    'categories': ['id', 'name', 'type', 'icon', 'color', 'created_at', 'updated_at'],
    'transactions': [
      'id',
      'name',
      'amount_minor',
      'type',
      'transaction_date',
      'created_at',
      'updated_at',
    ],
    'budgets': ['id', 'period', 'limit_minor', 'created_at', 'updated_at'],
    'recurring_rules': [
      'id',
      'name',
      'amount_minor',
      'type',
      'frequency',
      'start_date',
      'next_run_date',
      'created_at',
      'updated_at',
    ],
  };

  Db get _db => database.db;

  static String _checksum(Map<String, dynamic> data) =>
      sha256.convert(utf8.encode(jsonEncode(data))).toString();

  Future<String> exportJson() async {
    final uid = userId();
    final data = <String, dynamic>{};
    for (final table in _required.keys) {
      final rows = await _db.query(table,
          where: 'user_id = ? AND deleted_at IS NULL', whereArgs: [uid], orderBy: 'created_at');
      data[table] = rows.map((r) {
        final m = Map<String, Object?>.of(r)
          ..remove('user_id')
          ..remove('sync_status')
          ..remove('local_image_path');
        return m;
      }).toList();
    }
    final archived = await _db.query('tx_archive', where: 'user_id = ?', whereArgs: [uid]);
    data['tx_archive'] = archived.map((r) {
      final m = Map<String, Object?>.of(r)..remove('user_id');
      return m;
    }).toList();

    final doc = {
      'format': AppConstants.backupFormat,
      'version': AppConstants.backupFormatVersion,
      'schema_version': AppConstants.dbSchemaVersion,
      'app_version': Env.appVersion,
      'exported_at': _clock().toUtc().toIso8601String(),
      'user': uid == AppConstants.localUserId ? 'local' : uid,
      'counts': {for (final e in data.entries) e.key: (e.value as List).length},
      'checksum': _checksum(data),
      'data': data,
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Future<ImportReport> importJson(String content) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const AppError(AppErrorType.validation, detail: 'backup_not_json');
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != AppConstants.backupFormat) {
      throw const AppError(AppErrorType.validation, detail: 'backup_format');
    }
    final schema = decoded['schema_version'];
    if (schema is! int || schema > AppConstants.dbSchemaVersion) {
      throw const AppError(AppErrorType.validation, detail: 'backup_schema');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppError(AppErrorType.validation, detail: 'backup_data');
    }
    if (decoded['checksum'] != _checksum(data)) {
      throw const AppError(AppErrorType.validation, detail: 'backup_checksum');
    }

    final uid = userId();
    final nowMs = ms(_clock());
    var inserted = 0, updated = 0, skipped = 0, invalid = 0;

    await _db.transaction((txn) async {
      // Thứ tự: danh mục trước.
      for (final table in _required.keys) {
        final list = data[table];
        if (list is! List) continue;
        final dao = EntityDao(table);
        final cols = (await txn.rawQuery('PRAGMA table_info($table)'))
            .map((r) => r['name'] as String)
            .toSet();
        for (final item in list) {
          if (item is! Map<String, dynamic> || !_valid(table, item)) {
            invalid++;
            continue;
          }
          final row = Map<String, Object?>.of(item)
            ..['user_id'] = uid
            ..['sync_status'] = 'pending'
            ..['deleted_at'] = null;
          if (table == 'transactions') row['local_image_path'] = null;
          row.removeWhere((k, _) => !cols.contains(k));
          final existing = await dao.getRaw(txn, row['id'] as String);
          if (existing != null) {
            if (existing['user_id'] != uid) {
              invalid++;
              continue;
            }
            final exUpdated = existing['updated_at'] as int;
            if (exUpdated >= (row['updated_at'] as int) && existing['deleted_at'] == null) {
              skipped++;
              continue;
            }
            // Bản import mới hơn -> cập nhật, đóng dấu updated_at mới để thắng LWW.
            row['updated_at'] = nowMs;
            await dao.upsertRaw(txn, row);
            updated++;
          } else {
            await dao.upsertRaw(txn, row);
            inserted++;
          }
          await _outbox.enqueue(txn,
              entity: table, entityId: row['id'] as String, userId: uid, op: 'upsert');
        }
      }
      final arch = data['tx_archive'];
      if (arch is List) {
        for (final a in arch) {
          if (a is! Map<String, dynamic> || a['id'] is! String) continue;
          final exists = await txn.query('transactions',
              columns: ['id'], where: 'id = ?', whereArgs: [a['id']], limit: 1);
          if (exists.isNotEmpty) continue;
          await txn.rawInsert(
            'INSERT OR IGNORE INTO tx_archive (id, user_id, type, amount_minor, transaction_date, category_id) '
            'VALUES (?, ?, ?, ?, ?, ?)',
            [a['id'], uid, a['type'], a['amount_minor'], a['transaction_date'], a['category_id']],
          );
        }
      }
    });
    events.localWrite();
    return ImportReport(inserted: inserted, updated: updated, skipped: skipped, invalid: invalid);
  }

  bool _valid(String table, Map<String, dynamic> m) {
    for (final k in _required[table]!) {
      if (m[k] == null) return false;
    }
    if (m['id'] is! String || (m['id'] as String).length < 8) return false;
    if (m.containsKey('amount_minor')) {
      final a = m['amount_minor'];
      if (a is! int || a <= 0) return false;
    }
    if (m.containsKey('limit_minor')) {
      final a = m['limit_minor'];
      if (a is! int || a <= 0) return false;
    }
    if (m.containsKey('type') && m['type'] != 'income' && m['type'] != 'expense') {
      return false;
    }
    for (final k in ['created_at', 'updated_at', 'transaction_date']) {
      if (m.containsKey(k) && m[k] is! int) return false;
    }
    return true;
  }

  /// CSV (UTF-8 BOM để Excel đọc đúng tiếng Việt).
  static String toCsv(
    List<FinanceTransaction> txs, {
    required String Function(String? categoryId) categoryName,
    required int decimals,
  }) {
    final b = StringBuffer('﻿');
    b.writeln('id,date,name,type,amount,category,note,location,latitude,longitude');
    for (final t in txs) {
      final amount = decimals == 0
          ? (t.amountMinor ~/ 100).toString()
          : (t.amountMinor / 100).toStringAsFixed(2);
      b.writeln([
        t.id,
        t.date.toIso8601String(),
        t.name,
        t.type.name,
        amount,
        categoryName(t.categoryId),
        t.note ?? '',
        t.locationName ?? '',
        t.latitude?.toString() ?? '',
        t.longitude?.toString() ?? '',
      ].map(_csvCell).join(','));
    }
    return b.toString();
  }

  static String _csvCell(String v) {
    // Chống CSV injection khi mở bằng Excel.
    var s = v;
    if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      s = '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }
}
