import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_finance/core/constants/app_constants.dart';
import 'package:smart_finance/core/errors/app_error.dart';
import 'package:smart_finance/ui/i18n/app_localizations.dart';
import 'package:smart_finance/ui/i18n/strings_en.dart';
import 'package:smart_finance/ui/i18n/strings_vi.dart';
import 'package:smart_finance/ui/i18n/strings_zh.dart';
import 'package:smart_finance/core/utils/ids.dart';
import 'package:smart_finance/logic/data/backup/backup_service.dart';
import 'package:smart_finance/logic/data/repositories/category_repository.dart';
import 'package:smart_finance/logic/data/repositories/data_events.dart';
import 'package:smart_finance/logic/data/repositories/transaction_repository.dart';
import 'package:smart_finance/logic/domain/entities/common.dart';
import 'package:smart_finance/logic/domain/entities/finance_transaction.dart';

import 'helpers/fakes.dart';

void main() {
  group('Backup / restore', () {
    test('export -> import into empty DB restores same records', () async {
      final src = await openTestDb();
      final events = DataEvents();
      final repo = TransactionRepository(database: src, events: events, userId: () => 'u1');
      await CategoryRepository(database: src, events: events, userId: () => 'u1').ensureDefaults();
      final now = DateTime.now();
      for (var i = 0; i < 20; i++) {
        await repo.save(FinanceTransaction(
          id: Ids.newId(),
          userId: 'u1',
          name: 'Giao dịch $i, "đặc biệt"',
          amountMinor: 1000 * (i + 1),
          type: i % 3 == 0 ? TxType.income : TxType.expense,
          date: now.subtract(Duration(days: i)),
          note: i.isEven ? 'ghi chú $i' : null,
          latitude: i == 1 ? 10.5 : null,
          longitude: i == 1 ? 106.7 : null,
          createdAt: now,
          updatedAt: now,
        ));
      }
      final json =
          await BackupService(database: src, events: events, userId: () => 'u1').exportJson();
      final doc = jsonDecode(json) as Map<String, dynamic>;
      expect(doc['schema_version'], AppConstants.dbSchemaVersion);
      expect(doc['checksum'], isA<String>());
      expect(doc['counts']['transactions'], 20);

      final dst = await openTestDb();
      final svc = BackupService(database: dst, events: DataEvents(), userId: () => 'u2');
      final report = await svc.importJson(json);
      expect(report.inserted, 20 + 13);
      expect(report.invalid, 0);

      final srcSum = (await repo.ledger()).fold<int>(0, (a, e) => a + e.signedAmount);
      final dstRepo =
          TransactionRepository(database: dst, events: DataEvents(), userId: () => 'u2');
      final dstSum = (await dstRepo.ledger()).fold<int>(0, (a, e) => a + e.signedAmount);
      expect(dstSum, srcSum);
      final one = (await dstRepo.page(offset: 0, limit: 100)).firstWhere((t) => t.latitude != null);
      expect(one.longitude, 106.7);

      // Import lần 2: không tạo trùng.
      final again = await svc.importJson(json);
      expect(again.inserted, 0);
      expect(again.skipped, 33);
      await src.close();
      await dst.close();
    });

    test('tampered backup is rejected by checksum', () async {
      final db = await openTestDb();
      final svc = BackupService(database: db, events: DataEvents(), userId: () => 'u1');
      final doc = jsonDecode(await svc.exportJson()) as Map<String, dynamic>;
      (doc['data'] as Map<String, dynamic>)['transactions'] = [
        {
          'id': 'x' * 36,
          'name': 'hack',
          'amount_minor': 1,
          'type': 'income',
          'transaction_date': 1,
          'created_at': 1,
          'updated_at': 1
        },
      ];
      expect(() => svc.importJson(jsonEncode(doc)), throwsA(isA<AppError>()));
      expect(() => svc.importJson('not json'), throwsA(isA<AppError>()));
      await db.close();
    });

    test('CSV escapes commas, quotes and formula injection', () {
      final now = DateTime(2026, 1, 1);
      final csv = BackupService.toCsv([
        FinanceTransaction(
          id: 'a',
          userId: 'u',
          name: '=SUM(A1)',
          amountMinor: 5000000,
          type: TxType.expense,
          date: now,
          note: 'a, "b"',
          createdAt: now,
          updatedAt: now,
        ),
      ], categoryName: (_) => 'Ăn uống', decimals: 0);
      expect(csv.startsWith('﻿'), isTrue);
      expect(csv, contains("'=SUM(A1)"));
      expect(csv, contains('"a, ""b"""'));
      expect(csv, contains(',50000,'));
    });
  });

  group('Localization', () {
    test('all languages have the same keys as Vietnamese', () {
      final vi = stringsVi.keys.toSet();
      expect(stringsEn.keys.toSet(), vi);
      expect(stringsZhHans.keys.toSet(), vi);
      expect(stringsZhHant.keys.toSet(), vi);
    });

    test('Traditional Chinese resolves from zh_TW and zh_Hant', () {
      expect(AppLocalizations.isTraditional(const Locale('zh', 'TW')), isTrue);
      expect(
          AppLocalizations.isTraditional(
              const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
          isTrue);
      expect(AppLocalizations.isTraditional(const Locale('zh', 'CN')), isFalse);
      final hant =
          AppLocalizations(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
      expect(hant.t('nav_settings'), '設定');
      expect(AppLocalizations(const Locale('en')).t('tx_count', {'n': 3}), '3 transactions');
    });
  });
}
