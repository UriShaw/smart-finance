import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/bank_message_repository.dart';
import '../../domain/usecases/balance_calculator.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import '../bank/bank_channel.dart';
import '../bank/bank_controller.dart';
import '../map/map_screen.dart';
import '../moments/photo_viewer.dart';
import '../transactions/photo_preview.dart';
import '../transactions/transaction_detail_sheet.dart';
import '../transactions/transaction_tile.dart';

/// Trang chủ theo bố cục app cũ:
/// Thẻ tổng tài sản (xanh) -> Giám sát giao dịch -> Tổng quan hôm nay ->
/// (mới) Khoảnh khắc (ảnh + vị trí) -> Giao dịch gần đây.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onSeeAll});

  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentTransactionsProvider);
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).syncNow(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, AppSpacing.bottomNav + 40),
          children: [
            ContentWidth(
              max: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AssetCard(),
                  if (BankChannel.supported) ...[
                    const SizedBox(height: 20),
                    const MonitoringToggleCard(),
                  ],
                  const SizedBox(height: 20),
                  const TodayOverviewCard(),
                  const SizedBox(height: 20),
                  const _MomentsStrip(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(context.tr('recent_transactions'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18)),
                      ),
                      if (onSeeAll != null)
                        TextButton(
                          onPressed: onSeeAll,
                          child: Text(context.tr('see_all'),
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                  AsyncBody(
                    value: recent,
                    builder: (list) => list.isEmpty
                        ? GlassCard(
                            child: EmptyState(
                                icon: Icons.receipt_long_outlined,
                                message: context.tr('no_transactions')),
                          )
                        : Column(
                            children: [
                              for (final t in list.take(5))
                                TransactionTile(
                                  tx: t,
                                  category: catMap[t.categoryId],
                                  onTap: () =>
                                      showTransactionDetail(context, t, catMap[t.categoryId]),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ "Tổng tài sản" (gradient xanh như app cũ), có nút ẩn/hiện số dư.
class AssetCard extends ConsumerStatefulWidget {
  const AssetCard({super.key});

  @override
  ConsumerState<AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends ConsumerState<AssetCard> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(totalSummaryProvider).valueOrNull ?? BalanceSummary.empty;
    final today = ref.watch(todayStatsProvider).valueOrNull ?? DayStats.empty;
    // Thu nhập / chi tiêu / tiết kiệm chỉ tính tháng hiện tại, sang tháng mới tự về 0.
    final now = DateTime.now();
    final m = ref.watch(monthSummaryProvider(DateTime(now.year, now.month))).valueOrNull ??
        BalanceSummary.empty;
    // Có thông báo ngân hàng ghi số dư -> tổng tài sản = số dư ngân hàng báo (không tự cộng trừ).
    final banks = ref.watch(bankBalancesProvider).valueOrNull ?? const <AccountBalance>[];
    final fromBank = banks.isNotEmpty;
    // Đang đọc thông báo nhưng chưa có tin nào ghi số dư -> không hiện "thu - chi" thay số dư thật.
    final waitingBank =
        !fromBank && (ref.watch(bankControllerProvider).valueOrNull?.active ?? false);
    final shownBalance =
        fromBank ? banks.fold<int>(0, (a, b) => a + b.balance) * 100 : t.balanceMinor;
    final theme = Theme.of(context);
    String money(int v) => formatMoney(ref, context, v);
    final white80 = Colors.white.withValues(alpha: 0.8);

    Widget sub(String label, int value, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 11.5)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money(value),
                    style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ],
          ),
        );

    return GradientGlassCard(
      colors: AppColors.heroGradient,
      radius: 28,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(context.tr(fromBank || waitingBank ? 'bank_balance_title' : 'total_assets'),
                  style: TextStyle(color: white80, fontSize: 14)),
              const SizedBox(width: 8),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => _visible = !_visible),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                    color: white80,
                    semanticLabel: context.tr(_visible ? 'hide_balance' : 'show_balance'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: waitingBank
                  ? const Text('—',
                      key: ValueKey('waiting'),
                      style:
                          TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900))
                  : _visible
                      ? AnimatedNumber(
                          key: const ValueKey('shown'),
                          value: shownBalance,
                          format: money,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 32,
                            letterSpacing: -0.5,
                          ),
                        )
                      : const Text('••••••••',
                          key: ValueKey('hidden'),
                          style: TextStyle(
                              color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            ),
          ),
          if (fromBank)
            for (final b in banks.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_rounded, size: 14, color: white80),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${b.label} · ${context.tr('updated_at', {
                              't': DateFormat('HH:mm dd/MM').format(b.updatedAt)
                            })}'
                        '${b.fromNotification ? '' : ' · ${context.tr('bank_balance_estimated')}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: white80, fontSize: 12),
                      ),
                    ),
                    if (banks.length > 1 && _visible)
                      Text(money(b.balance * 100),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          if (waitingBank)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(context.tr('bank_balance_waiting'),
                  style: TextStyle(color: white80, fontSize: 12)),
            ),
          Text(
            context.tr('today_income', {'n': money(today.summary.incomeMinor)}),
            style: const TextStyle(
                color: Color(0xFFBBF7D0), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('home_month', {'m': now.month, 'y': now.year}),
            style: TextStyle(color: white80, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              sub(context.tr('income_total'), m.incomeMinor, const Color(0xFFBBF7D0)),
              const SizedBox(width: 8),
              sub(context.tr('expense_total'), m.expenseMinor, const Color(0xFFFECACA)),
              const SizedBox(width: 8),
              sub(context.tr('savings'), m.balanceMinor, const Color(0xFFDBEAFE)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thẻ "Giám sát đang bật/tắt" (đọc số dư tự động) - chỉ Android.
class MonitoringToggleCard extends ConsumerWidget {
  const MonitoringToggleCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(bankControllerProvider).valueOrNull;
    if (bank == null || !bank.supported) return const SizedBox.shrink();
    final on = bank.config.enabled;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ctrl = ref.read(bankControllerProvider.notifier);
    final color = on ? AppColors.income : AppColors.expense;
    final subtitle = !on
        ? context.tr('monitoring_off_sub')
        : (bank.permission
            ? context.tr('monitoring_on_sub')
            : context.tr('bank_permission_missing'));
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(20),
      onTap: () => ctrl.setEnabled(!on),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark
                  ? color.withValues(alpha: 0.18)
                  : (on ? AppColors.greenSoft : AppColors.redSoft),
            ),
            child: Icon(on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(on ? 'monitoring_on' : 'monitoring_off'),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: on && !bank.permission
                            ? AppColors.warning
                            : theme.colorScheme.onSurfaceVariant,
                        fontSize: 13)),
              ],
            ),
          ),
          LiquidSwitch(
            value: on,
            colors: AppColors.incomeGradient,
            onChanged: ctrl.setEnabled,
          ),
        ],
      ),
    );
  }
}

