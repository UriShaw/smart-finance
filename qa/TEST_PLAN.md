# Test Plan & Quality Gate

## Chạy test

```bat
flutter test                                  :: unit + widget
flutter test integration_test -d windows      :: luồng thật trên Windows
supabase test db                              :: RLS 2 user (pgTAP, Supabase local)

:: Bộ nhận diện thông báo ngân hàng (chỉ cần JDK, ví dụ JDK đi kèm Android Studio):
javac -encoding UTF-8 -d out frontend/native_android/BankParser.java frontend/native_android/BankRegistry.java frontend/native_android/VietnameseNumber.java frontend/native_android/SenderName.java frontend/native_android/test/BankParserTest.java
java -cp out io.smartfinance.smart_finance.BankParserTest
```

`devops\check.bat` chạy nhanh analyze + test (log ở `devops\build_logs\check_*.log`). `devops\build.bat` tự chạy `dart format` (kiểm tra), `flutter analyze`, `flutter test` và ghi kết quả vào `releases\<ver>\manifest.json`.

## Ma trận test (spec R)

| Yêu cầu | File test |
|---|---|
| balance calculation | `test/domain_test.dart` › Balance calculation |
| budget calculation | `test/domain_test.dart` › Budget calculation |
| recurring generation | `test/domain_test.dart` › Recurring; `test/repository_test.dart` › never duplicates |
| transaction CRUD | `test/repository_test.dart` |
| offline create/edit/delete | `test/repository_test.dart`, `test/sync_engine_test.dart` › offline |
| sync retry | `test/sync_engine_test.dart` › retry with backoff |
| duplicate prevention | `test/sync_engine_test.dart` (idempotent upsert), recurring v5 ids, backup re-import |
| conflict resolution | `test/domain_test.dart` › Conflict; `test/sync_engine_test.dart` › conflict |
| photo upload retry | `test/sync_engine_test.dart` › photo upload fails |
| temp cleanup / retention | `test/sync_engine_test.dart` › retention, tombstone purge, keepLocalPhotos |
| backup/restore | `test/backup_localization_test.dart` |
| bank notification parser (43 mẫu thật/giả: VCB, TCB, MB, BIDV, VietinBank, ACB, MoMo, Cake, Timo, OTP, khuyến mãi, Zalo, SMS lạ...) | `frontend/native_android/test/BankParserTest.java` |
| bank event → transaction | `test/bank_importer_test.dart` |
| liquid glass controls (công tắc chạm/kéo, thanh chọn, bảng chọn, không tràn 320px & 1024px, sáng/tối) | `test/liquid_widgets_test.dart` |
| RLS isolation A/B | `backend/supabase/tests/rls_isolation.test.sql` |
| auth flow | `integration_test/app_flow_test.dart` (offline); Google: kiểm thử tay (checklist dưới) |
| responsive | `test/widget_responsive_test.dart` (7 kích thước × sáng/tối × 4 ngôn ngữ, text scale 2.0) |
| localization / dark mode | `test/backup_localization_test.dart`, `test/widget_responsive_test.dart` |

## Checklist kiểm thử tay (smoke test mỗi bản release)

1. Mở exe lần đầu → chọn offline → thêm giao dịch có ảnh → thấy ở Tổng quan, Lịch sử, Lịch, Thống kê.
2. Đăng nhập Google (trình duyệt mở → quay lại app) → dữ liệu offline được chuyển lên tài khoản.
3. Rút mạng → thêm/sửa/xóa → badge "Offline" + số thay đổi chờ → cắm mạng → "Đã đồng bộ".
4. Máy thứ 2 đăng nhập cùng tài khoản → thấy dữ liệu; xóa ở máy 2 → máy 1 mất sau khi đồng bộ.
5. Cài đặt → Bộ nhớ tạm: ảnh tạm = 0 B sau khi đồng bộ (khi không bật giữ ảnh gốc).
6. Xuất JSON → Nhập lại → báo "0 mới, N bỏ qua".
7. Đổi ngôn ngữ 4 thứ tiếng, chế độ tối, thu nhỏ cửa sổ còn ~360px → không vỡ giao diện.
