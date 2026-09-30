class AppConstants {
  const AppConstants._();

  static const String appName = 'Smart Finance';

  /// user_id dùng khi chưa đăng nhập (chế độ offline). Khi đăng nhập,
  /// dữ liệu 'local' được chuyển sang user thật (LocalDataClaimer).
  static const String localUserId = 'local';

  static const int dbSchemaVersion = 2;
  static const String dbFileName = 'smart_finance.db';
  static const String photosDirName = 'photos';
  static const String storageBucket = 'receipts';

  static const String backupFormat = 'smart_finance_backup';
  static const int backupFormatVersion = 1;

  static const int historyPageSize = 30;

  /// Số ngày giữ bản ghi đầy đủ trên máy. 0 = giữ tất cả.
  static const List<int> retentionOptions = [30, 90, 180, 365, 0];
  static const int defaultRetentionDays = 180;

  static const int photoMaxSide = 1280;
  static const int photoJpegQuality = 80;

  static const Duration syncDebounce = Duration(seconds: 2);
  static const Duration syncPeriodic = Duration(minutes: 5);
  static const int syncMaxBackoffSeconds = 30 * 60;
  static const int syncFailedAfterAttempts = 5;
  static const int pullPageSize = 500;
}
