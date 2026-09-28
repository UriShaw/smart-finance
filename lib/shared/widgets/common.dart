import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/app_error.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../features/settings/settings_controller.dart';
import 'liquid.dart';

/// Bảng icon cho danh mục (tên lưu trong DB -> IconData hằng số).
const Map<String, IconData> kCategoryIcons = {
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'shopping_bag': Icons.shopping_bag,
  'receipt_long': Icons.receipt_long,
  'movie': Icons.movie,
  'favorite': Icons.favorite,
  'school': Icons.school,
  'home': Icons.home,
  'category': Icons.category,
  'payments': Icons.payments,
  'card_giftcard': Icons.card_giftcard,
  'trending_up': Icons.trending_up,
  'savings': Icons.savings,
  'local_cafe': Icons.local_cafe,
  'pets': Icons.pets,
  'flight': Icons.flight,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'phone_iphone': Icons.phone_iphone,
  'child_care': Icons.child_care,
  'local_gas_station': Icons.local_gas_station,
  'work': Icons.work,
  'volunteer_activism': Icons.volunteer_activism,
  'account_balance': Icons.account_balance,
};

IconData categoryIcon(String? name) => kCategoryIcons[name] ?? Icons.category;

const List<int> kCategoryColors = [
  0xFFFF6B6B,
  0xFFFF9F43,
  0xFFFFC940,
  0xFF00E5A0,
  0xFF00C48C,
  0xFF00D2FF,
  0xFF3D7BFF,
  0xFF7C4DFF,
  0xFFB14DFF,
  0xFFFF4FD8,
  0xFFFF3D71,
  0xFF14B8A6,
  0xFF84CC16,
  0xFF8D6E63,
];

String categoryLabel(BuildContext context, TxCategory? c) {
  if (c == null) return context.tr('category_uncategorized');
  if (c.name.isNotEmpty) return c.name;
  if (c.defaultKey != null) return context.tr(c.defaultKey!);
  return context.tr('category_uncategorized');
}

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final TxCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF90A4AE);
    final hsl = HSLColor.fromColor(color);
    final light = hsl
        .withLightness((hsl.lightness + 0.14).clamp(0.0, 0.85).toDouble())
        .withSaturation((hsl.saturation + 0.1).clamp(0.0, 1.0).toDouble())
        .toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, color],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Icon(categoryIcon(category?.icon), color: Colors.white, size: size * 0.52),
    );
  }
}

/// Hiển thị số tiền có màu + dấu (không chỉ dựa vào màu - spec E accessibility).
class AmountText extends ConsumerWidget {
  const AmountText({
    super.key,
    required this.minor,
    this.type,
    this.style,
    this.signed = true,
  });

  final int minor;
  final TxType? type;
  final TextStyle? style;
  final bool signed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(settingsProvider.select((s) => s.currency));
    final l = context.l10n;
    final value = type == TxType.expense ? -minor : minor;
    final text =
        Money.format(value, currency, locale: l.intlLocale, signed: signed && type != null);
    final color =
        type == null ? null : (type == TxType.income ? AppColors.income : AppColors.expense);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (style ?? Theme.of(context).textTheme.titleMedium)
          ?.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

String formatMoney(WidgetRef ref, BuildContext context, int minor) {
  final c = ref.read(settingsProvider).currency;
  return Money.format(minor, c, locale: context.l10n.intlLocale);
}

String formatDate(BuildContext context, DateTime d, {bool withTime = false}) {
  final loc = context.l10n.intlLocale;
  return withTime ? DateFormat.yMd(loc).add_Hm().format(d) : DateFormat.yMMMd(loc).format(d);
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: AppSpacing.md),
            Text(message,
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

/// Trạng thái trống kiểu app cũ: vòng tròn xanh nhạt + icon lớn + tiêu đề + mô tả.
class BigEmptyState extends StatelessWidget {
  const BigEmptyState({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? AppColors.primary.withValues(alpha: 0.2) : AppColors.lightBlue,
              ),
              child: Icon(icon, size: 60, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: AppSpacing.sm),
            Text(context.tr(e.messageKey), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(onPressed: onRetry, child: Text(context.tr('retry'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hiển thị AsyncValue gọn: loading / error / data.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.md, 4, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style:
                    Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('delete_confirm_title')),
      content: Text(ctx.tr('delete_confirm_msg')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('delete'))),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, Object error) {
  final e = AppError.from(error);
  showSnack(context, context.tr(e.messageKey));
}

/// Giới hạn độ rộng nội dung trên tablet/desktop (responsive, không fixed width).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.max = 920});
  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }
}

/// Ô chọn có nhãn: chạm để mở bảng kính chọn giá trị (thay cho menu thả xuống).
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    DropdownMenuItem<T>? current;
    for (final i in items) {
      if (i.value == value) current = i;
    }
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () async {
          final picked = await showLiquidPicker<T>(
            context: context,
            title: label,
            selected: value,
            options: [
              for (final i in items)
                if (i.value is T) LiquidOption<T>(i.value as T, '', child: i.child),
            ],
          );
          if (picked != null) onChanged(picked.value);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.unfold_more_rounded),
          ),
          isEmpty: current == null,
          child: current?.child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Nhóm cài đặt kính (giữ tên cũ, dùng giao diện Liquid mới).
class GlassSection extends StatelessWidget {
  const GlassSection({super.key, required this.children, this.title, this.footer});
  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      LiquidSection(title: title, footer: footer, children: children);
}
