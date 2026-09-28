import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show sqfliteFfiInit, databaseFactoryFfi;

import '../constants/app_constants.dart';
import 'file_paths.dart';

typedef Db = sqflite.Database;
typedef DbExecutor = sqflite.DatabaseExecutor;

/// SQLite local (offline-first). Mọi thời gian lưu dạng epoch milliseconds (UTC).
///
/// Migrations đánh số phiên bản: thêm hàm vào [_migrations] và tăng
/// [AppConstants.dbSchemaVersion]. Không sửa migration cũ đã phát hành.
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Db db;
  final String path;

  static bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static sqflite.DatabaseFactory get _factory {
    if (_isDesktop) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  static Future<AppDatabase> open({
    String? path,
    sqflite.DatabaseFactory? factory,
  }) async {
    final f = factory ?? _factory;
    final dbPath = path ?? p.join((await FilePaths.appDataDir()).path, AppConstants.dbFileName);
    final db = await f.openDatabase(
      dbPath,
      options: sqflite.OpenDatabaseOptions(
        version: AppConstants.dbSchemaVersion,
        onConfigure: (db) async {
          // rawQuery vì PRAGMA journal_mode trả về kết quả (Android bắt buộc).
          try {
            await db.rawQuery('PRAGMA journal_mode = WAL');
          } catch (_) {}
        },
        onCreate: (db, version) async {
          for (var v = 1; v <= version; v++) {
            await _migrations[v]!(db);
          }
        },
        onUpgrade: (db, oldV, newV) async {
          for (var v = oldV + 1; v <= newV; v++) {
            await _migrations[v]!(db);
          }
        },
      ),
    );
    return AppDatabase._(db, dbPath);
  }

  Future<void> close() => db.close();

  static final Map<int, Future<void> Function(sqflite.Database)> _migrations = {
    1: _v1,
    2: _v2,
  };

  /// v2: thông báo ngân hàng gốc (chỉ lưu trên máy) -> số dư theo ngân hàng + xem lại tin gốc.
  static Future<void> _v2(sqflite.Database db) async {
    final b = db.batch();
    b.execute('''
      CREATE TABLE IF NOT EXISTS bank_messages (
        id TEXT PRIMARY KEY,
        tx_id TEXT,
        pkg TEXT NOT NULL DEFAULT '',
        bank TEXT NOT NULL DEFAULT '',
        account TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        direction INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        balance INTEGER NOT NULL DEFAULT -1,
        posted_at INTEGER NOT NULL
      )''');
    b.execute('CREATE INDEX IF NOT EXISTS idx_bank_msg_time ON bank_messages(posted_at)');
    b.execute('CREATE INDEX IF NOT EXISTS idx_bank_msg_tx ON bank_messages(tx_id)');
    await b.commit(noResult: true);
  }

  static Future<void> _v1(sqflite.Database db) async {
    final b = db.batch();
    b.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        icon TEXT NOT NULL,
        color INTEGER NOT NULL,
        default_key TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    b.execute('CREATE INDEX idx_categories_user ON categories(user_id)');

    b.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        category_id TEXT,
        note TEXT,
        transaction_date INTEGER NOT NULL,
        location_name TEXT,
        latitude REAL,
        longitude REAL,
        local_image_path TEXT,
        remote_image_path TEXT,
        recurring_id TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    b.execute('CREATE INDEX idx_tx_user_date ON transactions(user_id, transaction_date)');
    b.execute('CREATE INDEX idx_tx_user_sync ON transactions(user_id, sync_status)');

    // Bản rút gọn của giao dịch cũ đã dọn khỏi máy (retention) - vẫn đủ để
    // tính số dư, thống kê, ngân sách khi offline.
    b.execute('''
      CREATE TABLE tx_archive (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        transaction_date INTEGER NOT NULL,
        category_id TEXT
      )''');
    b.execute('CREATE INDEX idx_archive_user_date ON tx_archive(user_id, transaction_date)');

    b.execute('''
      CREATE VIEW v_ledger AS
        SELECT id, user_id, type, amount_minor, transaction_date, category_id
          FROM transactions WHERE deleted_at IS NULL
        UNION ALL
        SELECT id, user_id, type, amount_minor, transaction_date, category_id
          FROM tx_archive''');

    b.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        category_id TEXT,
        period TEXT NOT NULL CHECK (period IN ('weekly','monthly','yearly')),
        limit_minor INTEGER NOT NULL CHECK (limit_minor > 0),
        warn_percent INTEGER NOT NULL DEFAULT 80,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    b.execute('CREATE INDEX idx_budgets_user ON budgets(user_id)');

    b.execute('''
      CREATE TABLE recurring_rules (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
        type TEXT NOT NULL CHECK (type IN ('income','expense')),
        category_id TEXT,
        note TEXT,
        frequency TEXT NOT NULL,
        start_date INTEGER NOT NULL,
        end_date INTEGER,
        next_run_date INTEGER NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )''');
    b.execute('CREATE INDEX idx_recurring_user ON recurring_rules(user_id)');

    // Outbox / sync queue. Mỗi entity chỉ có 1 dòng (gộp thay đổi);
    // revision tăng mỗi lần enqueue để không xóa nhầm thay đổi mới hơn.
    b.execute('''
      CREATE TABLE outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        op TEXT NOT NULL CHECK (op IN ('upsert','delete')),
        revision INTEGER NOT NULL DEFAULT 1,
        attempts INTEGER NOT NULL DEFAULT 0,
        next_attempt_at INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE (entity, entity_id)
      )''');
    b.execute('CREATE INDEX idx_outbox_due ON outbox(user_id, next_attempt_at)');

    b.execute('''
      CREATE TABLE sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    await b.commit(noResult: true);
  }
}
