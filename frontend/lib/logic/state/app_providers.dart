import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/config/env.dart';
import '../data/backup/backup_service.dart';
import '../data/remote/supabase_gateway.dart';
import '../data/repositories/bank_message_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/duplicate_cleaner.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/sync/cache_janitor.dart';
import '../data/sync/photo_service.dart';
import '../data/sync/sync_engine.dart';
import '../domain/entities/category.dart';
import '../domain/entities/finance_transaction.dart';
import '../domain/repositories/remote_gateway.dart';
import '../domain/usecases/balance_calculator.dart';
import '../../core/utils/date_x.dart';
import '../auth/auth_controller.dart';
import '../bank/bank_balance_cloud.dart';
import 'settings_controller.dart';
import 'core_providers.dart';

export 'core_providers.dart';

final remoteGatewayProvider = Provider<RemoteGateway?>((ref) {
  if (!Env.cloudReady) return null;
  return SupabaseGateway(sb.Supabase.instance.client);
});

final photoServiceProvider = Provider<PhotoService>((ref) => const PhotoService());

// ---------------------------------------------------------------- Repositories

final transactionRepoProvider = Provider<TransactionRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return TransactionRepository(
    database: ref.watch(appDatabaseProvider),
    events: ref.watch(dataEventsProvider),
    userId: () => uid,
  );
});

final categoryRepoProvider = Provider<CategoryRepository>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return CategoryRepository(
    database: ref.watch(appDatabaseProvider),
    events: ref.watch(dataEventsProvider),
    userId: () => uid,
  );
});

final backupServiceProvider = Provider<BackupService>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  return BackupService(
    database: ref.watch(appDatabaseProvider),
    events: ref.watch(dataEventsProvider),
    userId: () => uid,
  );
});

// ---------------------------------------------------------------- Sync

/// Dọn giao dịch trùng (nhiều máy cùng tài khoản cùng nhận 1 thông báo ngân hàng).
final duplicateCleanerProvider = Provider<DuplicateCleaner>(
  (ref) => DuplicateCleaner(
    database: ref.watch(appDatabaseProvider),
    transactions: ref.watch(transactionRepoProvider),
  ),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final isCloud = ref.watch(isCloudUserProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final engine = SyncEngine(
    database: ref.watch(appDatabaseProvider),
    remote: ref.watch(remoteGatewayProvider),
    events: ref.watch(dataEventsProvider),
    photos: ref.watch(photoServiceProvider),
    userId: () => uid,
    isCloudUser: () => isCloud,
    isOnline: connectivity.isOnline,
    settings: () {
      final s = ref.read(settingsProvider);
      return SyncSettings(retentionDays: s.retentionDays, keepLocalPhotos: s.keepLocalPhotos);
    },
    afterPull: () async {
      await ref.read(duplicateCleanerProvider).run();
    },
  );
  engine.start();
  final sub = connectivity.onlineChanges.listen(engine.onConnectivityChanged);
  ref.onDispose(() {
    sub.cancel();
    engine.dispose();
  });
  // Đồng bộ ngay khi khởi tạo (mở app / đăng nhập).
  Future.microtask(() => engine.syncNow(force: true));
  return engine;
});

final syncStatusProvider = StreamProvider<SyncSnapshot>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.last;
  yield* engine.status;
});

final cacheJanitorProvider = Provider<CacheJanitor>((ref) => ref.watch(syncEngineProvider).janitor);

final storageUsageProvider = FutureProvider<StorageUsage>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(cacheJanitorProvider).usage();
});

// ---------------------------------------------------------------- Bootstrap

/// Chạy mỗi khi đổi user: seed danh mục mặc định + sinh giao dịch định kỳ đến hạn.
final bootstrapProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserIdProvider);
  await ref.watch(categoryRepoProvider).ensureDefaults();
  // Đã bỏ tính năng Định kỳ: không tự sinh giao dịch nữa.
  return 0;
});

// ---------------------------------------------------------------- Queries

