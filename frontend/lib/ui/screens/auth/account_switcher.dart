import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../../logic/auth/account_vault.dart';
import '../../../logic/auth/auth_controller.dart';
import '../../../logic/auth/auth_errors.dart';

/// Danh sách tài khoản đã đăng nhập trên máy (kiểu Gmail): bấm để chuyển ngay,
/// dữ liệu mỗi tài khoản tách riêng. [showAdd]: thêm dòng "+ Thêm tài khoản".
class AccountSwitcher extends ConsumerStatefulWidget {
  const AccountSwitcher({super.key, this.showAdd = true, this.hideCurrent = false});

  final bool showAdd;

  /// Ẩn tài khoản đang dùng (màn đăng nhập khi đang thêm tài khoản).
  final bool hideCurrent;

  @override
  ConsumerState<AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends ConsumerState<AccountSwitcher> {
  String? _switching;

  Future<void> _switch(SavedAccount a) async {
    if (_switching != null) return;
    setState(() => _switching = a.userId);
    try {
      await ref.read(sessionProvider.notifier).switchTo(a.userId);
      if (mounted) showSnack(context, context.tr('account_switched', {'n': a.label}));
    } catch (e) {
      if (mounted) showSnack(context, context.tr(authErrorKey(e)));
    } finally {
      if (mounted) setState(() => _switching = null);
    }
  }

  Future<void> _forget(SavedAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('account_forget')),
        content: Text(ctx.tr('account_forget_confirm', {'n': a.label})),
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
    if (ok == true) await ref.read(sessionProvider.notifier).forgetAccount(a.userId);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final all = ref.watch(savedAccountsProvider).valueOrNull ?? const <SavedAccount>[];
    final accounts = widget.hideCurrent
        ? all.where((a) => a.userId != session.userId || !session.isCloud).toList()
        : all;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (accounts.isEmpty && !widget.showAdd) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in accounts)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: _Avatar(account: a),
            title: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: a.email == null || a.email == a.label
                ? null
                : Text(a.email!, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _switching == a.userId
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : session.isCloud && session.userId == a.userId
                    ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                    : IconButton(
                        tooltip: context.tr('account_forget'),
                        icon: Icon(Icons.close_rounded, color: muted),
                        onPressed: () => _forget(a),
                      ),
            onTap: session.isCloud && session.userId == a.userId ? null : () => _switch(a),
          ),
        if (widget.showAdd)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.person_add_alt_1_rounded, color: theme.colorScheme.primary),
            ),
            title: Text(context.tr('account_add')),
            subtitle: Text(context.tr('account_add_sub'), style: TextStyle(color: muted)),
            onTap: () => ref.read(sessionProvider.notifier).addAccount(),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.account});
  final SavedAccount account;

  @override
  Widget build(BuildContext context) {
    final url = account.avatarUrl;
    final initial = account.label.characters.first.toUpperCase();
    return CircleAvatar(
      backgroundColor: AppColors.lightBlue,
      foregroundImage: url == null || url.isEmpty ? null : NetworkImage(url),
      child: Text(initial,
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
    );
  }
}
