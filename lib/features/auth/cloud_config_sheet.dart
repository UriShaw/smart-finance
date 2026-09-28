import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/liquid.dart';
import '../settings/settings_controller.dart';
import 'auth_controller.dart';
import 'auth_errors.dart';
import 'cloud_config.dart';

/// Bảng "Máy chủ đồng bộ": dán Project URL + publishable key của Supabase
/// để điện thoại/máy tính kết nối cloud mà không cần build lại app.
Future<void> showCloudConfigSheet(BuildContext context) {
  return showGlassSheet<void>(context: context, builder: (_) => const _CloudConfigSheet());
}

class _CloudConfigSheet extends ConsumerStatefulWidget {
  const _CloudConfigSheet();

  @override
  ConsumerState<_CloudConfigSheet> createState() => _CloudConfigSheetState();
}

class _CloudConfigSheetState extends ConsumerState<_CloudConfigSheet> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  bool _busy = false;
  bool _showKey = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: Env.supabaseUrl);
    _key = TextEditingController(text: Env.supabaseAnonKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _paste(TextEditingController c) async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim() ?? '';
    if (t.isNotEmpty) setState(() => c.text = t);
  }

  void _applied(bool live) {
    // Dựng lại phiên đăng nhập / đồng bộ theo máy chủ mới.
    ref.read(cloudRevisionProvider.notifier).state++;
    final nav = Navigator.of(context);
    showSnack(context, context.tr(live ? 'server_connected' : 'server_restart'));
    nav.pop();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prefs = ref.read(sharedPrefsProvider);
      final live = await CloudConfig.connect(prefs, _url.text, _key.text);
      await ref.read(settingsProvider.notifier).setOfflineChosen(false);
      if (mounted) _applied(live);
    } catch (e) {
      if (mounted) setState(() => _error = context.tr(authErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      final live = await CloudConfig.disconnect(ref.read(sharedPrefsProvider));
      if (mounted) _applied(live);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final saved = CloudConfig.hasSaved(ref.read(sharedPrefsProvider));
    final host = CloudConfig.hostOf(Env.supabaseUrl) ?? '';
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('server_title'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(context.tr('server_sub'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color:
                  (Env.cloudReady ? AppColors.income : AppColors.warning).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Env.cloudReady ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                    color: Env.cloudReady ? AppColors.income : AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Env.cloudReady
                        ? context.tr('server_status_on', {'h': host})
                        : context.tr('server_status_off'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: context.tr('server_url'),
              hintText: 'https://xxxx.supabase.co',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: context.tr('paste'),
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () => _paste(_url),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            autocorrect: false,
            obscureText: !_showKey,
            maxLines: 1,
            decoration: InputDecoration(
              labelText: context.tr('server_key'),
              hintText: 'sb_publishable_…',
              helperText: context.tr('server_key_help'),
              helperMaxLines: 3,
              prefixIcon: const Icon(Icons.key_rounded),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.tr('show'),
                    icon: Icon(_showKey ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                  IconButton(
                    tooltip: context.tr('paste'),
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: () => _paste(_key),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy || session.isCloud ? null : _connect,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_rounded),
            label: Text(context.tr('server_connect')),
          ),
          if (saved && !session.isCloud) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off_rounded),
              label: Text(context.tr('server_disconnect')),
            ),
          ],
          if (session.isCloud) ...[
            const SizedBox(height: 8),
            Text(context.tr('server_signout_first'),
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 10),
          Text(context.tr('server_guide_hint'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.35)),
        ],
      ),
    );
  }
}
