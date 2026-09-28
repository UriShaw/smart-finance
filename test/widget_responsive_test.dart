import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_finance/core/localization/app_localizations.dart';
import 'package:smart_finance/core/theme/app_theme.dart';
import 'package:smart_finance/domain/entities/category.dart';
import 'package:smart_finance/domain/entities/common.dart';
import 'package:smart_finance/domain/entities/finance_transaction.dart';
import 'package:smart_finance/features/auth/login_screen.dart';
import 'package:smart_finance/features/settings/settings_controller.dart';
import 'package:smart_finance/features/transactions/transaction_tile.dart';
import 'package:smart_finance/shared/widgets/glass.dart';

/// Kích thước bắt buộc theo spec L.
const sizes = <Size>[
  Size(320, 640),
  Size(360, 800),
  Size(390, 844),
  Size(430, 932),
  Size(600, 1024),
  Size(768, 1024),
  Size(1024, 1366),
];

const locales = <Locale>[
  Locale('vi'),
  Locale('en'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
];

Future<Widget> harness(Widget child, {required Locale locale, required ThemeMode mode}) async {
  // Tắt nền chuyển động để pumpAndSettle kết thúc được.
  SharedPreferences.setMockInitialValues({'animated_background': false});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    key: UniqueKey(),
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, c) => GlassBackground(child: c!),
      home: child,
    ),
  );
}

void main() {
  final now = DateTime(2026, 9, 23, 12, 30);
  final cat = TxCategory(
    id: 'c1',
    userId: 'u',
    name: '',
    type: TxType.expense,
    icon: 'restaurant',
    color: 0xFFFF7A59,
    defaultKey: 'cat_food',
    createdAt: now,
    updatedAt: now,
  );
  final tx = FinanceTransaction(
    id: 't1',
    userId: 'u',
    name: 'Một cái tên giao dịch rất rất dài để kiểm tra tràn chữ trên màn hình nhỏ',
    amountMinor: 123456789900,
    type: TxType.expense,
    date: now,
    locationName: 'Quận 1, TP. Hồ Chí Minh',
    createdAt: now,
    updatedAt: now,
  );

  for (final size in sizes) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
          'Login + list widgets render without overflow at '
          '${size.width.toInt()}x${size.height.toInt()} ${mode.name}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        for (final locale in locales) {
          await tester.pumpWidget(await harness(const LoginScreen(), locale: locale, mode: mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(await harness(
            Scaffold(
              body: ListView(
                children: [
                  TransactionTile(tx: tx, category: cat),
                ],
              ),
            ),
            locale: locale,
            mode: mode,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('text scale 2.0 does not break login', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
        await harness(const LoginScreen(), locale: const Locale('vi'), mode: ThemeMode.light));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
