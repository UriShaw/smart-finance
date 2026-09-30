import 'dart:async';

/// Bus sự kiện dữ liệu: repository báo "có ghi local" -> Sync Engine đẩy lên cloud,
/// và UI được làm mới (revision tăng).
class DataEvents {
  final _localWrites = StreamController<void>.broadcast();
  final _revisions = StreamController<int>.broadcast();
  int _revision = 0;

  Stream<void> get localWrites => _localWrites.stream;
  Stream<int> get revisions => _revisions.stream;
  int get revision => _revision;

  /// Người dùng vừa ghi dữ liệu local (cần đồng bộ).
  void localWrite() {
    if (!_localWrites.isClosed) _localWrites.add(null);
    bump();
  }

  /// Dữ liệu đổi do sync/pull/dọn dẹp - chỉ cần làm mới UI.
  void bump() {
    _revision++;
    if (!_revisions.isClosed) _revisions.add(_revision);
  }

  Future<void> dispose() async {
    await _localWrites.close();
    await _revisions.close();
  }
}
