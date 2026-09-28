import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/storage/file_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/sync/sync_engine.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import '../../shared/widgets/sync_badge.dart';
import '../auth/auth_controller.dart';
import '../auth/cloud_config_sheet.dart';
import '../auth/account_switcher.dart';
import '../auth/sign_out_dialog.dart';
import '../bank/bank_channel.dart';
import '../bank/bank_controller.dart';
import '../bank/bank_settings_screen.dart';
import 'backup_actions.dart';
import 'settings_controller.dart';

/// Cài đặt theo bố cục app cũ: thẻ tài khoản -> Dịch vụ & Quyền hạn -> Âm thanh ->
/// Dữ liệu & Sao lưu -> (mới) Giao diện, Bảo mật -> Thông tin -> Đăng xuất.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Quay lại từ màn cấp quyền của Android -> cập nhật trạng thái quyền.
    _life = AppLifecycleListener(onResume: () {
      if (BankChannel.supported) ref.read(bankControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncStatusProvider).valueOrNull ?? SyncSnapshot.initial;
    final usage = ref.watch(storageUsageProvider).valueOrNull;
    final bank = BankChannel.supported ? ref.watch(bankControllerProvider).valueOrNull : null;
    final bankCtrl = ref.read(bankControllerProvider.notifier);
    final ch = ref.read(bankChannelProvider);
    final theme = Theme.of(context);

    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, AppSpacing.bottomNav + 40),
        children: [
          ContentWidth(
            max: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ------------------------------------------------ Tài khoản
                _AccountCard(
                  onSignIn: session.isCloud || session.busy
                      ? null
                      : Env.cloudReady
                          ? () => ref.read(sessionProvider.notifier).showLogin()
                          : () => showCloudConfigSheet(context),
                  onSignOut: session.isCloud ? () => confirmSignOut(context, ref) : null,
                ),

                // ------------------------------------------------ Chuyển tài khoản (kiểu Gmail)
                if (session.isCloud)
                  _OldSection(
                    icon: Icons.switch_account_rounded,
                    title: context.tr('accounts'),
                    children: const [AccountSwitcher()],
                  ),

                // ------------------------------------------------ Dịch vụ & Quyền hạn (Android)
                if (bank != null && bank.supported)
                  _OldSection(
                    icon: Icons.settings_suggest_rounded,
                    title: context.tr('services_permissions'),
                    children: [
                      _ActionRow(
                        icon: Icons.rocket_launch_rounded,
                        label: context.tr('autostart'),
                        onTap: ch.openAutostart,
                      ),
                      _ActionRow(
                        icon: Icons.refresh_rounded,
                        label: context.tr('restart_listener'),
                        onTap: () async {
                          await ch.restartListener();
                          if (context.mounted) {
                            showSnack(context, context.tr('restart_listener_done'));
                          }
                        },
                      ),
                      _ActionRow(
                        icon: Icons.record_voice_over_rounded,
                        label: context.tr('tts_settings'),
                        onTap: ch.openTtsSettings,
                      ),
                      _ActionRow(
                        icon: Icons.graphic_eq_rounded,
                        label: context.tr('bank_title'),
                        badge: context.tr('new_badge'),
                        onTap: () => push(const BankSettingsScreen()),
                      ),
                      const _SoftDivider(),
                      _SmallTitle(context.tr('granted_permissions')),
                      _PermissionRow(
                        label: context.tr('perm_notification'),
                        granted: bank.permission,
                        onTap: ch.openPermissionSettings,
                      ),
                      _PermissionRow(
                        label: context.tr('perm_battery'),
                        granted: bank.config.batteryIgnored,
                        onTap: ch.requestIgnoreBattery,
                      ),
                    ],
                  ),

                // ------------------------------------------------ Âm thanh (Android)
                if (bank != null && bank.supported)
                  _OldSection(
                    icon: Icons.volume_up_rounded,
                    title: context.tr('sound'),
                    children: [
                      _ToggleRow(
                        title: context.tr('bank_speak'),
                        value: bank.config.speak,
                        onChanged: bankCtrl.setSpeak,
                      ),
                      _ToggleRow(
                        title: context.tr('bank_speak_expense'),
                        value: bank.config.speakExpense,
                        onChanged: bank.config.speak ? bankCtrl.setSpeakExpense : null,
                      ),
                      _ToggleRow(
                        title: context.tr('volume_boost'),
                        subtitle: context.tr('volume_boost_sub'),
                        value: bank.config.volumeBoost,
                        onChanged: bankCtrl.setVolumeBoost,
                      ),
                      const _SoftDivider(),
                      _SmallTitle(context.tr('voice')),
                      Row(children: [
                        Expanded(
                          child: GlassChip(
                            expand: true,
                            icon: Icons.face_3_rounded,
                            label: context.tr('voice_female'),
                            selected: bank.config.voice != 'male',
                            onTap: () => bankCtrl.setVoice('female'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GlassChip(
                            expand: true,
                            icon: Icons.face_rounded,
                            label: context.tr('voice_male'),
                            selected: bank.config.voice == 'male',
                            onTap: () => bankCtrl.setVoice('male'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _SmallTitle(context.tr('chime')),
                      Row(children: [
                        for (final (v, key) in const [
                          ('default', 'chime_default'),
                          ('ting', 'chime_ting'),
                          ('none', 'chime_none'),
                        ]) ...[
                          if (v != 'default') const SizedBox(width: 8),
                          Expanded(
                            child: GlassChip(
                              expand: true,
                              label: context.tr(key),
                              selected: bank.config.chime == v,
                              onTap: () => bankCtrl.setChime(v),
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 16),
                      _SliderRow(
                        label: context.tr('speech_rate', {'p': (bank.config.rate * 100).round()}),
                        value: bank.config.rate,
                        onChanged: (v) => bankCtrl.setRate(v, persist: false),
                        onChangeEnd: (v) => bankCtrl.setRate(v),
                      ),
                      _SliderRow(
                        label: context.tr('speech_pitch', {'p': (bank.config.pitch * 100).round()}),
                        value: bank.config.pitch,
                        onChanged: (v) => bankCtrl.setPitch(v, persist: false),
                        onChangeEnd: (v) => bankCtrl.setPitch(v),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () => ch.preview(context.tr('bank_speak_sample')),
                          icon: const Icon(Icons.play_circle_fill_rounded),
                          label: Text(context.tr('bank_speak_test')),
                        ),
                      ),
                    ],
                  ),

                // ------------------------------------------------ Dữ liệu & Sao lưu
                _OldSection(
                  icon: Icons.cloud_sync_rounded,
                  title: context.tr('data_backup'),
                  children: [
                    _ActionRow(
                      icon: Icons.dns_rounded,
                      label: context.tr('server_title'),
                      onTap: () => showCloudConfigSheet(context),
                    ),
                    const _SoftDivider(),
                    if (!Env.cloudReady)
                      _WarnBox(context.tr('cloud_not_configured'))
                    else if (session.isCloud) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(context.tr('auto_backup'),
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(
                                  sync.pendingCount > 0
                                      ? context.tr('pending_changes', {'n': sync.pendingCount})
                                      : context.tr('last_sync', {
                                          'd': sync.lastSyncAt == null
                                              ? context.tr('never')
                                              : formatDate(context, sync.lastSyncAt!.toLocal(),
                                                  withTime: true),
                                        }),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SyncBadge(compact: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _ActionRow(
                        icon: Icons.sync_rounded,
                        label: context.tr('sync_now'),
                        onTap: () => ref.read(syncEngineProvider).syncNow(force: true),
                      ),
                      _ActionRow(
                        icon: Icons.cloud_download_rounded,
                        label: context.tr('restore_cloud'),
                        onTap: () => ref.read(syncEngineProvider).rehydrateFromCloud(),
                      ),
                    ] else ...[
                      _WarnBox(context.tr('login_for_backup')),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: session.busy
                              ? null
                              : () => ref.read(sessionProvider.notifier).showLogin(),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(context.tr('auth_sign_in')),
                        ),
                      ),
                    ],
                    const _SoftDivider(),
                    _ActionRow(
                      icon: Icons.data_object_rounded,
                      label: context.tr('export_json'),
                      onTap: () => BackupActions.exportJson(context, ref),
                    ),
                    _ActionRow(
                      icon: Icons.table_chart_rounded,
                      label: context.tr('export_csv'),
                      onTap: () => BackupActions.exportCsv(context, ref),
                    ),
                    _ActionRow(
                      icon: Icons.upload_file_rounded,
                      label: context.tr('import_json'),
                      onTap: () => BackupActions.importJson(context, ref),
                    ),
                    const _SoftDivider(),
                    _SmallTitle(context.tr('storage_title')),
                    if (usage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          [
                            context
                                .tr('storage_used', {'n': FilePaths.humanSize(usage.totalBytes)}),
                            context.tr('local_records', {'n': usage.localTransactions}),
                            if (usage.archivedTransactions > 0)
                              context.tr('archived_records', {'n': usage.archivedTransactions}),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    LiquidSelectTile<int>(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      title: context.tr('retention'),
                      value: s.retentionDays,
                      options: [
                        for (final d in AppConstants.retentionOptions)
                          LiquidOption(
                            d,
                            d == 0
                                ? context.tr('retention_all')
                                : context.tr('retention_days', {'n': d}),
                          ),
                      ],
                      onChanged: ctrl.setRetentionDays,
                    ),
                    _ToggleRow(
                      title: context.tr('keep_local_photos'),
                      value: s.keepLocalPhotos,
                      onChanged: ctrl.setKeepLocalPhotos,
                    ),
                    if (session.isCloud)
                      _ActionRow(
                        icon: Icons.cleaning_services_rounded,
                        label: context.tr('clean_now'),
                        onTap: () => _cleanNow(context, ref),
                      ),
                    const _SoftDivider(),
                    Row(children: [
                      if (BankChannel.supported) ...[
                        Expanded(
                          child: _SoftButton(
                            label: context.tr('simulate'),
                            color: AppColors.primary,
                            onTap: () => _simulate(context, ch),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _SoftButton(
                          label: context.tr('delete_all'),
                          color: AppColors.expense,
                          onTap: () => _deleteAll(context, ref),
                        ),
                      ),
                    ]),
                  ],
                ),

                // ------------------------------------------------ (Mới) Giao diện
                _OldSection(
                  icon: Icons.palette_rounded,
                  title: context.tr('appearance'),
                  children: [
                    _SmallTitle(context.tr('theme')),
                    LiquidSegmented<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.brightness_auto_rounded),
                          label: Text(context.tr('theme_system')),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode_rounded),
                          label: Text(context.tr('theme_light')),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode_rounded),
                          label: Text(context.tr('theme_dark')),
                        ),
                      ],
                      selected: {s.themeMode},
                      onSelectionChanged: (v) => ctrl.setThemeMode(v.first),
                    ),
                    const SizedBox(height: 8),
                    LiquidSelectTile<String>(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      icon: Icons.translate_rounded,
                      iconColor: LiquidColors.blue,
                      title: context.tr('language'),
                      value: s.localeCode,
                      options: [
                        LiquidOption('system', context.tr('language_system')),
                        const LiquidOption('vi', 'Tiếng Việt'),
                        const LiquidOption('en', 'English'),
                        const LiquidOption('zh_Hans', '简体中文'),
                        const LiquidOption('zh_Hant', '繁體中文'),
                      ],
                      onChanged: ctrl.setLocale,
                    ),
                    LiquidSelectTile<String>(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      icon: Icons.currency_exchange_rounded,
                      iconColor: LiquidColors.green,
                      title: context.tr('currency'),
                      subtitle: context.tr('currency_note'),
                      value: s.currencyCode,
                      options: [
                        for (final c in Currency.all)
                          LiquidOption(c.code, '${c.code} (${c.symbol})'),
                      ],
                      onChanged: ctrl.setCurrency,
                    ),
                    _ToggleRow(
                      title: context.tr('animated_background'),
                      value: s.animatedBackground,
                      onChanged: s.reduceEffects ? null : ctrl.setAnimatedBackground,
                    ),
                    _ToggleRow(
                      title: context.tr('glass_blur_all'),
                      value: s.glassBlurAll,
                      onChanged: s.reduceEffects ? null : ctrl.setGlassBlurAll,
                    ),
                    _ToggleRow(
                      title: context.tr('reduce_effects'),
                      value: s.reduceEffects,
                      onChanged: ctrl.setReduceEffects,
                    ),
                  ],
                ),

                // ------------------------------------------------ (Mới) Thông báo & bảo mật
                _OldSection(
                  icon: Icons.shield_rounded,
                  title: '${context.tr('notifications')} & ${context.tr('security')}',
                  children: [
                    _ToggleRow(
                      title: context.tr('app_lock'),
                      value: s.pinEnabled,
                      onChanged: (v) async {
                        if (v) {
                          final pin = await askNewPin(context);
                          if (pin != null) await ctrl.setPin(pin);
                        } else {
                          await ctrl.clearPin();
                        }
                      },
                    ),
                  ],
                ),

                // ------------------------------------------------ Thông tin
                const SizedBox(height: 24),
                const _AboutCard(),

                // ------------------------------------------------ Đăng xuất
                if (session.isCloud) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: _SoftButton(
                      label: context.tr('sign_out'),
                      color: AppColors.expense,
                      onTap: () => confirmSignOut(context, ref),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cleanNow(BuildContext context, WidgetRef ref) async {
    final s = ref.read(settingsProvider);
    try {
      await ref.read(syncEngineProvider).syncNow(force: true);
      final r = await ref.read(cacheJanitorProvider).run(
            cloudActive: ref.read(isCloudUserProvider),
            retentionDays: s.retentionDays,
            keepLocalPhotos: s.keepLocalPhotos,
          );
      ref.read(dataEventsProvider).bump();
      if (context.mounted) {
        showSnack(context, context.tr('cleaned', {'n': FilePaths.humanSize(r.bytesFreed)}));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  /// "Giả lập giao dịch" (app cũ): nhận diện + lưu + đọc to một tin nhắn mẫu.
  Future<void> _simulate(BuildContext context, BankChannel ch) async {
    final text = TextEditingController(text: context.tr('simulate_sample'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('simulate_title')),
        content: TextField(
          controller: text,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: ctx.tr('simulate_content')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('simulate_run'))),
        ],
      ),
    );
    final msg = text.text;
    text.dispose();
    if (ok != true) return;
    final r = await ch.simulate(msg);
    if (!context.mounted || r == null) return;
    showSnack(
      context,
      r.accepted
          ? '${context.tr('bank_test_ok')}: ${r.direction > 0 ? '+' : '-'}${formatMoney(ref, context, r.amount * 100)}'
          : context.tr('bank_test_no', {'reason': context.tr('bank_reason_${r.reason}')}),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete_confirm_title')),
        content: Text(ctx.tr('delete_all_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: Text(ctx.tr('delete_all')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final n = await ref.read(transactionRepoProvider).deleteAll();
      await ref.read(bankMessageRepoProvider).deleteAll();
      unawaited(ref.read(syncEngineProvider).syncNow(force: true));
      if (context.mounted) showSnack(context, context.tr('deleted_n', {'n': n}));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

Future<String?> askNewPin(BuildContext context) async {
  final a = TextEditingController();
  final b = TextEditingController();
  String? error;
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(ctx.tr('set_pin')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration:
                  InputDecoration(labelText: ctx.tr('enter_pin'), helperText: ctx.tr('pin_rule')),
            ),
            TextField(
              controller: b,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration: InputDecoration(labelText: ctx.tr('confirm_pin'), errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(
            onPressed: () {
              if (!SettingsController.isValidPin(a.text)) {
                setD(() => error = ctx.tr('pin_rule'));
              } else if (a.text != b.text) {
                setD(() => error = ctx.tr('pin_mismatch'));
              } else {
                Navigator.pop(ctx, a.text);
              }
            },
            child: Text(ctx.tr('save')),
          ),
        ],
      ),
    ),
  );
  a.dispose();
  b.dispose();
  return result;
}

// =====================================================================
// Thành phần giao diện kiểu app cũ (trên nền kính)
// =====================================================================

class _AccountCard extends ConsumerWidget {
  const _AccountCard({this.onSignIn, this.onSignOut});
  final VoidCallback? onSignIn;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final theme = Theme.of(context);
    final name = (session.displayName ?? '').trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : null;
    return GlassCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: session.isCloud
                  ? null
                  : const LinearGradient(colors: [AppColors.lightBlue, Color(0xFFBFDBFE)]),
              color: session.isCloud ? AppColors.lightBlue : null,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: initial != null
                ? Text(initial,
                    style: const TextStyle(
                        color: AppColors.primary, fontSize: 24, fontWeight: FontWeight.w800))
                : const Icon(Icons.person_rounded, size: 32, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isNotEmpty ? name : context.tr('user_default'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 20)),
                Text(
                  session.isCloud
                      ? (session.email ?? session.userId)
                      : context.tr('not_connected_google'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onSignOut != null)
            IconButton(
              tooltip: context.tr('sign_out'),
              onPressed: onSignOut,
              icon: const Icon(Icons.logout_rounded, color: AppColors.expense),
            )
          else if (onSignIn != null)
            IconButton(
              tooltip: context.tr('auth_sign_in'),
              onPressed: onSignIn,
              icon: Icon(Icons.login_rounded, color: theme.colorScheme.primary),
            )
          else if (session.busy)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

/// Nhóm cài đặt kiểu app cũ: tiêu đề có icon xanh bên ngoài, nội dung trong thẻ kính.
class _OldSection extends StatelessWidget {
  const _OldSection({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.badge});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: dark ? Colors.white.withValues(alpha: 0.08) : AppColors.borderSoft,
              ),
              child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w500, fontSize: 15)),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(colors: AppColors.accentGradient),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
              ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.granted, required this.onTap});
  final String label;
  final bool granted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = granted ? AppColors.income : AppColors.expense;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: granted ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: dark
                    ? color.withValues(alpha: 0.18)
                    : (granted ? AppColors.greenSoft : AppColors.redSoft),
              ),
              child: Text(context.tr(granted ? 'granted' : 'not_granted'),
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.title, required this.value, required this.onChanged, this.subtitle});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: onChanged == null ? 0.5 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            LiquidSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: theme.colorScheme.primary,
            thumbColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value.clamp(0.5, 2.0).toDouble(),
            min: 0.5,
            max: 2.0,
            divisions: 15,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _SmallTitle extends StatelessWidget {
  const _SmallTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Text(text,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
    );
  }
}

class _SoftDivider extends StatelessWidget {
  const _SoftDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 1),
      );
}

class _WarnBox extends StatelessWidget {
  const _WarnBox(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: dark ? AppColors.expense.withValues(alpha: 0.15) : AppColors.redSoft,
      ),
      child: Text(text, style: const TextStyle(color: AppColors.expense, fontSize: 13)),
    );
  }
}

class _SoftButton extends StatelessWidget {
  const _SoftButton({required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      child: Text(label),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      radius: 28,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const AppLogo(size: 48),
          const SizedBox(height: 16),
          Text(AppConstants.appName,
              style: TextStyle(
                  color: theme.colorScheme.primary, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${context.tr('version', {'v': Env.appVersion})} · ${Env.appEnv}',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          Text(context.tr('developer'),
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const Text('© 2026 Uri Shaw. All rights reserved.',
              style: TextStyle(color: AppColors.hint, fontSize: 11)),
          const SizedBox(height: 12),
          Text(context.tr('about_desc'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }
}
