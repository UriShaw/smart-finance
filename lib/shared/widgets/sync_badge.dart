import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/sync_engine.dart';
import '../providers/app_providers.dart';

/// Chip trạng thái đồng bộ; bấm để đồng bộ ngay.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(syncStatusProvider).valueOrNull ?? SyncSnapshot.initial;
    final (icon, color, key) = switch (snap.phase) {
      SyncPhase.idle => (Icons.cloud_done_outlined, AppColors.income, 'sync_status_idle'),
      SyncPhase.syncing => (Icons.sync, AppColors.seed, 'sync_status_syncing'),
      SyncPhase.offline => (Icons.cloud_off_outlined, AppColors.warning, 'sync_status_offline'),
      SyncPhase.disabled => (Icons.phone_android, Colors.grey, 'sync_status_disabled'),
      SyncPhase.error => (Icons.sync_problem, AppColors.expense, 'sync_status_error'),
    };
    final label = context.tr(key);
    final pending = snap.pendingCount;
    final tooltip =
        pending > 0 ? '$label\n${context.tr('pending_changes', {'n': pending})}' : label;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => ref.read(syncEngineProvider).syncNow(force: true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                if (pending > 0) ...[
                  const SizedBox(width: 4),
                  Text('$pending', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ],
                if (!compact) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
