import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_service.dart';
import '../../core/storage/app_database.dart';
import '../../data/repositories/data_events.dart';

/// Được override trong main() sau khi mở DB.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('override in main()'),
);

final dataEventsProvider = Provider<DataEvents>((ref) {
  final e = DataEvents();
  ref.onDispose(e.dispose);
  return e;
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

final onlineProvider = StreamProvider<bool>((ref) async* {
  final svc = ref.watch(connectivityServiceProvider);
  yield await svc.isOnline();
  yield* svc.onlineChanges;
});

/// Tăng mỗi khi dữ liệu local đổi -> các FutureProvider truy vấn lại.
class DataRevision extends Notifier<int> {
  @override
  int build() {
    final events = ref.watch(dataEventsProvider);
    final sub = events.revisions.listen((r) => state = r);
    ref.onDispose(sub.cancel);
    return events.revision;
  }
}

final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

/// Tăng mỗi khi kết nối/đổi máy chủ cloud trong app -> session, gateway, sync tạo lại.
final cloudRevisionProvider = StateProvider<int>((ref) => 0);
