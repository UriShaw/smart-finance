import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/common.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/liquid.dart';
import '../../shared/widgets/glass.dart';
import '../auth/auth_controller.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  TxType _type = TxType.expense;

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('categories'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text(context.tr('add_category')),
      ),
      body: ContentWidth(
        max: 760,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: LiquidSegmented<TxType>(
                segments: [
                  ButtonSegment(value: TxType.expense, label: Text(context.tr('expense'))),
                  ButtonSegment(value: TxType.income, label: Text(context.tr('income'))),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: AsyncBody<List<TxCategory>>(
                value: cats,
                builder: (list) {
                  final items = list.where((c) => c.type == _type).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md, 0, AppSpacing.md, AppSpacing.bottomNav + 40),
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Column(
                          children: [
                            for (final c in items)
                              ListTile(
                                leading: CategoryAvatar(category: c),
                                title: Text(categoryLabel(context, c)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _edit(c),
                              ),
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

  Future<void> _edit(TxCategory? existing) async {
    final nameCtrl =
        TextEditingController(text: existing == null ? '' : categoryLabel(context, existing));
    var icon = existing?.icon ?? 'category';
    var color = existing?.color ?? kCategoryColors.first;
    final type = existing?.type ?? _type;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(ctx.tr(existing == null ? 'add_category' : 'edit_category')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(labelText: ctx.tr('category_name')),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(ctx.tr('category_icon')),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in kCategoryIcons.entries)
                        ChoiceChip(
                          label: Icon(e.value, size: 20),
                          selected: icon == e.key,
                          onSelected: (_) => setD(() => icon = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(ctx.tr('category_color')),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in kCategoryColors)
                        Semantics(
                          button: true,
                          selected: color == c,
                          child: InkWell(
                            onTap: () => setD(() => color = c),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: color == c
                                    ? Border.all(
                                        color: Theme.of(ctx).colorScheme.onSurface, width: 3)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text(ctx.tr('delete')),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(ctx.tr('save'))),
          ],
        ),
      ),
    );
    final name = nameCtrl.text;
    nameCtrl.dispose();
    if (!mounted || result == null) return;
    final repo = ref.read(categoryRepoProvider);
    try {
      if (result == 'delete' && existing != null) {
        if (!await confirmDelete(context)) return;
        await repo.delete(existing.id);
        return;
      }
      final now = DateTime.now();
      // Đổi tên danh mục mặc định: nếu giữ nguyên nhãn dịch thì lưu name rỗng
      // để vẫn hiển thị đúng ngôn ngữ.
      final unchangedDefault =
          existing?.defaultKey != null && name.trim() == context.tr(existing!.defaultKey!);
      final c = existing == null
          ? TxCategory(
              id: Ids.newId(),
              userId: ref.read(currentUserIdProvider),
              name: name,
              type: type,
              icon: icon,
              color: color,
              sortOrder: 100,
              createdAt: now,
              updatedAt: now,
            )
          : existing.copyWith(
              name: unchangedDefault ? '' : name,
              icon: icon,
              color: color,
            );
      await repo.save(c);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}
