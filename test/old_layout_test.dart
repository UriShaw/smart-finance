import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_finance/core/localization/app_localizations.dart';
import 'package:smart_finance/core/theme/app_theme.dart';
import 'package:smart_finance/domain/usecases/balance_calculator.dart';
import 'package:smart_finance/features/home/home_screen.dart';
import 'package:smart_finance/features/settings/settings_controller.dart';
import 'package:smart_finance/shared/providers/app_providers.dart';
import 'package:smart_finance/shared/widgets/app_logo.dart';
import 'package:smart_finance/shared/widgets/liquid.dart';

Future<Widget> harness(Widget child, {required Locale locale, required ThemeMode mode}) async {
  SharedPreferences.setMockInitialValues({'animated_background': false});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      totalSummaryProvider.overrideWith(
          (ref) async => const BalanceSummary(incomeMinor: 1234567800, expenseMinor: 98765400)),
      todayStatsProvider.overrideWith((ref) async =>
          const DayStats(BalanceSummary(incomeMinor: 15000000, expenseMinor: 4500000), 3)),
    ],
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
      home: Scaffold(body: child),
    ),
  );
}

class _Page extends StatefulWidget {
  const _Page();
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int tab = 0;
  bool chip = false;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final k in ['tab_home', 'nav_history', 'nav_stats', 'nav_settings'])
        GlassNavItem(icon: Icons.circle_outlined, selectedIcon: Icons.circle, label: context.tr(k)),
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Row(children: [AppLogo(size: 32), SizedBox(width: 8), AppLogo(size: 48)]),
              const SizedBox(height: 12),
              const AssetCard(),
              const SizedBox(height: 12),
              const TodayOverviewCard(),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                GlassChip(
                    label: context.tr('this_week'),
                    selected: chip,
                    onTap: () => setState(() => chip = !chip)),
                GlassChip(label: context.tr('over_1m'), selected: !chip, onTap: () {}),
              ]),
              Text('tab:$tab'),
            ],
          ),
        ),
        GlassNavBar(items: items, index: tab, onSelect: (i) => setState(() => tab = i)),
      ],
    );
  }
}

void main() {
  const locales = [
    Locale('vi'),
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  for (final size in const [Size(320, 640), Size(390, 844), Size(1024, 800)]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('old layout widgets render at $size ${mode.name}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        for (final locale in locales) {
          await tester.pumpWidget(await harness(const _Page(), locale: locale, mode: mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('balance eye toggles and bottom bar switches tab', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        await harness(const _Page(), locale: const Locale('vi'), mode: ThemeMode.light));
    await tester.pumpAndSettle();

    expect(find.text('••••••••'), findsNothing);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.text('••••••••'), findsOneWidget);

    await tester.tap(find.text('Thống kê'));
    await tester.pumpAndSettle();
    expect(find.text('tab:2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