/// Thẻ "Tổng quan hôm nay".
class TodayOverviewCard extends ConsumerWidget {
  const TodayOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(todayStatsProvider).valueOrNull ?? DayStats.empty;
    String money(int v) => formatMoney(ref, context, v);
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('today_overview'),
              style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            children: [
              OverviewItem(label: context.tr('tx_count_label'), value: '${d.count}'),
              OverviewItem(label: context.tr('income_total'), value: money(d.summary.incomeMinor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OverviewItem(
                  label: context.tr('expense_total'), value: money(d.summary.expenseMinor)),
              OverviewItem(label: context.tr('net_flow'), value: money(d.summary.balanceMinor)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Nhãn nhỏ + giá trị đậm (dùng ở Trang chủ và Lịch sử).
class OverviewItem extends StatelessWidget {
  const OverviewItem({super.key, required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 14, color: color)),
          ),
        ],
      ),
    );
  }
}

/// (Mới) Lưới tiện ích nhanh.
/// Dải "Khoảnh khắc": ảnh vuông kiểu Locket của các giao dịch đã chụp, kèm vị trí.
class _MomentsStrip extends ConsumerWidget {
  const _MomentsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final list = ref.watch(momentsProvider).valueOrNull ?? const [];
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};

    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const LiquidIconBadge(
                  icon: Icons.photo_camera_rounded, color: LiquidColors.pink, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.tr('moments'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MapScreen())),
                icon: const Icon(Icons.map_rounded, size: 18),
                label: Text(context.tr('nav_map')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            Text(context.tr('moments_empty'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4))
          else
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                separatorBuilder: (context, i) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final t = list[i];
                  final place = t.locationName ?? '';
                  return Semantics(
                    button: true,
                    label: '${t.name} $place',
                    child: GestureDetector(
                      onTap: () => showTransactionDetail(context, t, catMap[t.categoryId]),
                      onLongPress: () => showPhotoViewer(context, t),
                      child: SizedBox(
                        width: 108,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: SizedBox(
                                width: 108,
                                height: 108,
                                child: PhotoPreview(
                                  localPath: t.localImagePath,
                                  remotePath: t.remoteImagePath,
                                  height: 108,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              place.isEmpty ? t.name : place,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
