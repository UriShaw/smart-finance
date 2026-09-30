import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../../logic/state/app_providers.dart';
import '../../../logic/auth/auth_controller.dart';

/// Hỏi lại trước khi đăng xuất (như app cũ).
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final pending = ref.read(syncStatusProvider).valueOrNull?.pendingCount ?? 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('sign_out')),
      content: Text(
          pending > 0 ? ctx.tr('sign_out_pending', {'n': pending}) : ctx.tr('sign_out_confirm')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.expense),
          child: Text(ctx.tr('confirm')),
        ),
      ],
    ),
  );
  if (ok == true) await ref.read(sessionProvider.notifier).signOut();
}
