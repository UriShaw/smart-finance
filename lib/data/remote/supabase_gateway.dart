import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/constants/app_constants.dart';
import '../../domain/repositories/remote_gateway.dart';

class SupabaseGateway implements RemoteGateway {
  SupabaseGateway(this._client);

  final sb.SupabaseClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<void> upsert(String table, Map<String, dynamic> row) async {
    await _client.from(table).upsert(row, onConflict: 'id').timeout(_timeout);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table, {
    required String userId,
    required String? since,
    required int limit,
  }) async {
    final base = _client.from(table).select().eq('user_id', userId);
    final filtered = since == null ? base : base.gt('server_updated_at', since);
    final res =
        await filtered.order('server_updated_at', ascending: true).limit(limit).timeout(_timeout);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTransactionsBefore({
    required String userId,
    required DateTime before,
    required int limit,
  }) async {
    final res = await _client
        .from('transactions')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .lt('transaction_date', before.toUtc().toIso8601String())
        .order('transaction_date', ascending: false)
        .limit(limit)
        .timeout(_timeout);
    return List<Map<String, dynamic>>.from(res);
  }

  @override
  Future<String> uploadPhoto(String path, Uint8List bytes) async {
    await _client.storage
        .from(AppConstants.storageBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const sb.FileOptions(upsert: true, contentType: 'image/jpeg'),
        )
        .timeout(const Duration(seconds: 60));
    return path;
  }

  @override
  Future<void> deletePhoto(String path) async {
    await _client.storage.from(AppConstants.storageBucket).remove([path]).timeout(_timeout);
  }

  @override
  Future<String> signedPhotoUrl(String path) {
    return _client.storage
        .from(AppConstants.storageBucket)
        .createSignedUrl(path, 3600)
        .timeout(_timeout);
  }

  @override
  Future<bool> ping() async {
    try {
      await _client.from('profiles').select('id').limit(1).timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    }
  }
}
