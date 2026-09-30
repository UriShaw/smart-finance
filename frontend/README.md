# Frontend (FE) · App Flutter

App Smart Finance cho **Android** và **Windows**. Mọi lệnh `flutter` chạy trong thư mục này.

## Giao diện ở đâu, xử lý ở đâu

| Thư mục | Nội dung |
|---|---|
| `lib/ui/` | **Giao diện**: mọi thứ người dùng nhìn thấy |
| `lib/ui/screens/<màn>/` | Từng màn hình: `home`, `transactions`, `map`, `calendar`, `statistics`, `settings`, `auth`, `bank`, `moments`, `categories` |
| `lib/ui/widgets/` | Widget dùng chung (khung app, kính mờ, nút, huy hiệu đồng bộ) |
| `lib/ui/theme/` | Màu sắc, chữ, bo góc |
| `lib/ui/i18n/` | Ngôn ngữ: Việt, Anh, Trung |
| `lib/logic/` | **Xử lý / thuật toán**: không vẽ gì lên màn hình |
| `lib/logic/domain/` | Thực thể (giao dịch, danh mục) và quy tắc: tính số dư, thống kê, đoán danh mục, xử lý xung đột |
| `lib/logic/data/` | CSDL trên máy (SQLite), đồng bộ với Supabase, ảnh, sao lưu, dọn trùng |
| `lib/logic/bank/` | Đọc thông báo ngân hàng → tạo giao dịch |
| `lib/logic/auth/` | Đăng nhập Google/email, nhiều tài khoản |
| `lib/logic/location/` | Lấy vị trí GPS, gom điểm trên bản đồ |
| `lib/logic/state/` | Provider và controller (trạng thái app, cài đặt) |
| `lib/core/` | Nền tảng dùng chung: cấu hình, hằng số, lỗi, mạng, bảo mật, tiện ích |
| `native_android/` | Mã Java/Kotlin đọc thông báo ngân hàng (script build tự chép vào `android/`) |
| `test/`, `integration_test/` | Kiểm thử tự động |
| `config/` | `env.example.json` (mẫu). `env.json` và `client_secret_*.json` là bí mật, không commit |

Quy ước: `ui/` được gọi `logic/`, còn `logic/` không import màn hình hay widget.

## Lệnh hay dùng

```
flutter test          :: chạy test
flutter analyze       :: kiểm tra code
..\devops\run_dev.bat :: chạy bản debug trên Windows
```
