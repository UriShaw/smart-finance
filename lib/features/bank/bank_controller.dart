import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/ids.dart';
import '../../shared/providers/app_providers.dart';
import '../auth/auth_controller.dart';
import '../settings/settings_controller.dart';
import 'bank_channel.dart';
import 'bank_importer.dart';

final bankChannelProvider = Provider<BankChannel>((ref) => BankChannel());

class BankState {
  const BankState({
    required this.supported,
    required this.permission,
    required this.config,
  });

  final bool supported;
  final bool permission;
  final BankConfig config;

  /// Đang thật sự hoạt động: đã bật + đã cấp quyền.
  bool get active => supported && permission && config.enabled;

  BankState copyWith({bool? permission, BankConfig? config}) => BankState(
        supported: supported,
        permission: permission ?? this.permission,
        config: config ?? this.config,
      );
}

class BankController extends AsyncNotifier<BankState> {
  BankChannel get _ch => ref.read(bankChannelProvider);

  @override
  Future<BankState> build() async {
    final ch = ref.watch(bankChannelProvider);
    if (!BankChannel.supported) {
      return const BankState(supported: false, permission: false, config: BankConfig());
    }
    final results = await Future.wait([ch.isPermissionGranted(), ch.getConfig()]);
    return BankState(
      supported: true,
      permission: results[0] as bool,
      config: results[1] as BankConfig,
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _save(BankConfig c) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await _ch.setConfig(c);
    state = AsyncData(cur.copyWith(config: c));
  }

  Future<void> setEnabled(bool v) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await _save(cur.config.copyWith(enabled: v));
    if (v && !cur.permission) await _ch.openPermissionSettings();
  }

  Future<void> setSpeak(bool v) async {
    final cur = state.valueOrNull;
    if (cur != null) await _save(cur.config.copyWith(speak: v));
  }

  Future<void> setSpeakExpense(bool v) async {
    final cur = state.valueOrNull;
    if (cur != null) await _save(cur.config.copyWith(speakExpense: v));
  }

  Future<void> _saveAudio(BankConfig c) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(config: c));
    await _ch.setAudio(c);
  }

  Future<void> setVolumeBoost(bool v) async {
    final cur = state.valueOrNull;
    if (cur != null) await _saveAudio(cur.config.copyWith(volumeBoost: v));
  }

  Future<void> setVoice(String v) async {
    final cur = state.valueOrNull;
    if (cur != null) await _saveAudio(cur.config.copyWith(voice: v));
  }

  Future<void> setChime(String v) async {
    final cur = state.valueOrNull;
    if (cur != null) await _saveAudio(cur.config.copyWith(chime: v));
  }

  /// Kéo thanh trượt: cập nhật giao diện ngay, lưu khi thả tay ([persist]).
  Future<void> setRate(double v, {bool persist = true}) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    final c = cur.config.copyWith(rate: v);
    if (persist) {
      await _saveAudio(c);
    } else {
      state = AsyncData(cur.copyWith(config: c));
    }
  }

  Future<void> setPitch(double v, {bool persist = true}) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    final c = cur.config.copyWith(pitch: v);
    if (persist) {
      await _saveAudio(c);
    } else {
      state = AsyncData(cur.copyWith(config: c));
    }
  }

  Future<void> trustApp(String pkg) async {
    final cur = state.valueOrNull;
    if (cur == null || pkg.isEmpty) return;
    await _save(cur.config.copyWith(
      allow: {...cur.config.allow, pkg}.toList(),
      block: cur.config.block.where((p) => p != pkg).toList(),
    ));
  }

  Future<void> blockApp(String pkg) async {
    final cur = state.valueOrNull;
    if (cur == null || pkg.isEmpty) return;
    await _save(cur.config.copyWith(
      block: {...cur.config.block, pkg}.toList(),
      allow: cur.config.allow.where((p) => p != pkg).toList(),
    ));
  }

  Future<void> forgetApp(String pkg) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    await _save(cur.config.copyWith(
      block: cur.config.block.where((p) => p != pkg).toList(),
      allow: cur.config.allow.where((p) => p != pkg).toList(),
    ));
  }
}

final bankControllerProvider = AsyncNotifierProvider<BankController, BankState>(BankController.new);

/// Bộ nhập giao dịch từ thông báo (chỉ Android).
final bankImporterProvider = Provider<BankImporter?>((ref) {
  if (!BankChannel.supported) return null;
  final uid = ref.watch(currentUserIdProvider);
  final categories = ref.watch(categoryRepoProvider);
  final locale =
      ref.watch(settingsProvider.select((s) => s.locale)) ?? PlatformDispatcher.instance.locale;
  final l = AppLocalizations(locale);
  return BankImporter(
    channel: ref.watch(bankChannelProvider),
    transactions: ref.watch(transactionRepoProvider),
    messages: ref.watch(bankMessageRepoProvider),
    userId: uid,
    categoryIdForKey: (key) async {
      final id = Ids.defaultCategory(uid, key);
      final all = await categories.mapAll();
      final c = all[id];
      return c != null && c.deletedAt == null ? id : null;
    },
    labels: BankLabels(
      incomeName: l.t('bank_income_name'),
      expenseName: l.t('bank_expense_name'),
      autoNote: l.t('bank_auto_note'),
    ),
  );
});

/// Số giao dịch vừa nhập gần nhất (để hiện thông báo nhỏ).
final bankLastImportProvider = StateProvider<int>((ref) => 0);

/// Tự nhập khi mở app và ngay khi service báo có giao dịch mới.
final bankAutoImportProvider = Provider<void>((ref) {
  final importer = ref.watch(bankImporterProvider);
  if (importer == null) return;
  final ch = ref.watch(bankChannelProvider);
  Future<void> run() async {
    try {
      // Đảm bảo danh mục mặc định đã được tạo trước khi gán.
      await ref.read(bootstrapProvider.future);
      final n = await importer.importPending();
      if (n > 0) {
        await ref.read(duplicateCleanerProvider).run();
        ref.read(bankLastImportProvider.notifier).state = n;
      }
    } catch (_) {}
  }

  ch.setOnPending(() => unawaited(run()));
  ref.onDispose(() => ch.setOnPending(null));
  unawaited(Future.microtask(run));
});
