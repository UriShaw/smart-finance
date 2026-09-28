import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_x.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../domain/usecases/statistics_aggregator.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import 'charts.dart';

/// Thống kê theo bố cục app cũ: tiêu đề + thanh chọn kỳ (7 ngày / 30 ngày / 3 tháng / 1 năm),
/// lưới 4 chỉ số, biến động số dư, so sánh thu - chi, thói quen giao dịch, xu hướng thu nhập
/// + (mới) cơ cấu theo danh mục.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  int _period = 0; // 0: 7 ngày, 1: 30 ngày, 2: 3 tháng, 3: 1 năm
  TxType _breakdown = TxType.expense;

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final end = DateX.nextDay(DateX.startOfDay(now));
    final start = switch (_period) {
      0 => DateTime(end.year, end.month, end.day - 7),
      1 => DateTime(end.year, end.month, end.day - 30),
      2 => DateTime(end.year, end.month - 3, end.day),
      _ => DateTime(end.year - 1, end.month, end.day),
    };
    return (start, end);
  }

  /// Các mốc thời gian (kết thúc mỗi đoạn) để vẽ đường số dư.
  List<DateTime> _marks(DateTime start, DateTime end) {
    final out = <DateTime>[];
    switch (_period) {
      case 0:
        for (var i = 6; i >= 0; i--) {
          out.add(DateTime(end.year, end.month, end.day - i));
        }
      case 1:
        for (var i = 27; i >= 0; i -= 3) {
          out.add(DateTime(end.year, end.month, end.day - i));
        }
      case 2:
        for (var i = 12; i >= 0; i--) {
          out.add(DateTime(end.year, end.month, end.day - i * 7));
        }
      default:
        for (var i = 11; i >= 0; i--) {
          out.add(DateTime(end.year, end.month - i, 1));
        }
        out[out.length - 1] = end;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ledgerAsync = ref.watch(fullLedgerProvider);
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final loc = context.l10n.intlLocale;
    String money(int v) => formatMoney(ref, context, v);

    final periods = [
      context.tr('days_n', {'n': 7}),
      context.tr('days_n', {'n': 30}),
      context.tr('months_n', {'n': 3}),
      context.tr('years_n', {'n': 1}),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ContentWidth(
        max: 860,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.tr('stats_title'),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 26)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: LiquidSegmented<int>(
                segments: [
                  for (var i = 0; i < periods.length; i++)
                    ButtonSegment(value: i, label: Text(periods[i])),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
            Expanded(
              child: AsyncBody<List<LedgerEntry>>(
                value: ledgerAsync,
                builder: (ledger) {
                  if (ledger.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 40),
                      BigEmptyState(
                        icon: Icons.bar_chart_rounded,
                        title: context.tr('no_stats'),
                        message: context.tr('no_stats_sub'),
                      ),
                    ]);
                  }
                  final (start, end) = _range();
                  final inRange = [
                    for (final e in ledger)
                      if (!e.date.isBefore(start) && e.date.isBefore(end)) e,
                  ];
                  var income = 0;
                  var expense = 0;
                  for (final e in inRange) {
                    if (e.type == TxType.income) {
                      income += e.amountMinor;
                    } else {
                      expense += e.amountMinor;
                    }
                  }
                  // Đường số dư: số dư luỹ kế tại từng mốc.
                  final sorted = [...ledger]..sort((a, b) => a.date.compareTo(b.date));
                  final marks = _marks(start, end);
                  final values = <double>[];
                  var acc = 0;
                  var p = 0;
                  for (final m in marks) {
                    while (p < sorted.length && sorted[p].date.isBefore(m)) {
                      acc += sorted[p].signedAmount;
                      p++;
                    }
                    values.add(acc / 100);
                  }
                  final agg = StatisticsAggregator.aggregate(ledger, start, end);
                  final slices =
                      _breakdown == TxType.expense ? agg.expenseByCategory : agg.incomeByCategory;
                  final labelFmt = _period == 3 ? DateFormat.MMM(loc) : DateFormat('dd/MM');

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, AppSpacing.bottomNav + 40),
                    children: [
                      // -------------------------------------------- Lưới 4 chỉ số
                      Row(children: [
                        Expanded(
                          child: _StatCard(
                            title: context.tr('income_total'),
                            value: '${income > 0 ? '+' : ''}${money(income)}',
                            color: AppColors.income,
                            icon: Icons.arrow_upward_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: context.tr('expense_total'),
                            value: '${expense > 0 ? '-' : ''}${money(expense)}',
                            color: AppColors.expense,
                            icon: Icons.arrow_downward_rounded,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _StatCard(
                            title: context.tr('cash_flow'),
                            value: money(income - expense),
                            color: AppColors.primary,
                            icon: Icons.account_balance_wallet_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            title: context.tr('transactions'),
                            value: '${inRange.length}',
                            color: AppColors.textSecondary,
                            icon: Icons.numbers_rounded,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      // -------------------------------------------- Biến động số dư
                      GlassCard(
                        radius: 28,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CardTitle(context.tr('balance_trend')),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 180,
                              child: values.length < 2
                                  ? Center(
                                      child: Text(context.tr('need_more_data'),
                                          style: const TextStyle(color: AppColors.hint)))
                                  : _TrendChart(values: values),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(labelFmt.format(marks.first.subtract(const Duration(days: 1))),
                                    style: const TextStyle(color: AppColors.hint, fontSize: 11)),
                                const Spacer(),
                                Text(money((values.last * 100).round()),
                                    style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12)),
                                const Spacer(),
                                Text(context.tr('today'),
                                    style: const TextStyle(color: AppColors.hint, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // -------------------------------------------- So sánh thu - chi
                      _IncomeExpenseBar(income: income, expense: expense, money: money),
                      const SizedBox(height: 24),
                      // -------------------------------------------- Thói quen
                      _InsightsCard(entries: inRange, days: end.difference(start).inDays),
                      const SizedBox(height: 24),
                      // -------------------------------------------- Xu hướng thu nhập
                      _MonthlyTrendCard(ledger: ledger),
                      const SizedBox(height: 24),
                      // -------------------------------------------- (Mới) theo danh mục
                      GlassCard(
                        radius: 28,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: _CardTitle(context.tr('by_category'))),
                                LiquidSegmented<TxType>(
                                  height: 36,
                                  segmentWidth: 76,
                                  segments: [
                                    ButtonSegment(
                                        value: TxType.expense, label: Text(context.tr('expense'))),
                                    ButtonSegment(
                                        value: TxType.income, label: Text(context.tr('income'))),
                                  ],
                                  selected: {_breakdown},
                                  onSelectionChanged: (s) => setState(() => _breakdown = s.first),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (slices.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                child: Text(context.tr('no_transactions'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: AppColors.hint)),
                              )
                            else
                              LayoutBuilder(builder: (context, c) {
                                final chart = DonutChart(
                                  size: math.min(200, c.maxWidth * 0.6),
                                  slices: [
                                    for (final s in slices)
                                      DonutSlice(
                                        s.amountMinor.toDouble(),
                                        Color(catMap[s.categoryId]?.color ?? 0xFF90A4AE),
                                        categoryLabel(context, catMap[s.categoryId]),
                                      ),
                                  ],
                                );
                                final legend = Column(
                                  children: [
                                    for (final s in slices.take(8))
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Row(
                                          children: [
                                            CategoryAvatar(
                                                category: catMap[s.categoryId], size: 30),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(categoryLabel(context, catMap[s.categoryId]),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                          fontWeight: FontWeight.w600)),
                                                  Text('${(s.ratio * 100).toStringAsFixed(1)}%',
                                                      style: const TextStyle(
                                                          color: AppColors.hint, fontSize: 12)),
                                                ],
                                              ),
                                            ),
                                            Text(money(s.amountMinor),
                                                style:
                                                    const TextStyle(fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                                if (c.maxWidth >= 560) {
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      chart,
                                      const SizedBox(width: 24),
                                      Expanded(child: legend),
                                    ],
                                  );
                                }
                                return Column(
                                    children: [chart, const SizedBox(height: 16), legend]);
                              }),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

/// Đường số dư có vùng tô gradient (vẽ tay, không cần package biểu đồ).
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values});
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => CustomPaint(
        size: Size.infinite,
        painter: _TrendPainter(values, Theme.of(context).colorScheme.primary, t),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color, this.progress);
  final List<double> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final span = math.max(maxV - minV, 1.0);
    final h = size.height - 8;
    final pts = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          i * size.width / (values.length - 1),
          4 + h - ((values[i] - minV) / span) * h * progress,
        ),
    ];
    // Đường cong mềm (Catmull-Rom -> Bezier).
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    final area = Path.from(line)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final last = pts.last;
    canvas.drawCircle(last, 6, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.color != color || old.progress != progress;
}

class _IncomeExpenseBar extends StatelessWidget {
  const _IncomeExpenseBar({required this.income, required this.expense, required this.money});
  final int income;
  final int expense;
  final String Function(int) money;

  @override
  Widget build(BuildContext context) {
    final total = math.max(income + expense, 1);
    final wi = math.max(income / total, 0.01);
    final we = math.max(expense / total, 0.01);
    Widget legend(Color c, String label, int v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(width: 6),
            Text(money(v), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        );
    return GlassCard(
      radius: 28,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(context.tr('income_vs_expense')),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 24,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.5, end: wi / (wi + we)),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, r, _) => Row(
                  children: [
                    Expanded(
                      flex: math.max(1, (r * 1000).round()),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: AppColors.incomeGradient)),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, ((1 - r) * 1000).round()),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: AppColors.expenseGradient)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            children: [
              legend(AppColors.income, context.tr('income_total'), income),
              legend(AppColors.expense, context.tr('expense_total'), expense),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.entries, required this.days});
  final List<LedgerEntry> entries;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = context.l10n.intlLocale;
    String peakHour = '--:--';
    String peakDay = '---';
    if (entries.isNotEmpty) {
      final hours = List<int>.filled(24, 0);
      final wd = List<int>.filled(8, 0);
      for (final e in entries) {
        hours[e.date.hour]++;
        wd[e.date.weekday]++;
      }
      var h = 0;
      for (var i = 1; i < 24; i++) {
        if (hours[i] > hours[h]) h = i;
      }
      var d = 1;
      for (var i = 2; i <= 7; i++) {
        if (wd[i] > wd[d]) d = i;
      }
      peakHour = '$h:00';
      // 2024-01-01 là thứ Hai -> ngày (weekday d) = 2024-01-(d).
      final s = DateFormat.EEEE(loc).format(DateTime(2024, 1, d));
      peakDay = s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    }
    final avg = days <= 0 ? 0.0 : entries.length / days;
    final avgText = avg >= 10 ? avg.toStringAsFixed(0) : avg.toStringAsFixed(1);

    Widget row(String label, String value, IconData icon, Color color) => Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ],
        );

    return GlassCard(
      radius: 28,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: _CardTitle(context.tr('tx_habits'))),
          const SizedBox(height: 20),
          row(context.tr('peak_hour'), peakHour, Icons.access_time_rounded, AppColors.sun),
          const Divider(height: 24),
          row(context.tr('peak_day'), peakDay, Icons.calendar_today_rounded, AppColors.violet),
          const Divider(height: 24),
          row(context.tr('avg_per_day'), context.tr('n_tx_short', {'n': avgText}),
              Icons.analytics_rounded, theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _MonthlyTrendCard extends StatelessWidget {
  const _MonthlyTrendCard({required this.ledger});
  final List<LedgerEntry> ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final thisStart = DateX.startOfMonth(now);
    final lastStart = DateTime(now.year, now.month - 1);
    var cur = 0;
    var prev = 0;
    for (final e in ledger) {
      if (e.type != TxType.income) continue;
      if (!e.date.isBefore(thisStart)) {
        cur += e.amountMinor;
      } else if (!e.date.isBefore(lastStart)) {
        prev += e.amountMinor;
      }
    }
    final String text;
    if (ledger.isEmpty) {
      text = context.tr('trend_empty');
    } else if (prev == 0) {
      text = context.tr('trend_start');
    } else if (cur > prev) {
      text = context.tr('trend_up', {'p': ((cur - prev) * 100 / prev).round()});
    } else if (cur < prev) {
      text = context.tr('trend_down', {'p': ((prev - cur) * 100 / prev).round()});
    } else {
      text = context.tr('trend_flat');
    }
    return GlassCard(
      radius: 28,
      tint: AppColors.sky,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.white,
            ),
            child: Icon(Icons.trending_up_rounded, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('income_trend'),
                    style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text(text,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.8)
                            : const Color(0xFF1E3A8A).withValues(alpha: 0.85),
                        fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
