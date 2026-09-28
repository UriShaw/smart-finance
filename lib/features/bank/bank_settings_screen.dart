import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/liquid.dart';
import 'bank_channel.dart';
import 'bank_controller.dart';

final _bankLogProvider = FutureProvider.autoDispose<List<BankLogEntry>>(
    (ref) => ref.watch(bankChannelProvider).getLog());

final _supportedBanksProvider = FutureProvider.autoDispose<List<String>>(
    (ref) => ref.watch(bankChannelProvider).supportedBanks());

/// Cài đặt "Ghi tự động từ thông báo ngân hàng" (Android).
class BankSettingsScreen extends ConsumerStatefulWidget {
  const BankSettingsScreen({super.key});

  @override
  ConsumerState<BankSettingsScreen> createState() => _BankSettingsScreenState();
}

class _BankSettingsScreenState extends ConsumerState<BankSettingsScreen>
    with WidgetsBindingObserver {
  final _title = TextEditingController(text: 'Vietcombank');
  final _content = TextEditingController(
      text: 'TK 0071xxx +500,000 VND lúc 20:15. SD 12,345,678 VND. ND: LUONG THANG 9');
  BankTestResult? _test;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Quay lại từ màn cấp quyền của Android -> cập nhật trạng thái.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(bankControllerProvider.notifier).refresh();
      ref.invalidate(_bankLogProvider);
    }
  }

  Future<void> _runTest() async {
    final r = await ref.read(bankChannelProvider).testParse(
          // Giả lập nguồn là một app ngân hàng bất kỳ.
          pkg: 'vn.test.mobilebanking',
          title: _title.text,
          text: _content.text,
        );
    if (mounted) setState(() => _test = r);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bankControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('bank_title'))),
      body: AsyncBody<BankState>(
        value: state,
        builder: (s) {
          if (!s.supported) {
            return EmptyState(icon: Icons.phone_android, message: context.tr('bank_android_only'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 120),
            children: [
              ContentWidth(
                max: 760,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Hero(state: s),
                    const SizedBox(height: AppSpacing.md),
                    if (!s.permission) const _PermissionCard(),
                    _toggles(context, s),
                    _testCard(context),
                    _appsCard(context, s),
                    _logCard(context),
                    _supportedCard(context),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(context.tr('bank_privacy'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _toggles(BuildContext context, BankState s) {
    final ctrl = ref.read(bankControllerProvider.notifier);
    return GlassSection(
      title: context.tr('bank_section'),
      children: [
        LiquidSwitchTile(
          icon: Icons.notifications_active_rounded,
          iconColor: LiquidColors.green,
          title: context.tr('bank_enable'),
          value: s.config.enabled,
          onChanged: ctrl.setEnabled,
        ),
        LiquidSwitchTile(
          icon: Icons.record_voice_over_rounded,
          iconColor: LiquidColors.purple,
          title: context.tr('bank_speak'),
          value: s.config.speak,
          onChanged: s.config.enabled ? ctrl.setSpeak : null,
        ),
        LiquidSwitchTile(
          icon: Icons.volume_down_rounded,
          iconColor: LiquidColors.orange,
          title: context.tr('bank_speak_expense'),
          value: s.config.speakExpense,
          onChanged: s.config.enabled && s.config.speak ? ctrl.setSpeakExpense : null,
        ),
        LiquidTile(
          icon: Icons.play_circle_fill_rounded,
          iconColor: LiquidColors.pink,
          title: context.tr('bank_speak_test'),
          showChevron: false,
          onTap: () => ref.read(bankChannelProvider).speak(context.tr('bank_speak_sample')),
        ),
        LiquidTile(
          icon: Icons.battery_charging_full_rounded,
          iconColor: LiquidColors.teal,
          title: context.tr('bank_battery'),
          subtitle: context.tr('bank_battery_hint'),
          onTap: () => ref.read(bankChannelProvider).openBatterySettings(),
        ),
      ],
    );
  }

  Widget _testCard(BuildContext context) {
    final r = _test;
    return GlassSection(
      title: context.tr('bank_test_title'),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: InputDecoration(labelText: context.tr('bank_test_sender')),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _content,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: context.tr('bank_test_content')),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _runTest,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(context.tr('bank_test_run')),
                ),
              ),
              if (r != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ResultBox(result: r),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _appsCard(BuildContext context, BankState s) {
    if (s.config.allow.isEmpty && s.config.block.isEmpty) return const SizedBox.shrink();
    final ctrl = ref.read(bankControllerProvider.notifier);
    Widget chips(List<String> pkgs, Color color) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in pkgs)
              InputChip(
                label: Text(p, overflow: TextOverflow.ellipsis),
                side: BorderSide(color: color.withValues(alpha: 0.5)),
                onDeleted: () => ctrl.forgetApp(p),
              ),
          ],
        );
    return GlassSection(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.config.allow.isNotEmpty) ...[
                Text(context.tr('bank_trusted_apps'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                chips(s.config.allow, AppColors.income),
                const SizedBox(height: AppSpacing.md),
              ],
              if (s.config.block.isNotEmpty) ...[
                Text(context.tr('bank_blocked_apps'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                chips(s.config.block, AppColors.expense),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _logCard(BuildContext context) {
    final log = ref.watch(_bankLogProvider);
    final ctrl = ref.read(bankControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          context.tr('bank_log'),
          trailing: TextButton(
            onPressed: () async {
              await ref.read(bankChannelProvider).clearLog();
              ref.invalidate(_bankLogProvider);
            },
            child: Text(context.tr('bank_log_clear')),
          ),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: log.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(error: e),
            data: (entries) => entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(context.tr('bank_log_empty'), textAlign: TextAlign.center),
                  )
                : Column(
                    children: [
                      for (final e in entries.take(60))
                        LiquidTile(
                          leading: LiquidIconBadge(
                            icon: e.saved
                                ? (e.direction > 0
                                    ? Icons.south_west_rounded
                                    : Icons.north_east_rounded)
                                : Icons.block_rounded,
                            color: e.saved
                                ? (e.direction > 0 ? LiquidColors.green : LiquidColors.red)
                                : LiquidColors.gray,
                          ),
                          title: e.saved
                              ? '${e.direction > 0 ? '+' : '-'}${formatMoney(ref, context, e.amount * 100)} · ${e.bank}'
                              : '${context.tr('bank_ignored')}: ${context.tr('bank_reason_${e.reason}')}',
                          subtitle: '${formatDate(context, e.time, withTime: true)} · ${e.preview}',
                          trailing: e.saved || e.pkg.isEmpty
                              ? null
                              : PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_horiz_rounded),
                                  onSelected: (v) {
                                    if (v == 'trust') ctrl.trustApp(e.pkg);
                                    if (v == 'block') ctrl.blockApp(e.pkg);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'trust', child: Text(context.tr('bank_trust_app'))),
                                    PopupMenuItem(
                                        value: 'block', child: Text(context.tr('bank_block_app'))),
                                  ],
                                ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _supportedCard(BuildContext context) {
    final banks = ref.watch(_supportedBanksProvider).valueOrNull ?? const <String>[];
    return GlassSection(
      title: context.tr('bank_supported'),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final b in banks) Chip(label: Text(b))],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(context.tr('bank_supported_more'), style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.state});
  final BankState state;

  @override
  Widget build(BuildContext context) {
    final active = state.active;
    return GradientGlassCard(
      colors: active
          ? const [Color(0xFF00C48C), Color(0xFF00B4FF)]
          : const [Color(0xFF7C4DFF), Color(0xFFFF4FD8)],
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: Icon(active ? Icons.graphic_eq : Icons.account_balance,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('bank_title'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(context.tr('bank_subtitle'),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.white.withValues(alpha: 0.9))),
                const SizedBox(height: 6),
                Text(
                  state.permission
                      ? context.tr('bank_permission_ok')
                      : context.tr('bank_permission_missing'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (state.config.pending > 0)
                  Text(context.tr('bank_pending', {'n': state.config.pending}),
                      style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ch = ref.read(bankChannelProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: GlassCard(
        tint: AppColors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(context.tr('bank_permission_missing'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(context.tr('bank_restricted_hint'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: ch.openPermissionSettings,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(context.tr('bank_grant')),
                ),
                OutlinedButton(
                  onPressed: ch.openAppDetails,
                  child: Text(context.tr('bank_app_info')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultBox extends ConsumerWidget {
  const _ResultBox({required this.result});
  final BankTestResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = result;
    final color = r.accepted
        ? (r.direction > 0 ? AppColors.income : AppColors.expense)
        : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.accepted ? Icons.check_circle : Icons.block, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  r.accepted
                      ? '${context.tr('bank_test_ok')}: ${r.direction > 0 ? '+' : '-'}${formatMoney(ref, context, r.amount * 100)} · ${r.bank}'
                      : context
                          .tr('bank_test_no', {'reason': context.tr('bank_reason_${r.reason}')}),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (r.accepted && r.balance >= 0)
            Text(context.tr('bank_balance', {'n': formatMoney(ref, context, r.balance * 100)})),
          if (r.content.isNotEmpty) Text('${context.tr('tx_note')}: ${r.content}'),
          if (r.announcement.isNotEmpty)
            Text('🔊 ${r.announcement}', style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}
