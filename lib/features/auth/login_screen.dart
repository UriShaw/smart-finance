import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import 'account_switcher.dart';
import 'auth_controller.dart';
import 'auth_errors.dart';

enum _Mode { signIn, signUp }

/// Đăng nhập: email + mật khẩu (đăng ký / quên mật khẩu), Google, hoặc dùng offline.
/// Chân trang hiển thị máy chủ đang kết nối + nút đổi máy chủ.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _showPw = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  String? _validateEmail(String? v) =>
      _emailRe.hasMatch((v ?? '').trim()) ? null : context.tr('auth_bad_email');

  String? _validatePassword(String? v) =>
      (v ?? '').length >= 6 ? null : context.tr('auth_weak_password');

  Future<void> _run(Future<void> Function() job) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _error = context.tr(authErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(sessionProvider.notifier);
    await _run(() async {
      if (_mode == _Mode.signIn) {
        await ctrl.signInWithEmail(_email.text, _password.text);
      } else {
        final needConfirm = await ctrl.signUpWithEmail(_name.text, _email.text, _password.text);
        if (needConfirm && mounted) {
          setState(() {
            _mode = _Mode.signIn;
            _info = context.tr('auth_check_email', {'e': _email.text.trim()});
          });
        }
      }
    });
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (_validateEmail(email) != null) {
      setState(() => _error = context.tr('auth_enter_email_first'));
      return;
    }
    await _run(() => ref.read(sessionProvider.notifier).sendPasswordReset(email));
    if (!mounted || _error != null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _ResetDialog(email: email),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final nativeError = ref.watch(nativeGoogleErrorProvider);
    final ctrl = ref.read(sessionProvider.notifier);
    final theme = Theme.of(context);
    final cloud = Env.cloudReady;
    final busy = _busy || session.busy;
    final signUp = _mode == _Mode.signUp;
    final googleError = session.error != null ? context.tr('error_${session.error!.name}') : null;
    final error = _error ?? googleError;
    final saved = ref.watch(savedAccountsProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassCard(
                radius: AppRadius.lg,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppLogo(size: 80)),
                        const SizedBox(height: AppSpacing.md),
                        Text(context.tr('app_name'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900, color: theme.colorScheme.primary)),
                        const SizedBox(height: 4),
                        Text(context.tr('login_subtitle'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: AppSpacing.lg),
                        if (!cloud) ...[
                          _Notice(
                            icon: Icons.cloud_off_rounded,
                            color: AppColors.warning,
                            text: context.tr('server_status_off'),
                          ),
                        ] else ...[
                          // Tài khoản đã đăng nhập trên máy: bấm để vào lại ngay (không cần mật khẩu).
                          if (saved.isNotEmpty) ...[
                            Text(context.tr('accounts_on_device'),
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            const AccountSwitcher(showAdd: false),
                            const Divider(height: AppSpacing.lg),
                            Text(context.tr('account_other'),
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          LiquidSegmented<_Mode>(
                            segments: [
                              ButtonSegment(
                                  value: _Mode.signIn, label: Text(context.tr('auth_sign_in'))),
                              ButtonSegment(
                                  value: _Mode.signUp, label: Text(context.tr('auth_sign_up'))),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) => setState(() {
                              _mode = s.first;
                              _error = null;
                              _info = null;
                            }),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          if (signUp) ...[
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              decoration: InputDecoration(
                                labelText: context.tr('auth_name'),
                                prefixIcon: const Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            validator: _validateEmail,
                            decoration: InputDecoration(
                              labelText: context.tr('auth_email'),
                              prefixIcon: const Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _password,
                            obscureText: !_showPw,
                            textInputAction: signUp ? TextInputAction.next : TextInputAction.done,
                            autofillHints: [
                              signUp ? AutofillHints.newPassword : AutofillHints.password
                            ],
                            validator: _validatePassword,
                            onFieldSubmitted: (_) => signUp ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: context.tr('auth_password'),
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: context.tr('show'),
                                icon: Icon(_showPw
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded),
                                onPressed: () => setState(() => _showPw = !_showPw),
                              ),
                            ),
                          ),
                          if (signUp) ...[
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _confirm,
                              obscureText: !_showPw,
                              textInputAction: TextInputAction.done,
                              validator: (v) =>
                                  v == _password.text ? null : context.tr('auth_password_mismatch'),
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: context.tr('auth_password_confirm'),
                                prefixIcon: const Icon(Icons.lock_reset_rounded),
                              ),
                            ),
                          ],
                          if (!signUp)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: busy ? null : _forgot,
                                child: Text(context.tr('auth_forgot')),
                              ),
                            )
                          else
                            const SizedBox(height: AppSpacing.md),
                          if (_info != null) ...[
                            _Notice(
                                icon: Icons.mark_email_read_rounded,
                                color: AppColors.income,
                                text: _info!),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          if (error != null) ...[
                            _Notice(
                                icon: Icons.error_outline_rounded,
                                color: theme.colorScheme.error,
                                text: error),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          FilledButton(
                            onPressed: busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(context.tr(signUp ? 'auth_create' : 'auth_sign_in')),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child:
                                    Text(context.tr('auth_or'), style: theme.textTheme.bodySmall),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          OutlinedButton.icon(
                            onPressed: busy ? null : ctrl.signInWithGoogle,
                            icon: session.busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.g_mobiledata_rounded, size: 28),
                            label: Text(context.tr(session.busy ? 'signing_in' : 'sign_in_google')),
                          ),
                          if (nativeError != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            SelectableText(
                              context.tr('google_native_failed', {'code': nativeError}),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => ctrl.signInWithGoogle(browser: true),
                              child: Text(context.tr('sign_in_google_browser')),
                            ),
                          ],
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        TextButton.icon(
                          onPressed: busy ? null : ctrl.continueOffline,
                          icon: const Icon(Icons.wifi_off),
                          label: Text(context.tr('use_offline')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, height: 1.3))),
        ],
      ),
    );
  }
}

/// Nhập mã 6 số trong email + mật khẩu mới.
class _ResetDialog extends ConsumerStatefulWidget {
  const _ResetDialog({required this.email});
  final String email;

  @override
  ConsumerState<_ResetDialog> createState() => _ResetDialogState();
}

class _ResetDialogState extends ConsumerState<_ResetDialog> {
  final _code = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    if (_code.text.trim().length < 6) {
      setState(() => _error = context.tr('auth_bad_code'));
      return;
    }
    if (_pw.text.length < 6) {
      setState(() => _error = context.tr('auth_weak_password'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .resetPasswordWithCode(widget.email, _code.text, _pw.text);
      if (mounted) {
        showSnack(context, context.tr('auth_password_changed'));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = context.tr(authErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('auth_reset_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('auth_reset_sent', {'e': widget.email})),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: InputDecoration(labelText: context.tr('auth_code'), counterText: ''),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pw,
              obscureText: true,
              decoration: InputDecoration(labelText: context.tr('auth_new_password')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: _busy ? null : _ok,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('confirm')),
        ),
      ],
    );
  }
}

/// Mở từ link "quên mật khẩu" trong email (đã vào phiên khôi phục) -> đặt mật khẩu mới.
class NewPasswordDialog extends ConsumerStatefulWidget {
  const NewPasswordDialog({super.key});

  @override
  ConsumerState<NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends ConsumerState<NewPasswordDialog> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _ok() async {
    if (_pw.text.length < 6) {
      setState(() => _error = context.tr('auth_weak_password'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).updatePassword(_pw.text);
      if (mounted) {
        showSnack(context, context.tr('auth_password_changed'));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) setState(() => _error = context.tr(authErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('auth_new_password_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pw,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: context.tr('auth_new_password')),
            onSubmitted: (_) => _busy ? null : _ok(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: _busy ? null : _ok,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('confirm')),
        ),
      ],
    );
  }
}
