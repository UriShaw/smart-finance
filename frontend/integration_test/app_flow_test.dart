// Chạy trên máy thật / Windows:  flutter test integration_test -d windows
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_finance/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline flow: open app -> visit every main tab without errors', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Màn đăng nhập (nếu đã cấu hình Supabase): chọn dùng offline.
    final offline = find.byIcon(Icons.wifi_off);
    if (offline.evaluate().isNotEmpty) {
      await tester.tap(offline);
      await tester.pumpAndSettle();
    }

    // Không còn nút "Thêm giao dịch" nổi.
    expect(find.byIcon(Icons.add), findsNothing);

    // Đi qua 5 tab: Trang chủ, Lịch sử, Lịch, Thống kê, Cài đặt.
    for (final icon in [
      Icons.history_rounded,
      Icons.calendar_month_outlined,
      Icons.bar_chart_outlined,
      Icons.settings_outlined,
      Icons.home_outlined,
    ]) {
      final f = find.byIcon(icon);
      if (f.evaluate().isNotEmpty) {
        await tester.tap(f.first);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
