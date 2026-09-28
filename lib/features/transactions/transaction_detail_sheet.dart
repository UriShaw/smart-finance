import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/liquid.dart';
import '../moments/moment_capture.dart';
import '../moments/photo_viewer.dart';
import '../settings/settings_controller.dart';
import 'transaction_form_screen.dart';

/// Chi tiết giao dịch trong bảng kính: khoảnh khắc ảnh vuông kiểu Locket (chụp + lưu
/// vị trí), số tiền lớn, thông tin, ghi chú, nút Xoá / Sửa / Đóng.
Future<void> showTransactionDetail(
  BuildContext context,
  FinanceTransaction tx,
  TxCategory? category,
) {
  return showGlassSheet<void>(
    context: context,
    builder: (_) => _DetailSheet(tx: tx, category: category),
  );
}

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({required this.tx, required this.category});
  final FinanceTransaction tx;
  final TxCategory? category;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  late FinanceTransaction tx = widget.tx;
  bool _busy = false;

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await captureMoment(context, ref, tx);
      if (updated != null && mounted) setState(() => tx = updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final income = tx.type == TxType.income;
    final color = income ? AppColors.income : AppColors.expense;
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final bankMsg = ref.watch(bankMessageForTxProvider(tx.id)).valueOrNull;
    final amount = Money.format(income ? tx.amountMinor : -tx.amountMinor, currency,
        locale: context.l10n.intlLocale, signed: true);

    Future<void> delete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('delete_confirm_title')),
          content: Text(ctx.tr('delete_tx_confirm')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.expense),
              child: Text(ctx.tr('delete')),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await ref.read(transactionRepoProvider).delete(tx.id);
      if (context.mounted) Navigator.of(context).pop();
    }

    void edit() {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(MaterialPageRoute(builder: (_) => TransactionFormScreen(initial: tx)));
    }

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    Widget button(String label, Color bg, Color fg, VoidCallback onTap) => Expanded(
          child: SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: fg,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: Text(label),
            ),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('tx_detail_title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 20),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(amount,
                style: TextStyle(color: color, fontSize: 32, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 4),
          Text(tx.name,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          if (tx.hasPhoto) ...[
            GestureDetector(
              onTap: () => showPhotoViewer(context, tx),
              child: MomentCard(tx: tx, onRetake: _busy ? null : _capture),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => showPhotoViewer(context, tx),
                    icon: const Icon(Icons.zoom_out_map_rounded),
                    label: Text(context.tr('photo_view')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => downloadPhoto(context, ref, tx),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(context.tr('photo_download')),
                  ),
                ),
              ],
            ),
          ] else
            MomentPlaceholder(onCapture: _capture),
          if (tx.hasPhoto && tx.remoteImagePath == null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_upload_outlined, size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(context.tr('moment_pending_upload'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          row(context.tr('tx_time'), DateFormat('dd/MM/yyyy HH:mm').format(tx.date)),
          row(context.tr('tx_category'), categoryLabel(context, category)),
          row(context.tr('type'), context.tr(income ? 'income' : 'expense')),
          if (tx.locationName != null && tx.locationName!.isNotEmpty)
            row(context.tr('tx_location'), tx.locationName!),
          if (tx.note != null && tx.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark ? Colors.white.withValues(alpha: 0.06) : AppColors.lightBase,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: dark ? Colors.white.withValues(alpha: 0.1) : AppColors.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('tx_note'),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(tx.note!, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
                ],
              ),
            ),
          ],
          if (bankMsg != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
              decoration: BoxDecoration(
                color: dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : AppColors.lightBlue.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: dark ? Colors.white.withValues(alpha: 0.1) : AppColors.lightBlue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sms_outlined, size: 18, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${context.tr('bank_original')} · ${bankMsg.bank}',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('copy'),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(
                              text: [bankMsg.title, bankMsg.body]
                                  .where((e) => e.trim().isNotEmpty)
                                  .join('\n')));
                          showSnack(context, context.tr('copied'));
                        },
                      ),
                    ],
                  ),
                  if (bankMsg.title.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: Text(bankMsg.title,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SelectableText(bankMsg.body,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    [
                      DateFormat('HH:mm:ss dd/MM/yyyy').format(bankMsg.postedAt),
                      if (bankMsg.balance >= 0)
                        context.tr('bank_balance_after', {
                          'n': Money.format(bankMsg.balance * 100, currency,
                              locale: context.l10n.intlLocale)
                        }),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              button(
                  context.tr('delete'),
                  dark ? AppColors.expense.withValues(alpha: 0.18) : AppColors.redSoft,
                  AppColors.expense,
                  delete),
              const SizedBox(width: 10),
              button(
                  context.tr('edit'),
                  dark ? AppColors.primary.withValues(alpha: 0.25) : AppColors.lightBlue,
                  dark ? Colors.white : AppColors.primary,
                  edit),
              const SizedBox(width: 10),
              button(
                  context.tr('close'),
                  dark ? Colors.white.withValues(alpha: 0.08) : AppColors.borderSoft,
                  theme.colorScheme.onSurfaceVariant,
                  () => Navigator.of(context).pop()),
            ],
          ),
        ],
      ),
    );
  }
}
