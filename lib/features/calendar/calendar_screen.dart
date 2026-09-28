import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_x.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../domain/usecases/statistics_aggregator.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/shell_scope.dart';
import '../../shared/widgets/glass.dart';
import '../settings/settings_controller.dart';
import '../transactions/transaction_detail_sheet.dart';
import '../transactions/transaction_tile.dart';

final _monthNetProvider = FutureProvider.family<Map<int, int>, DateTime>((ref, month) async {
  ref.watch(dataRevisionProvider);
  final ledger = await ref
      .watch(transactionRepoProvider)
      .ledger(from: DateX.startOfMonth(month), to: DateX.startOfNextMonth(month));
  return StatisticsAggregator.dailyNet(ledger, month.year, month.month);
});

final _dayTxProvider = FutureProvider.family<List<FinanceTransaction>, DateTime>((ref, day) async {
  ref.watch(dataRevisionProvider);
  return ref.watch(transactionRepoProvider).inRange(day, DateX.nextDay(day));
});

/// Lịch chi tiêu: tổng chi mỗi ngày; chạm vào ngày để xem giao dịch.
/// [embedded] = nằm trong thanh điều hướng chính (không AppBar riêng).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateX.startOfDay(now);
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _selected = _month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final daily = ref.watch(_monthNetProvider(_month)).valueOrNull ?? const {};
    final dayTx = ref.watch(_dayTxProvider(_selected));
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final maxDay = daily.values.fold<int>(0, (m, v) => v.abs() > m ? v.abs() : m);

    final calendar = GlassCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left), tooltip: '-1'),
              Expanded(
                child: Text(
                  DateFormat.yMMMM(l.intlLocale).format(_month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                  onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right), tooltip: '+1'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _MonthGrid(
            month: _month,
            selected: _selected,
            daily: daily,
            maxDay: maxDay,
            locale: l.intlLocale,
            onSelect: (d) => setState(() => _selected = d),
          ),
        ],
      ),
    );

    final dayNet = _selected.month == _month.month ? daily[_selected.day] : null;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          formatDate(context, _selected),
          trailing: dayNet == null
              ? null
              : Text(
                  '${context.tr('day_net')}: ${Money.format(dayNet, currency, locale: l.intlLocale, signed: true)}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: dayNet >= 0 ? AppColors.income : AppColors.expense,
                      ),
                ),
        ),
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AsyncBody<List<FinanceTransaction>>(
            value: dayTx,
            builder: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(context.tr('no_tx_day'), textAlign: TextAlign.center),
                  )
                : Column(
                    children: [
                      for (final t in list)
                        TransactionTile(
                          boxed: false,
                          tx: t,
                          category: catMap[t.categoryId],
                          onTap: () => showTransactionDetail(context, t, catMap[t.categoryId]),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );

    final body = LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: calendar)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: SingleChildScrollView(child: details)),
            ],
          ),
        );
      }
      return ListView(
        padding:
            const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.bottomNav + 40),
        children: [
          ContentWidth(max: 720, child: Column(children: [calendar, details]))
        ],
      );
    });

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        leading: ShellMenuButton.maybe(context),
        title: Text(context.tr('calendar_title')),
      ),
      body: body,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.daily,
    required this.maxDay,
    required this.locale,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<int, int> daily;
  final int maxDay;
  final String locale;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = DateX.daysInMonth(month.year, month.month);
    final leading = DateTime(month.year, month.month, 1).weekday - 1; // thứ Hai đầu tuần
    final cells = leading + days;
    final rows = (cells / 7).ceil();
    final today = DateX.startOfDay(DateTime.now());
    // Tên thứ theo locale, bắt đầu từ thứ Hai (2024-01-01 là thứ Hai).
    final weekdays = [
      for (var i = 0; i < 7; i++) DateFormat.E(locale).format(DateTime(2024, 1, 1 + i)),
    ];

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays)
              Expanded(
                child: Center(
                  child: Text(w,
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Builder(builder: (context) {
                    final idx = r * 7 + c - leading + 1;
                    if (idx < 1 || idx > days) return const SizedBox(height: 56);
                    final d = DateTime(month.year, month.month, idx);
                    // Ngày không có giao dịch -> null (ô trống).
                    final net = daily[idx];
                    final intensity = net == null || maxDay == 0 ? 0.0 : net.abs() / maxDay;
                    final tone = (net ?? 0) >= 0 ? AppColors.income : AppColors.expense;
                    final isSel = DateX.sameDay(d, selected);
                    final isToday = DateX.sameDay(d, today);
                    return Padding(
                      padding: const EdgeInsets.all(2),
                      child: Semantics(
                        button: true,
                        selected: isSel,
                        label: '$idx',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onSelect(d),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            decoration: BoxDecoration(
                              color: net == null || net == 0
                                  ? null
                                  : tone.withValues(alpha: 0.08 + 0.32 * intensity),
                              borderRadius: BorderRadius.circular(10),
                              border: isSel
                                  ? Border.all(color: scheme.primary, width: 2)
                                  : isToday
                                      ? Border.all(color: scheme.outline)
                                      : null,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$idx',
                                    style: TextStyle(
                                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
                                if (net != null)
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      Money.shortSigned(net, locale: locale),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: tone,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
      ],
    );
  }
}
