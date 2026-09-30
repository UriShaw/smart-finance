import 'dart:typed_data';

/// Hợp đồng giữa Sync Engine và backend. Supabase là 1 implementation;
/// test dùng FakeRemoteGateway. UI không bao giờ gọi trực tiếp lớp này.
abstract class RemoteGateway {
  /// Upsert idempotent theo `id` (UUID client-generated).
  Future<void> upsert(String table, Map<String, dynamic> row);

  /// Chỉ thêm nếu server chưa có `id` này (không ghi đè). Trả về bản đang có trên
  /// server sau đó (bản vừa thêm hoặc bản cũ), null nếu không đọc được.
  Future<Map<String, dynamic>?> insertIfAbsent(String table, Map<String, dynamic> row);

  /// Lấy các bản ghi có server_updated_at > [since] (ISO) - tăng dần.
  Future<List<Map<String, dynamic>>> fetchChanges(
    String table, {
    required String userId,
    required String? since,
    required int limit,
  });

  /// Giao dịch đầy đủ cũ hơn [before] (cho "tải thêm từ cloud").
  Future<List<Map<String, dynamic>>> fetchTransactionsBefore({
    required String userId,
    required DateTime before,
    required int limit,
  });

  /// Upload ảnh (upsert). Trả về storage path.
  Future<String> uploadPhoto(String path, Uint8List bytes);

  Future<void> deletePhoto(String path);

  Future<String> signedPhotoUrl(String path);

  /// Kiểm tra backend thật sự truy cập được (không chỉ có mạng).
  Future<bool> ping();
}
