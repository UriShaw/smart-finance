import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:smart_finance/core/storage/app_database.dart';
import 'package:smart_finance/core/storage/file_paths.dart';
import 'package:smart_finance/logic/domain/repositories/remote_gateway.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Backend giả lập Supabase (trong bộ nhớ) cho test Sync Engine.
class FakeRemoteGateway implements RemoteGateway {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final Map<String, Uint8List> storage = {};
  int _clock = 0;

  /// Số lần upsert tiếp theo sẽ ném lỗi (giả lập lỗi server).
  int failNextUpserts = 0;
  bool offline = false;
  bool failUploads = false;
  int upsertCalls = 0;
  int uploadCalls = 0;

  String _stamp() {
    _clock++;
    return DateTime.utc(2030, 1, 1).add(Duration(milliseconds: _clock)).toIso8601String();
  }

  Map<String, Map<String, dynamic>> table(String t) => tables.putIfAbsent(t, () => {});

  /// Ghi trực tiếp như thể thiết bị khác vừa đồng bộ.
  void serverWrite(String t, Map<String, dynamic> row) {
    table(t)[row['id'] as String] = {...row, 'server_updated_at': _stamp()};
  }

  @override
  Future<void> upsert(String t, Map<String, dynamic> row) async {
    upsertCalls++;
    if (offline) throw const SocketException('offline');
    if (failNextUpserts > 0) {
      failNextUpserts--;
      throw Exception('server error');
    }
    table(t)[row['id'] as String] = {...row, 'server_updated_at': _stamp()};
  }

  @override
  Future<Map<String, dynamic>?> insertIfAbsent(String t, Map<String, dynamic> row) async {
    upsertCalls++;
    if (offline) throw const SocketException('offline');
    final id = row['id'] as String;
    table(t).putIfAbsent(id, () => {...row, 'server_updated_at': _stamp()});
    return Map<String, dynamic>.of(table(t)[id]!);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(String t,
      {required String userId, required String? since, required int limit}) async {
    if (offline) throw const SocketException('offline');
    final rows = table(t)
        .values
        .where((r) => r['user_id'] == userId)
        .where((r) => since == null || (r['server_updated_at'] as String).compareTo(since) > 0)
        .toList()
      ..sort(
          (a, b) => (a['server_updated_at'] as String).compareTo(b['server_updated_at'] as String));
    return rows.take(limit).map((e) => Map<String, dynamic>.of(e)).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactionsBefore(
      {required String userId, required DateTime before, required int limit}) async {
    final rows = table('transactions')
        .values
        .where((r) => r['user_id'] == userId && r['deleted_at'] == null)
        .where((r) => DateTime.parse(r['transaction_date'] as String).isBefore(before))
        .toList();
    return rows.take(limit).toList();
  }

  @override
  Future<String> uploadPhoto(String path, Uint8List bytes) async {
    uploadCalls++;
    if (offline) throw const SocketException('offline');
    if (failUploads) throw Exception('storage error');
    storage[path] = bytes;
    return path;
  }

  @override
  Future<void> deletePhoto(String path) async {
    storage.remove(path);
  }

  @override
  Future<String> signedPhotoUrl(String path) async => 'https://example.test/$path';

  @override
  Future<bool> ping() async => !offline;
}

/// DB SQLite trong bộ nhớ (FFI, không isolate) + thư mục tạm cho ảnh.
Future<AppDatabase> openTestDb() async {
  sqfliteFfiInit();
  final tmp = await Directory.systemTemp.createTemp('sf_test_');
  FilePaths.overrideForTest(tmp);
  // File riêng mỗi test (in-memory của sqflite dùng chung 1 instance).
  return AppDatabase.open(
    path: p.join(tmp.path, 'test.db'),
    factory: databaseFactoryFfiNoIsolate,
  );
}
