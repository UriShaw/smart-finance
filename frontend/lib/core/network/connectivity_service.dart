import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Trạng thái mạng. Không crash nếu plugin không hỗ trợ nền tảng (spec E).
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity}) : _c = connectivity ?? Connectivity();

  final Connectivity _c;

  static bool _online(List<ConnectivityResult> r) => r.any((e) => e != ConnectivityResult.none);

  Future<bool> isOnline() async {
    try {
      return _online(await _c.checkConnectivity());
    } catch (_) {
      return true; // Không xác định được -> thử, lỗi mạng sẽ được xử lý ở tầng sync.
    }
  }

  Stream<bool> get onlineChanges {
    try {
      return _c.onConnectivityChanged.map(_online).distinct();
    } catch (_) {
      return const Stream<bool>.empty();
    }
  }
}
