import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_finance/ui/i18n/app_localizations.dart';
import 'package:smart_finance/ui/theme/app_theme.dart';
import 'package:smart_finance/logic/state/settings_controller.dart';
import 'package:smart_finance/ui/widgets/common.dart';
import 'package:smart_finance/ui/widgets/liquid.dart';

Future<Widget> harness(Widget child, {ThemeMode mode = ThemeMode.light}) async {
  SharedPreferences.setMockInitialValues({'animated_background': false});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    key: UniqueKey(),
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      locale: const Locale('vi'),
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

/// Trạng thái công tắc giữ trong widget test.
class _SwitchHost extends StatefulWidget {
  const _SwitchHost();
  @override
  State<_SwitchHost> createState() => _SwitchHostState();
}

class _SwitchHostState extends State<_SwitchHost> {
  bool on = false;
  String type = 'expense';
  String? cat;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassSection(
          title: 'Thông báo & bảo mật',
          children: [
            LiquidSwitchTile(
              icon: Icons.notifications_active_rounded,
              title: 'Cảnh báo ngân sách với một tiêu đề rất dài để kiểm tra tràn chữ',
              subtitle: 'Mô tả phụ',
              value: on,
              onChanged: (v) => setState(() => on = v),
            ),
            const LiquidTile(icon: Icons.lock_rounded, title: 'Khoá', value: 'Tắt'),
          ],
        ),
        const SizedBox(height: 16),
        LiquidSegmented<String>(
          segments: const [
            ButtonSegment(value: 'expense', label: Text('Chi')),
            ButtonSegment(value: 'income', label: Text('Thu')),
          ],
          selected: {type},
          onSelectionChanged: (s) => setState(() => type = s.first),
        ),
        const SizedBox(height: 16),
        LabeledDropdown<String?>(
          label: 'Danh mục',
          value: cat,
          items: const [
            DropdownMenuItem<String?>(value: null, child: Text('Tất cả')),
            DropdownMenuItem<String?>(value: 'food', child: Text('Ăn uống')),
          ],
          onChanged: (v) => setState(() => cat = v),
        ),
        Text('state:$on:$type:$cat'),
      ],
    );
  }
}

void main() {
  testWidgets('LiquidSwitch toggles by tap on switch and on tile', (tester) async {
    await tester.pumpWidget(await harness(const _SwitchHost()));
    await tester.pumpAndSettle();
    expect(find.text('state:false:expense:null'), findsOneWidget);

    await tester.tap(find.byType(LiquidSwitch));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('state:true:expense:null'), findsOneWidget);

    await tester.tap(find.text('Mô tả phụ'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('state:false:expense:null'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LiquidSwitch drag to the right turns it on', (tester) async {
    await tester.pumpWidget(await harness(const _SwitchHost()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(LiquidSwitch), const Offset(40, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('state:true:expense:null'), findsOneWidget);
  });

  testWidgets('LiquidSegmented + glass picker select values', (tester) async {
    await tester.pumpWidget(await harness(const _SwitchHost()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Thu'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('state:false:income:null'), findsOneWidget);

    await tester.tap(find.text('Danh mục'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ăn uống').last);
    await tester.pumpAndSettle();
    expect(find.text('state:false:income:food'), findsOneWidget);
  });

  for (final size in const [Size(320, 640), Size(1024, 800)]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('liquid kit has no overflow at $size $mode', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(await harness(const _SwitchHost(), mode: mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
