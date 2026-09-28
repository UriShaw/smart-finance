import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_x.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../domain/entities/finance_transaction.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import '../auth/auth_controller.dart';
import '../home/home_screen.dart' show OverviewItem;
import 'transaction_detail_sheet.dart';
import 'transaction_tile.dart';

/// Lịch sử giao dịch theo bố cục app cũ: tiêu đề lớn + "Đặt lại" + nút lọc,
/// ô tìm kiếm, dải chip thời gian (Hôm nay/Tuần/Tháng/Năm | Tháng 1..12),
/// thẻ tóm tắt, danh sách nhóm theo ngày. Vẫn phân trang + tải thêm từ cloud.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  final List<FinanceTransaction> _items = [];
  final List<FinanceTransaction> _cloudItems = [];
  bool _loading = false;
  bool _hasMore = true;
  bool _cloudLoading = false;
  bool _cloudExhausted = false;
  int _loadedRevision = -1;
  TxSummary _summary = TxSummary.empty;

  // Bộ lọc (giống app cũ) + lọc mới theo loại / danh mục.
  int _quick = 0; // 0 = không, 1 hôm nay, 2 tuần này, 3 tháng này, 4 năm nay, 10+m = tháng m+1
  DateTime? _date;
  int? _month; // 1..12
  int? _year;
  int _amount = 0; // 0 tất cả, 1 < 100k, 2 < 500k, 3 > 1 triệu
  TxType? _type;
  String? _categoryId;

  bool get _timeFilterActive => _quick != 0 || _date != null || _month != null || _year != null;
  bool get _filterActive =>
      _timeFilterActive || _amount != 0 || _type != null || _categoryId != null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _range {
    final now = DateTime.now();
    if (_date != null) {
      final d = DateX.startOfDay(_date!);
      return (d, DateX.nextDay(d));
    }
    if (_month != null) {
      final y = _year ?? now.year;
      return (DateTime(y, _month!), DateTime(y, _month! + 1));
    }
    if (_year != null) return (DateTime(_year!), DateTime(_year! + 1));
    switch (_quick) {
      case 1:
        final d = DateX.startOfDay(now);
        return (d, DateX.nextDay(d));
      case 2:
        final s = DateX.startOfWeek(now);
        return (s, DateTime(s.year, s.month, s.day + 7));
      case 3:
        return (DateX.startOfMonth(now), DateX.startOfNextMonth(now));
      case 4:
        return (DateTime(now.year), DateTime(now.year + 1));
    }
    if (_quick >= 10) {
      final m = _quick - 10 + 1;
      return (DateTime(now.year, m), DateTime(now.year, m + 1));
    }
    return (null, null);
  }

  TxQuery get _query {
    final (from, to) = _range;
    return TxQuery(
      search: _search.text,
      type: _type,
      categoryId: _categoryId,
      from: from,
      to: to,
      maxMinor: switch (_amount) { 1 => 100000 * 100, 2 => 500000 * 100, _ => null },
      minMinor: _amount == 3 ? 1000000 * 100 : null,
    );
  }

  Future<void> _reload() async {
    _items.clear();
    _cloudItems.clear();
    _hasMore = true;
    _cloudExhausted = false;
    _loadedRevision = ref.read(dataRevisionProvider);
    unawaited(ref.read(transactionRepoProvider).summary(_query).then((s) {
      if (mounted) setState(() => _summary = s);
    }).catchError((_) {}));
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if ((_loading || !_hasMore) && !force) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(transactionRepoProvider).page(
            offset: _items.length,
            limit: AppConstants.historyPageSize,
            query: _query,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == AppConstants.historyPageSize;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFromCloud() async {
    final gw = ref.read(remoteGatewayProvider);
    if (gw == null) return;
    setState(() => _cloudLoading = true);
    try {
      final all = [..._items, ..._cloudItems];
      final before = all.isEmpty ? DateTime.now() : all.last.date;
      final rows = await gw.fetchTransactionsBefore(
        userId: ref.read(currentUserIdProvider),
        before: before,
        limit: AppConstants.historyPageSize,
      );
      final known = all.map((e) => e.id).toSet();
      final list =
          rows.map(TransactionRepository.fromRemote).where((t) => !known.contains(t.id)).toList();
      if (!mounted) return;
      setState(() {
        _cloudItems.addAll(list);
        _cloudExhausted = rows.length < AppConstants.historyPageSize;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
    setState(() {});
  }

  void _setQuick(int v) {
    setState(() {
      _quick = _quick == v ? 0 : v;
      _date = null;
      _month = null;
      _year = null;
    });
    _reload();
  }

  void _resetFilters() {
    setState(() {
      _quick = 0;
      _date = null;
      _month = null;
      _year = null;
      _amount = 0;
      _type = null;
      _categoryId = null;
    });
    _reload();
  }

  Future<void> _openFilter(List<TxCategory> cats) async {
    final r = await showGlassSheet<_FilterResult>(
      context: context,
      builder: (_) => _FilterSheet(
        initial: _FilterResult(
          date: _date,
          month: _month,
          year: _year,
          amount: _amount,
          type: _type,
          categoryId: _categoryId,
        ),
        categories: cats,
      ),
    );
    if (r == null || !mounted) return;
    setState(() {
      _date = r.date;
      _month = r.month;
      _year = r.year;
      _amount = r.amount;
      _type = r.type;
      _categoryId = r.categoryId;
      if (r.date != null || r.month != null || r.year != null) _quick = 0;
    });
    await _reload();
  }

  String _dayLabel(BuildContext context, DateTime day) {
    final today = DateX.startOfDay(DateTime.now());
    if (DateX.sameDay(day, today)) return context.tr('today');
    if (DateX.sameDay(day, today.subtract(const Duration(days: 1)))) {
      return context.tr('yesterday');
    }
    final s = DateFormat('EEEE, dd/MM/yyyy', context.l10n.intlLocale).format(day);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    // Dữ liệu đổi (thêm/sửa/xóa/đồng bộ) -> tải lại danh sách.
    ref.listen<int>(dataRevisionProvider, (prev, next) {
      if (next != _loadedRevision) _reload();
    });
    final theme = Theme.of(context);
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <TxCategory>[];
    final catMap = ref.watch(categoryMapProvider).valueOrNull ?? const {};
    final archived = ref.watch(archivedCountProvider).valueOrNull ?? 0;
    final canCloud = ref.watch(isCloudUserProvider) && ref.watch(remoteGatewayProvider) != null;
    final all = [..._items, ..._cloudItems];
    String money(int v) => formatMoney(ref, context, v);

    // Danh sách phẳng: tiêu đề ngày + giao dịch.
    final rows = <Object>[];
    DateTime? cur;
    for (var i = 0; i < all.length; i++) {
      final d = DateX.startOfDay(all[i].date);
      if (cur == null || !DateX.sameDay(cur, d)) {
        cur = d;
        var inc = 0;
        var exp = 0;
        for (final t in all) {
          if (!DateX.sameDay(t.date, d)) continue;
          if (t.type == TxType.income) {
            inc += t.amountMinor;
          } else {
            exp += t.amountMinor;
          }
        }
        rows.add(_DayHeader(d, inc, exp));
      }
      rows.add(i);
    }

    final monthNames = [
      for (var m = 1; m <= 12; m++) context.tr('month_n', {'n': m})
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ContentWidth(
        max: 860,
        child: Column(
          children: [
            // ---------------------------------------------------- Tiêu đề
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(context.tr('history_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800, fontSize: 26)),
                  ),
                  if (_filterActive)
                    TextButton(
                      onPressed: _resetFilters,
                      style: TextButton.styleFrom(foregroundColor: AppColors.expense),
                      child: Text(context.tr('reset'),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  Badge(
                    isLabelVisible: _filterActive,
                    smallSize: 9,
                    backgroundColor: AppColors.primary,
                    child: GlassCircleButton(
                      icon: Icons.filter_list_rounded,
                      tooltip: context.tr('advanced_filter'),
                      size: 42,
                      onPressed: () => _openFilter(cats),
                    ),
                  ),
                ],
              ),
            ),
            // ---------------------------------------------------- Tìm kiếm
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.tr('search_tx'),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.hint),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.tr('clear'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            _onSearchChanged('');
                          },
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.14)
                            : AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
                  ),
                ),
              ),
            ),
            // ---------------------------------------------------- Chip thời gian
            SizedBox(
              height: 58,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                children: [
                  for (final (i, key) in const [
                    (1, 'today'),
                    (2, 'this_week'),
                    (3, 'this_month'),
                    (4, 'this_year'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GlassChip(
                        label: context.tr(key),
                        selected: _quick == i,
                        onTap: () => _setQuick(i),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                    child: VerticalDivider(width: 1, color: theme.dividerTheme.color),
                  ),
                  for (var m = 0; m < 12; m++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GlassChip(
                        label: monthNames[m],
                        selected: _quick == 10 + m,
                        onTap: () => _setQuick(10 + m),
                      ),
                    ),
                ],
              ),
            ),
            // ---------------------------------------------------- Danh sách
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await ref.read(syncEngineProvider).syncNow(force: true);
                  await _reload();
                },
                child: all.isEmpty && !_loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 40),
                          BigEmptyState(
                            icon: Icons.account_balance_wallet_rounded,
                            title: context.tr(_filterActive || _search.text.isNotEmpty
                                ? 'no_tx_filter'
                                : 'no_tx_yet'),
                            message: context.tr('no_tx_yet_sub'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.bottomNav + 60),
                        itemCount: rows.length + 2,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8, top: 4),
                              child: GlassCard(
                                radius: 24,
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  children: [
                                    Row(children: [
                                      OverviewItem(
                                          label: context.tr('tx_count_label'),
                                          value: '${_summary.count}'),
                                      OverviewItem(
                                          label: context.tr('net_flow'),
                                          value: money(_summary.netMinor)),
                                    ]),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 14),
                                      child: Divider(height: 1),
                                    ),
                                    Row(children: [
                                      OverviewItem(
                                          label: context.tr('income_total'),
                                          value: '+${money(_summary.incomeMinor)}',
                                          color: AppColors.income),
                                      OverviewItem(
                                          label: context.tr('expense_total'),
                                          value: '-${money(_summary.expenseMinor)}',
                                          color: AppColors.expense),
                                    ]),
                                  ],
                                ),
                              ),
                            );
                          }
                          final k = i - 1;
                          if (k < rows.length) {
                            final r = rows[k];
                            if (r is _DayHeader) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 14, bottom: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(_dayLabel(context, r.day),
                                          style: theme.textTheme.labelLarge?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: theme.colorScheme.onSurfaceVariant)),
                                    ),
                                    if (r.income > 0)
                                      Text('+${money(r.income)}',
                                          style: const TextStyle(
                                              color: AppColors.income,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                    if (r.income > 0 && r.expense > 0) const SizedBox(width: 8),
                                    if (r.expense > 0)
                                      Text('-${money(r.expense)}',
                                          style: const TextStyle(
                                              color: AppColors.expense,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              );
                            }
                            final idx = r as int;
                            final t = all[idx];
                            final isCloud = idx >= _items.length;
                            return Opacity(
                              opacity: isCloud ? 0.85 : 1,
                              child: TransactionTile(
                                tx: t,
                                category: catMap[t.categoryId],
                                onTap: isCloud
                                    ? null
                                    : () => showTransactionDetail(context, t, catMap[t.categoryId]),
                              ),
                            );
                          }
                          if (_loading) {
                            return const Padding(
                              padding: EdgeInsets.all(AppSpacing.lg),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (!_hasMore && canCloud && !_cloudExhausted && _query.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                              child: GlassCard(
                                child: Column(
                                  children: [
                                    if (archived > 0)
                                      Text(context.tr('archived_note', {'n': archived}),
                                          textAlign: TextAlign.center),
                                    const SizedBox(height: AppSpacing.sm),
                                    OutlinedButton.icon(
                                      onPressed: _cloudLoading ? null : _loadFromCloud,
                                      icon: _cloudLoading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.cloud_download_outlined),
                                      label: Text(context.tr('load_more_cloud')),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return const SizedBox(height: AppSpacing.lg);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader {
  const _DayHeader(this.day, this.income, this.expense);
  final DateTime day;
  final int income;
  final int expense;
}

class _FilterResult {
  const _FilterResult({
    this.date,
    this.month,
    this.year,
    this.amount = 0,
    this.type,
    this.categoryId,
  });
  final DateTime? date;
  final int? month;
  final int? year;
  final int amount;
  final TxType? type;
  final String? categoryId;
}

/// "Bộ lọc nâng cao" (như app cũ) + lọc theo loại và danh mục (mới).
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.categories});
  final _FilterResult initial;
  final List<TxCategory> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateTime? _date = widget.initial.date;
  late int? _month = widget.initial.month;
  late int? _year = widget.initial.year;
  late int _amount = widget.initial.amount;
  late TxType? _type = widget.initial.type;
  late String? _categoryId = widget.initial.categoryId;

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _pickButton(String label, VoidCallback onTap, bool active) => Expanded(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 46),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(
                color: active ? AppColors.primary : AppColors.border, width: active ? 1.6 : 1),
            foregroundColor: active ? AppColors.primary : null,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final validCat = widget.categories.any((c) => c.id == _categoryId) ? _categoryId : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('advanced_filter'),
              style:
                  Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _section(
            context.tr('specific_time'),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _pickButton(
                      _date == null
                          ? context.tr('pick_day')
                          : DateFormat('dd/MM/yyyy').format(_date!),
                      () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _date ?? now,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(now.year + 5),
                        );
                        if (d != null) {
                          setState(() {
                            _date = d;
                            _month = null;
                            _year = null;
                          });
                        }
                      },
                      _date != null,
                    ),
                    const SizedBox(width: 10),
                    _pickButton(
                      _month == null
                          ? context.tr('pick_month')
                          : context.tr('month_n', {'n': _month!}),
                      () async {
                        final o = await showLiquidPicker<int>(
                          context: context,
                          title: context.tr('pick_month'),
                          selected: _month ?? 0,
                          options: [
                            for (var m = 1; m <= 12; m++)
                              LiquidOption(m, context.tr('month_n', {'n': m})),
                          ],
                        );
                        if (o != null) {
                          setState(() {
                            _month = o.value;
                            _date = null;
                          });
                        }
                      },
                      _month != null,
                    ),
                    const SizedBox(width: 10),
                    _pickButton(
                      _year == null ? context.tr('pick_year') : '$_year',
                      () async {
                        final o = await showLiquidPicker<int>(
                          context: context,
                          title: context.tr('pick_year'),
                          selected: _year ?? 0,
                          options: [
                            for (var i = 0; i < 6; i++)
                              LiquidOption(now.year - i, '${now.year - i}'),
                          ],
                        );
                        if (o != null) {
                          setState(() {
                            _year = o.value;
                            _date = null;
                          });
                        }
                      },
                      _year != null,
                    ),
                  ],
                ),
                if (_date != null || _month != null || _year != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _date = null;
                      _month = null;
                      _year = null;
                    }),
                    style: TextButton.styleFrom(foregroundColor: AppColors.expense),
                    child: Text(context.tr('clear_time_filter')),
                  ),
              ],
            ),
          ),
          _section(
            context.tr('amount_range'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, key) in const [
                  (0, 'all'),
                  (1, 'under_100k'),
                  (2, 'under_500k'),
                  (3, 'over_1m'),
                ])
                  GlassChip(
                    label: context.tr(key),
                    selected: _amount == i,
                    onTap: () => setState(() => _amount = i),
                  ),
              ],
            ),
          ),
          _section(
            context.tr('type'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GlassChip(
                    label: context.tr('all'),
                    selected: _type == null,
                    onTap: () => setState(() => _type = null)),
                GlassChip(
                    label: context.tr('expense'),
                    icon: Icons.north_east_rounded,
                    selected: _type == TxType.expense,
                    onTap: () => setState(() => _type = TxType.expense)),
                GlassChip(
                    label: context.tr('income'),
                    icon: Icons.south_west_rounded,
                    selected: _type == TxType.income,
                    onTap: () => setState(() => _type = TxType.income)),
              ],
            ),
          ),
          _section(
            context.tr('tx_category'),
            LabeledDropdown<String?>(
              label: context.tr('tx_category'),
              value: validCat,
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(context.tr('all'))),
                for (final c in widget.categories)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Row(
                      children: [
                        CategoryAvatar(category: c, size: 24),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(categoryLabel(context, c), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_FilterResult(
                date: _date,
                month: _month,
                year: _year,
                amount: _amount,
                type: _type,
                categoryId: validCat,
              )),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              child: Text(context.tr('apply_filter')),
            ),
          ),
        ],
      ),
    );
  }
}
