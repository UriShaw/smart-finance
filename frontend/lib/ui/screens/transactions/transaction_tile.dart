import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../i18n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../../core/utils/money.dart';
import '../../../logic/domain/entities/category.dart';
import '../../../logic/domain/entities/common.dart';
import '../../../logic/domain/entities/finance_transaction.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../../logic/state/settings_controller.dart';

/// Dòng giao dịch kiểu app cũ: thẻ kính trắng, vòng tròn icon xanh lá (thu) / đỏ (chi),
/// tên đậm, "danh mục • dd/MM HH:mm", số tiền có dấu bên phải.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    super.key,
    required this.tx,
    required this.category,
    this.onTap,
    this.boxed = true,
  });

  final FinanceTransaction tx;
  final TxCategory? category;
  final VoidCallback? onTap;

  /// true = tự vẽ thẻ kính riêng (danh sách chính); false = dòng phẳng trong thẻ khác.
  final bool boxed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final income = tx.type == TxType.income;
    final color = income ? AppColors.income : AppColors.expense;
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final amount = Money.format(income ? tx.amountMinor : -tx.amountMinor, currency,
        locale: context.l10n.intlLocale, signed: true);
    final sub = '${categoryLabel(context, category)} • '
        '${DateFormat('dd/MM HH:mm').format(tx.date)}';

    final row = LayoutBuilder(builder: (context, c) {
      return Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark
                  ? color.withValues(alpha: 0.18)
                  : (income ? AppColors.greenSoft : AppColors.redSoft),
            ),
            child: Icon(categoryIcon(category?.icon), color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tx.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    if (tx.hasPhoto) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.image_outlined, size: 14, color: theme.colorScheme.outline),
                    ],
                    if (tx.recurringId != null) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.repeat, size: 14, color: theme.colorScheme.outline),
                    ],
                    if (tx.syncStatus != SyncStatus.synced) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.cloud_upload_outlined, size: 14, color: AppColors.warning),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: c.maxWidth * 0.42),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                amount,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      );
    });

    final semantics = '${tx.name}, $sub, $amount';
    if (!boxed) {
      return Semantics(
        label: semantics,
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: row,
          ),
        ),
      );
    }
    return Semantics(
      label: semantics,
      button: onTap != null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: GlassCard(
          radius: 20,
          onTap: onTap,
          padding: const EdgeInsets.all(16),
          child: row,
        ),
      ),
    );
  }
}