final categoriesProvider = FutureProvider<List<TxCategory>>((ref) async {
  ref.watch(dataRevisionProvider);
  await ref.watch(bootstrapProvider.future);
  return ref.watch(categoryRepoProvider).list();
});

final categoryMapProvider = FutureProvider<Map<String, TxCategory>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(categoryRepoProvider).mapAll();
});

final totalSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  ref.watch(dataRevisionProvider);
  final ledger = await ref.watch(transactionRepoProvider).ledger();
  return BalanceCalculator.summarize(ledger);
});

/// Thu / chi / tiết kiệm của một tháng (trang chủ). Tham số = ngày đầu tháng.
final monthSummaryProvider = FutureProvider.family<BalanceSummary, DateTime>((ref, month) async {
  ref.watch(dataRevisionProvider);
  final ledger = await ref
      .watch(transactionRepoProvider)
      .ledger(from: DateX.startOfMonth(month), to: DateX.startOfNextMonth(month));
  return BalanceCalculator.summarize(ledger);
});

final bankMessageRepoProvider = Provider<BankMessageRepository>(
    (ref) => BankMessageRepository(ref.watch(appDatabaseProvider), ref.watch(dataEventsProvider)));

/// Số dư tính từ thông báo ngân hàng gốc trên máy này (chỉ điện thoại có).
final _localBankBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(bankMessageRepoProvider).balances(userId: ref.watch(currentUserIdProvider));
});

/// Số dư các máy khác đã gửi lên cloud (đọc lại mỗi khi dữ liệu đồng bộ về).
final _cloudBankBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  ref.watch(dataRevisionProvider);
  if (!ref.watch(isCloudUserProvider) || !Env.cloudReady) return const [];
  return BankBalanceCloud.fetch(sb.Supabase.instance.client);
});

/// Số dư từng tài khoản theo thông báo ngân hàng: của máy này gộp với số dư điện thoại
/// khác đã gửi lên (máy tính không nhận thông báo vẫn thấy số dư). Rỗng nếu chưa có.
final bankBalancesProvider = FutureProvider<List<AccountBalance>>((ref) async {
  final local = await ref.watch(_localBankBalancesProvider.future);
  final cloud = await ref.watch(_cloudBankBalancesProvider.future);
  if (local.isNotEmpty && ref.read(isCloudUserProvider) && Env.cloudReady) {
    // Không chờ: lỗi mạng thì lần thay đổi sau gửi lại.
    BankBalanceCloud.publish(sb.Supabase.instance.client, local, cloud).ignore();
  }
  return BankBalanceCloud.merge(cloud, local);
});

/// Thông báo ngân hàng gốc của 1 giao dịch (null nếu nhập tay / máy khác).
final bankMessageForTxProvider = FutureProvider.family<BankMessage?, String>((ref, txId) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(bankMessageRepoProvider).byTransaction(txId);
});

final momentsProvider = FutureProvider<List<FinanceTransaction>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).withPhoto(limit: 20);
});

final recentTransactionsProvider = FutureProvider<List<FinanceTransaction>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).recent(limit: 8);
});

final archivedCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).archivedCount();
});

/// Thống kê hôm nay (thẻ "Tổng quan hôm nay" + "+x hôm nay").
class DayStats {
  const DayStats(this.summary, this.count);
  static const empty = DayStats(BalanceSummary.empty, 0);
  final BalanceSummary summary;
  final int count;
}

final todayStatsProvider = FutureProvider<DayStats>((ref) async {
  ref.watch(dataRevisionProvider);
  final start = DateX.startOfDay(DateTime.now());
  final ledger =
      await ref.watch(transactionRepoProvider).ledger(from: start, to: DateX.nextDay(start));
  return DayStats(BalanceCalculator.summarize(ledger), ledger.length);
});

/// Toàn bộ sổ cái (cả giao dịch đã lưu trữ) cho biểu đồ số dư & xu hướng.
final fullLedgerProvider = FutureProvider<List<LedgerEntry>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).ledger();
});
