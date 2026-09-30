import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n/app_localizations.dart';
import 'theme/app_theme.dart';
import '../logic/state/settings_controller.dart';
import 'widgets/app_shell.dart';
import 'widgets/glass.dart';

class SmartFinanceApp extends ConsumerWidget {
  const SmartFinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final locale = ref.watch(settingsProvider.select((s) => s.locale));
    return MaterialApp(
      onGenerateTitle: (ctx) => ctx.tr('app_name'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (device, supported) {
        if (device == null) return const Locale('vi');
        if (device.languageCode == 'zh') {
          return AppLocalizations.isTraditional(device)
              ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
              : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
        }
        for (final l in supported) {
          if (l.languageCode == device.languageCode) return l;
        }
        return const Locale('vi');
      },
      // Nền kính dùng chung cho mọi màn hình (Scaffold trong suốt).
      builder: (context, child) => GlassBackground(child: child ?? const SizedBox()),
      home: const RootGate(),
    );
  }
}
