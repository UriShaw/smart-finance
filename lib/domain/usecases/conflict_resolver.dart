/// Chính sách xung đột (DEC-007): Last-Write-Wins theo `updated_at` của client,
/// có bảo vệ thay đổi local chưa đồng bộ.
///
/// - Local không có thay đổi chờ đẩy       -> luôn nhận bản remote.
/// - Local đang pending và mới hơn/bằng   -> giữ local (sẽ được đẩy lên sau).
///   (Bằng nhau thường là "tiếng vọng" của chính lần đẩy trước, ví dụ khi
///   metadata đã lên nhưng ảnh chưa upload xong -> không được mất outbox.)
/// - Local pending nhưng remote mới hơn   -> nhận remote, bỏ thay đổi local.
///
/// Giới hạn: phụ thuộc đồng hồ thiết bị. Server lưu thêm `server_updated_at`
/// để làm con trỏ pull, không dùng để so sánh LWW.
enum ConflictDecision { takeRemote, keepLocal }

class ConflictResolver {
  const ConflictResolver._();

  static ConflictDecision resolve({
    required DateTime localUpdatedAt,
    required bool localPending,
    required bool localDeleted,
    required DateTime remoteUpdatedAt,
    required bool remoteDeleted,
  }) {
    if (!localPending) return ConflictDecision.takeRemote;
    if (!localUpdatedAt.isBefore(remoteUpdatedAt)) {
      return ConflictDecision.keepLocal;
    }
    return ConflictDecision.takeRemote;
  }
}
