import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/money.dart';

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main()'),
);

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.light,
    this.localeCode = 'system',
    this.currencyCode = 'VND',
    this.reduceEffects = false,
    this.retentionDays = AppConstants.defaultRetentionDays,
    this.keepLocalPhotos = false,
    this.pinHash,
    this.pinSalt,
    this.offlineChosen = false,
    this.animatedBackground = true,
    this.glassBlurAll = false,
  });

  final ThemeMode themeMode;

  /// 'system' | 'vi' | 'en' | 'zh_Hans' | 'zh_Hant'
  final String localeCode;
  final String currencyCode;
  final bool reduceEffects;
  final int retentionDays;
  final bool keepLocalPhotos;
  final String? pinHash;
  final String? pinSalt;

  /// User đã chọn "dùng offline" ở màn đăng nhập.
  final bool offlineChosen;

  /// Nền chất lỏng chuyển động.
  final bool animatedBackground;

  /// Làm mờ (blur) mọi thẻ kính - đẹp hơn nhưng tốn GPU/pin hơn.
  final bool glassBlurAll;

  Currency get currency => Currency.byCode(currencyCode);
  bool get pinEnabled => pinHash != null && pinSalt != null;

  Locale? get locale {
    switch (localeCode) {
      case 'vi':
        return const Locale('vi');
      case 'en':
        return const Locale('en');
      case 'zh_Hans':
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      case 'zh_Hant':
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      default:
        return null;
    }
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? localeCode,
    String? currencyCode,
    bool? reduceEffects,
    int? retentionDays,
    bool? keepLocalPhotos,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    bool? offlineChosen,
    bool? animatedBackground,
    bool? glassBlurAll,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      localeCode: localeCode ?? this.localeCode,
      currencyCode: currencyCode ?? this.currencyCode,
      reduceEffects: reduceEffects ?? this.reduceEffects,
      retentionDays: retentionDays ?? this.retentionDays,
      keepLocalPhotos: keepLocalPhotos ?? this.keepLocalPhotos,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      offlineChosen: offlineChosen ?? this.offlineChosen,
      animatedBackground: animatedBackground ?? this.animatedBackground,
      glassBlurAll: glassBlurAll ?? this.glassBlurAll,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'theme_mode';
  static const _kLocale = 'locale';
  static const _kCurrency = 'currency';
  static const _kReduce = 'reduce_effects';
  static const _kRetention = 'retention_days';
  static const _kKeepPhotos = 'keep_local_photos';
  static const _kPinHash = 'pin_hash';
  static const _kPinSalt = 'pin_salt';
  static const _kOffline = 'offline_chosen';
  static const _kAnimatedBg = 'animated_background';
  static const _kBlurAll = 'glass_blur_all';

  SharedPreferences get _p => ref.read(sharedPrefsProvider);

  @override
  AppSettings build() {
    final p = ref.watch(sharedPrefsProvider);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == p.getString(_kTheme),
        orElse: () => ThemeMode.light,
      ),
      localeCode: p.getString(_kLocale) ?? 'system',
      currencyCode: p.getString(_kCurrency) ?? 'VND',
      reduceEffects: p.getBool(_kReduce) ?? false,
      retentionDays: p.getInt(_kRetention) ?? AppConstants.defaultRetentionDays,
      keepLocalPhotos: p.getBool(_kKeepPhotos) ?? false,
      pinHash: p.getString(_kPinHash),
      pinSalt: p.getString(_kPinSalt),
      offlineChosen: p.getBool(_kOffline) ?? false,
      animatedBackground: p.getBool(_kAnimatedBg) ?? true,
      glassBlurAll: p.getBool(_kBlurAll) ?? false,
    );
  }

  Future<void> setThemeMode(ThemeMode m) async {
    await _p.setString(_kTheme, m.name);
    state = state.copyWith(themeMode: m);
  }

  Future<void> setLocale(String code) async {
    await _p.setString(_kLocale, code);
    state = state.copyWith(localeCode: code);
  }

  Future<void> setCurrency(String code) async {
    await _p.setString(_kCurrency, code);
    state = state.copyWith(currencyCode: code);
  }

  Future<void> setReduceEffects(bool v) async {
    await _p.setBool(_kReduce, v);
    state = state.copyWith(reduceEffects: v);
  }

  Future<void> setRetentionDays(int v) async {
    await _p.setInt(_kRetention, v);
    state = state.copyWith(retentionDays: v);
  }

  Future<void> setKeepLocalPhotos(bool v) async {
    await _p.setBool(_kKeepPhotos, v);
    state = state.copyWith(keepLocalPhotos: v);
  }

  Future<void> setAnimatedBackground(bool v) async {
    await _p.setBool(_kAnimatedBg, v);
    state = state.copyWith(animatedBackground: v);
  }

  Future<void> setGlassBlurAll(bool v) async {
    await _p.setBool(_kBlurAll, v);
    state = state.copyWith(glassBlurAll: v);
  }

  Future<void> setOfflineChosen(bool v) async {
    await _p.setBool(_kOffline, v);
    state = state.copyWith(offlineChosen: v);
  }

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static bool isValidPin(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final hash = _hash(salt, pin);
    await _p.setString(_kPinSalt, salt);
    await _p.setString(_kPinHash, hash);
    state = state.copyWith(pinHash: hash, pinSalt: salt);
  }

  Future<void> clearPin() async {
    await _p.remove(_kPinHash);
    await _p.remove(_kPinSalt);
    state = state.copyWith(clearPin: true);
  }

  bool verifyPin(String pin) {
    final s = state;
    if (!s.pinEnabled) return true;
    return _hash(s.pinSalt!, pin) == s.pinHash;
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
