import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'app.dart';
import 'core/config/env.dart';
import 'core/security/app_logger.dart';
import 'core/storage/app_database.dart';
import 'features/auth/cloud_config.dart';
import 'features/settings/settings_controller.dart';
import 'shared/providers/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Không để lỗi bất ngờ làm crash app; không log dữ liệu nhạy cảm (spec S).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e('flutter', details.exceptionAsString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('platform', 'uncaught', error);
    return true;
  };

  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();
  final db = await AppDatabase.open();

  // Máy chủ nhập trong app (Cài đặt → Máy chủ đồng bộ) ưu tiên hơn máy chủ lúc build.
  CloudConfig.applySaved(prefs);
  if (Env.cloudConfigured) {
    try {
      await sb.Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        debug: false,
      );
      Env.cloudReady = true;
    } catch (e) {
      // Supabase lỗi khởi tạo -> app vẫn chạy offline.
      AppLogger.e('main', 'supabase init failed', e);
    }
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const SmartFinanceApp(),
    ),
  );
}
