import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../i18n/app_localizations.dart';
import '../../../core/utils/date_x.dart';
import '../../../logic/data/backup/backup_service.dart';
import '../../../logic/domain/entities/category.dart';
import '../../../logic/state/app_providers.dart';
import '../../widgets/common.dart';
import '../../../logic/state/settings_controller.dart';

/// Hành động sao lưu/xuất/nhập - tách khỏi UI Settings cho gọn.
class BackupActions {
  const BackupActions._();

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<String?> _saveText(String suggestedName, String content, String ext) async {
    String? path;
    if (_desktop) {
      final loc = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: ext.toUpperCase(), extensions: [ext])
        ],
      );
      if (loc == null) return null;
      path = loc.path;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, suggestedName);
    }
    await File(path).writeAsString(content, flush: true);
    return path;
  }

  static String _stamp() {
    final n = DateTime.now();
    return '${DateX.ymd(n)}_${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}';
  }

  static Future<void> exportJson(BuildContext context, WidgetRef ref) async {
    try {
      final json = await ref.read(backupServiceProvider).exportJson();
      final path = await _saveText('smart_finance_backup_${_stamp()}.json', json, 'json');
      if (path != null && context.mounted) {
        showSnack(context, context.tr('export_done', {'p': path}));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static Future<void> exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final txs = await ref.read(transactionRepoProvider).page(offset: 0, limit: 1000000);
      final cats = await ref.read(categoryRepoProvider).mapAll();
      if (!context.mounted) return;
      String name(String? id) {
        final TxCategory? c = id == null ? null : cats[id];
        return categoryLabel(context, c);
      }

      final csv = BackupService.toCsv(
        txs,
        categoryName: name,
        decimals: ref.read(settingsProvider).currency.decimals,
      );
      final path = await _saveText('smart_finance_${_stamp()}.csv', csv, 'csv');
      if (path != null && context.mounted) {
        showSnack(context, context.tr('export_done', {'p': path}));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  static Future<void> importJson(BuildContext context, WidgetRef ref) async {
    try {
      final file = await openFile(acceptedTypeGroups: [
        const XTypeGroup(label: 'JSON', extensions: ['json']),
      ]);
      if (file == null) return;
      final content = await file.readAsString();
      final report = await ref.read(backupServiceProvider).importJson(content);
      if (context.mounted) {
        showSnack(
          context,
          context.tr('import_done', {
            'a': report.inserted,
            'u': report.updated,
            's': report.skipped,
            'i': report.invalid,
          }),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
