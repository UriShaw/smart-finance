# Smart Finance

**Ứng dụng quản lý tài chính cá nhân offline-first cho Android và Windows**, xây bằng Flutter và Supabase.
Tự ghi giao dịch từ thông báo biến động số dư của ngân hàng, hiển thị đúng số dư ngân hàng báo,
đồng bộ nhiều thiết bị theo tài khoản Google hoặc email.

![Flutter](https://img.shields.io/badge/Flutter-3.27%2B-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.6%2B-0175C2?logo=dart)
![Supabase](https://img.shields.io/badge/Supabase-Auth%20%7C%20Postgres%20%7C%20Storage-3ECF8E?logo=supabase)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows-lightgrey)
![Tests](https://img.shields.io/badge/tests-105%20passed-brightgreen)

---

## Mục lục

1. [Tổng quan](#tổng-quan)
2. [Tính năng](#tính-năng)
3. [Công nghệ](#công-nghệ)
4. [Kiến trúc](#kiến-trúc)
5. [Cấu trúc thư mục](#cấu-trúc-thư-mục)
6. [Bắt đầu nhanh](#bắt-đầu-nhanh)
7. [Cấu hình](#cấu-hình)
8. [Build và phát hành](#build-và-phát-hành)
9. [Kiểm thử và chất lượng mã](#kiểm-thử-và-chất-lượng-mã)
10. [Bảo mật và quyền riêng tư](#bảo-mật-và-quyền-riêng-tư)
11. [Giới hạn đã biết](#giới-hạn-đã-biết)
12. [Tài liệu](#tài-liệu)

---

## Tổng quan

Phần lớn ứng dụng quản lý chi tiêu bắt người dùng nhập tay từng khoản, nên số liệu nhanh chóng lệch
với tài khoản thật. Smart Finance giải quyết bằng cách **đọc thông báo biến động số dư** mà ứng dụng
ngân hàng đã gửi lên điện thoại, tự tạo giao dịch và lấy **số dư sau giao dịch do ngân hàng báo** làm
số dư hiển thị.

Nguyên tắc thiết kế:

| Nguyên tắc | Ý nghĩa |
|---|---|
| **Offline-first** | Mọi thao tác ghi vào SQLite trên máy ngay lập tức; mạng chỉ dùng để đồng bộ. Không có mạng, không có tài khoản vẫn dùng đủ tính năng. |
| **Dữ liệu tách theo tài khoản** | Mỗi tài khoản Google/email chỉ đọc và ghi được dữ liệu của chính mình (Row Level Security trên Postgres). |
| **Không trùng lặp** | Nhiều điện thoại cùng tài khoản cùng nhận một thông báo vẫn chỉ ra một giao dịch. |
| **Thông tin nhạy cảm ở lại trên máy** | Nội dung thông báo ngân hàng gốc chỉ lưu cục bộ, không bao giờ gửi lên máy chủ. |

---

## Tính năng

### Tự động từ thông báo ngân hàng *(Android)*

- **Nhận diện mọi ngân hàng và ví Việt Nam** qua `NotificationListenerService`: số tiền, chiều thu/chi,
  số dư sau giao dịch, 4 số cuối tài khoản, nội dung chuyển khoản, tên người chuyển.
- **Lọc nhầm:** bỏ qua OTP, khuyến mãi, tin nhắn chat, giao dịch lỗi/chờ duyệt. Có nhật ký nhận diện,
  danh sách ứng dụng tin cậy/chặn và công cụ thử nhận diện một tin nhắn mẫu.
- **Số dư theo ngân hàng:** trang chủ hiển thị đúng con số ngân hàng báo, tách riêng từng tài khoản.
  Thông báo không ghi số dư thì cộng/trừ từ số dư gần nhất và gắn nhãn *ước tính*.
- **Xem lại thông báo gốc** trong chi tiết giao dịch (tiêu đề, nội dung, giờ nhận, số dư sau GD).
- **Đọc giọng tiếng Việt:** "ting ting", *"Bạn đã nhận được 150 nghìn đồng từ Nguyễn Văn A"*;
  tuỳ chỉnh giọng nam/nữ, tốc độ, cao độ, âm báo, khuếch đại âm lượng.
- **Gắn vị trí tự động:** lấy vị trí điện thoại ngay khi có thông báo (kể cả khi app đang đóng,
  cần quyền *Luôn cho phép*), đổi sang địa chỉ đường/phường/quận.
- **Tự đoán danh mục** từ nội dung chuyển khoản (ăn uống, di chuyển, hoá đơn, lương…).

### Chống trùng giữa nhiều thiết bị

1. **Mã giao dịch tất định:** UUIDv5 tạo từ *tài khoản + chiều + số tiền + số dư sau giao dịch*.
   Hai máy nhận cùng một thông báo ra cùng một mã, lên máy chủ tự gộp làm một.
2. **Dọn trùng sau đồng bộ:** giao dịch cùng loại, cùng số tiền, lệch nhau ≤ 60 giây được coi là trùng.
   Giữ bản **có ảnh**, sau đó bản sớm hơn, sau đó mã nhỏ hơn, nên mọi máy chọn cùng một bản.
   Thông báo gốc của bản bị xoá được chuyển sang bản giữ lại.

### Tài khoản và đồng bộ

- Đăng nhập **Google** hoặc **email + mật khẩu**; quên mật khẩu qua link trong email mở thẳng vào app.
- **Nhiều tài khoản trên một máy**, chuyển nhanh kiểu Gmail không cần đăng nhập lại.
- Đồng bộ nền qua hàng đợi **outbox**: ghi cục bộ → đẩy lên khi có mạng (thử lại với backoff lũy thừa)
  → kéo thay đổi mới theo `server_updated_at`. Xung đột giải quyết theo **last-write-wins**, tôn trọng bản xoá.
- Dữ liệu nhập khi còn offline được **gộp vào tài khoản** ở lần đăng nhập đầu tiên.
- **Dọn bộ nhớ sau đồng bộ:** xoá ảnh đã tải lên, bản ghi đã xoá, chuyển giao dịch cũ sang bảng lưu trữ
  rút gọn (30/90/180/365 ngày hoặc giữ vĩnh viễn) mà số dư vẫn đúng.

### Quản lý chi tiêu

- **Trang chủ:** số dư, thu nhập / chi tiêu / tiết kiệm **của tháng hiện tại** (sang tháng mới tự về 0),
  tổng quan hôm nay, dải ảnh khoảnh khắc.
- **Giao dịch:** tên, số tiền, danh mục, ghi chú, ngày giờ, vị trí, ảnh.
- **Khoảnh khắc:** chụp ảnh vuông kiểu Locket gắn vào giao dịch, tự lưu vị trí và tên nơi chụp.
- **Lịch sử:** tìm kiếm, lọc theo loại/danh mục/khoảng thời gian, phân trang.
- **Lịch:** mỗi ngày hiển thị chênh lệch thu − chi (`+150k`, `−320k`); ngày không có giao dịch để trống.
- **Thống kê:** theo tuần/tháng/năm, biểu đồ xu hướng, cơ cấu theo danh mục.
- **Bản đồ kiểu Google Photos:** ảnh vệ tinh kèm tên đường; ảnh giao dịch hiện ngay trên bản đồ, gom
  cụm theo mức phóng; bảng *Trong khu vực này* liệt kê giao dịch trong vùng đang xem theo địa chỉ.
  Dùng Google Maps khi có khoá API, không thì dùng ảnh vệ tinh Esri.
- **Danh mục** tuỳ chỉnh (biểu tượng, màu).
- **Sao lưu / khôi phục** JSON có checksum SHA-256; xuất CSV (chống chèn công thức bảng tính).
- **Khoá ứng dụng bằng mã PIN.**

### Giao diện

- Phong cách **Liquid Glass**: thẻ kính mờ, nền chất lỏng chuyển động, công tắc và thanh điều hướng kính.
- **Responsive** từ điện thoại tới màn hình desktop; chế độ Sáng/Tối; tuỳ chọn giảm hiệu ứng.
- **4 ngôn ngữ:** Tiếng Việt, English, 简体中文, 繁體中文.

---

## Công nghệ

| Lớp | Công nghệ |
|---|---|
| Ứng dụng | Flutter (Dart 3.6+), Material 3 |
| Quản lý trạng thái | Riverpod 2 |
| Lưu trữ cục bộ | SQLite (`sqflite`, `sqflite_common_ffi` cho Windows) |
| Backend | Supabase: Auth (Google OAuth, email), Postgres + RLS, Storage (bucket riêng tư) |
| Bản đồ | `flutter_map` (Esri World Imagery), `google_maps_flutter` (tuỳ chọn) |
| Vị trí | `geolocator`, `geocoding`; `LocationManager` phía Android native |
| Native Android | Java: đọc thông báo, nhận diện, giọng đọc TTS, âm báo, định vị nền |
| Build | PowerShell scripts, Gradle (Kotlin DSL), CMake (Windows), Inno Setup (tuỳ chọn) |

---

## Kiến trúc

```
┌──────────────────────────────── Flutter app ────────────────────────────────┐
│  UI (features/*)  ──►  Riverpod providers  ──►  Repositories / Use cases     │
│                                                   │               │          │
│                                         SQLite (nguồn sự thật)   Domain     │
│                                                   │            (logic thuần) │
│                                            Outbox + SyncEngine               │
└───────────────────────────────────────────────────┼──────────────────────────┘
        ▲ MethodChannel                             │ HTTPS
┌───────┴────────────── Android native ─────┐       ▼
│ BankNotificationListener → BankParser     │   Supabase
│ → hàng chờ (SharedPreferences)            │   ├─ Auth (Google / email)
│ BankSpeaker (TTS) · BankLocator (GPS)     │   ├─ Postgres + RLS + trigger LWW
└───────────────────────────────────────────┘   └─ Storage `receipts` (riêng tư)
```

- **Giao diện không gọi Supabase trực tiếp.** Mọi ghi đọc đi qua repository vào SQLite; `SyncEngine`
  là nơi duy nhất nói chuyện với máy chủ qua giao diện `RemoteGateway` (dễ thay thế khi test).
- **Logic nghiệp vụ thuần** (tính số dư, thống kê, giải xung đột, đoán danh mục) nằm trong
  `domain/usecases`, không phụ thuộc Flutter, có unit test riêng.
- **Native → Flutter:** dịch vụ Android ghi giao dịch vào hàng chờ bền vững; Flutter lấy về, lưu vào
  SQLite rồi mới xác nhận để Android xoá, nên app bị tắt giữa chừng cũng không mất giao dịch.

### Dữ liệu

| Bảng cục bộ (SQLite) | Bảng máy chủ (Postgres) | Ghi chú |
|---|---|---|
| `transactions`, `tx_archive` | `transactions` | Số tiền lưu dạng số nguyên ×100 để tránh sai số |
| `categories` | `categories` | Danh mục mặc định có mã tất định theo tài khoản |
| `budgets`, `recurring_rules` | `budgets`, `recurring_transactions` | Giữ để không mất dữ liệu cũ (tính năng đã gỡ khỏi UI) |
| `bank_messages` | — | Thông báo gốc, **chỉ trên máy** |
| `outbox`, `sync_meta` | — | Hàng đợi đồng bộ, mốc kéo dữ liệu |
| — | `profiles`, `attachments`, `audit_logs`… | Hồ sơ, tệp đính kèm, nhật ký |

---

## Cấu trúc thư mục

```
smart_finance/
├── lib/
│   ├── core/          cấu hình, hằng số, theme, đa ngôn ngữ, mạng, SQLite, bảo mật, tiện ích
│   ├── data/          DAO cục bộ, gateway Supabase, mapper, repository, đồng bộ, sao lưu
│   ├── domain/        entity, giao diện repository, use case (logic thuần)
│   ├── features/      auth · bank · home · transactions · moments · calendar
│   │                  statistics · categories · map · settings
│   └── shared/        widget dùng chung (Liquid Glass), Riverpod providers
├── native/android/    mã Java/Kotlin (đọc thông báo, giọng đọc, định vị) + test nhận diện
├── android/ windows/  project nền tảng (script build tự vá và chép mã native vào)
├── supabase/          setup_all.sql, migrations, rollback, pgTAP RLS test, seed
├── test/              unit + widget test
├── integration_test/  luồng end-to-end
├── scripts/           build.ps1, check.ps1, setup_windows.ps1, patch_platforms.ps1
├── installer/         Inno Setup (tạo bộ cài Windows)
├── config/            env.example.json (env.json không đưa lên git)
├── docs/              hướng dẫn, nhật ký quyết định, kế hoạch kiểm thử, tài liệu phân tích
└── releases/          bản build (chỉ giữ bản mới nhất)
```

---

## Bắt đầu nhanh

### Yêu cầu

- Windows 10/11 64-bit
- Flutter 3.27+ (Dart 3.6+)
- Visual Studio Build Tools (C++) để build Windows
- Android SDK + JDK 17 để build APK

`setup.bat` cài tự động Flutter, Visual Studio Build Tools và bật Developer Mode.

### Chạy thử

```bat
setup.bat            :: chỉ lần đầu
run_dev.bat          :: chạy bản Windows (hot reload)
run_dev.bat android  :: chạy trên điện thoại Android đang cắm
```

Không cấu hình máy chủ thì app chạy **hoàn toàn offline**.

### Bật đồng bộ cloud

1. Tạo project Supabase (gói Free đủ dùng), chạy `supabase/setup_all.sql` trong SQL Editor.
2. Bật đăng nhập email/Google và thêm Redirect URLs.
3. Điền `config/env.json` rồi build lại.

Hướng dẫn từng bước có hình minh hoạ: **[docs/HUONG_DAN_SUPABASE.md](docs/HUONG_DAN_SUPABASE.md)**.

---

## Cấu hình

Tạo `config/env.json` từ `config/env.example.json`:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_ANON_KEY": "sb_publishable_...",
  "OAUTH_DESKTOP_PORT": "3789",
  "GOOGLE_MAPS_API_KEY": ""
}
```

| Khoá | Bắt buộc | Mô tả |
|---|---|---|
| `SUPABASE_URL` | Không | URL project Supabase. Để trống = chạy offline. |
| `SUPABASE_ANON_KEY` | Không | **Publishable key** (khoá công khai). Script build **từ chối** secret/service_role key. |
| `OAUTH_DESKTOP_PORT` | Không | Cổng loopback nhận kết quả đăng nhập Google trên Windows. |
| `GOOGLE_MAPS_API_KEY` | Không | Khoá *Maps SDK for Android*. Để trống = dùng ảnh vệ tinh Esri. |

Máy chủ **chỉ đặt lúc build**, không sửa được trong app, để người khác (hay trẻ nhỏ) không đổi nhầm
trên điện thoại. Redirect URL cần khai báo trên Supabase:

```
io.smartfinance.app://login-callback      (Android)
http://localhost:3789/auth-callback       (Windows)
```

---

## Build và phát hành

```bat
build.bat              :: build SmartFinance.exe (Windows)
build_apk.bat          :: build exe + APK Android, bỏ qua test
build.bat -Apk -Notes "Mô tả thay đổi"
```

| Tuỳ chọn | Tác dụng |
|---|---|
| `-Bump build\|patch\|minor\|major` | Tăng phiên bản (mặc định tăng số build) |
| `-Apk` | Build thêm APK Android |
| `-Notes "..."` | Ghi chú đưa vào CHANGELOG và RELEASE_NOTES |
| `-SkipTests` / `-Strict` | Bỏ qua test / dừng nếu analyze hay test lỗi |
| `-NoZip`, `-NoOpen` | Không nén zip / không mở thư mục kết quả |

Script tự động: vá cấu hình nền tảng, chép mã native, kiểm tra khoá bí mật, chạy `flutter analyze`,
build, ký APK bằng keystore trong `android/key.properties`, tăng phiên bản trong `pubspec.yaml`,
ghi `CHANGELOG.md`. Mỗi bản build nằm trong thư mục riêng:

```
releases/v1.0.0+19_20260929-0213/
├── SmartFinance/SmartFinance.exe          bản chạy trực tiếp
├── SmartFinance_v1.0.0+19_windows_x64.zip
├── SmartFinance_v1.0.0+19.apk
├── manifest.json                          phiên bản, sha256, kết quả kiểm tra
└── RELEASE_NOTES.md
```

Chi tiết: [docs/BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md).

---

## Kiểm thử và chất lượng mã

```bat
check.bat            :: flutter analyze + flutter test
```

- **105 test** Flutter (unit + widget), gồm:
  - bộ nhập thông báo ngân hàng, chống trùng mô phỏng 2–3 điện thoại, dọn trùng sau đồng bộ;
  - số dư theo ngân hàng, gắn vị trí, nhiều tài khoản trên một máy;
  - SyncEngine (outbox, backoff, xung đột), repository, sao lưu/khôi phục;
  - gom cụm bản đồ, lịch, thống kê, đa ngôn ngữ đồng bộ khoá, bố cục responsive.
- **65 test** Java cho bộ nhận diện thông báo (chạy bằng JDK thuần):
  ```bat
  javac -encoding UTF-8 -d out native/android/Bank*.java native/android/SenderName.java ^
        native/android/VietnameseNumber.java native/android/test/BankParserTest.java
  java -cp out io.smartfinance.smart_finance.BankParserTest
  ```
- **pgTAP** kiểm tra cách ly dữ liệu RLS: `supabase/tests/rls_isolation.test.sql`.
- `flutter analyze` không cảnh báo; mã định dạng bằng `dart format` (100 cột).

---

## Bảo mật và quyền riêng tư

- App chỉ chứa **publishable key**; secret/service_role key bị script build chặn.
- **Row Level Security** trên mọi bảng: tài khoản A không đọc được dữ liệu hay ảnh của tài khoản B.
- Ảnh nằm trong bucket **riêng tư**, xem qua link ký tạm thời.
- **Thông báo ngân hàng gốc không rời khỏi điện thoại.**
- Mật khẩu do Supabase Auth xử lý; app không lưu mật khẩu.
- `config/env.json`, keystore, `key.properties` và file token nằm trong `.gitignore`.
- Chính sách quyền riêng tư: <https://urishaw.github.io/smart-finance/privacy.html>

### Quyền Android

| Quyền | Dùng để |
|---|---|
| Truy cập thông báo | Đọc thông báo biến động số dư (người dùng tự bật) |
| Vị trí (+ *Luôn cho phép*, tuỳ chọn) | Gắn vị trí cho giao dịch, kể cả khi app đóng |
| Bỏ qua tối ưu pin, khởi động cùng máy | Giữ dịch vụ đọc thông báo chạy nền ổn định |
| Internet, trạng thái mạng | Đồng bộ, tải bản đồ |

Chụp ảnh khoảnh khắc đi qua ứng dụng Camera của hệ thống nên app không cần quyền camera riêng.

---

## Giới hạn đã biết

- **iOS không hỗ trợ đọc thông báo của ứng dụng khác**, nên các tính năng tự động chỉ có trên Android.
  Chưa có bản build iOS.
- Một số hãng (Xiaomi, Oppo, Vivo…) hạn chế chạy nền; cần tắt tối ưu pin cho app.
- Hai thiết bị đọc được số dư khác nhau cho cùng một thông báo (ví dụ SMS và app ngân hàng) có thể
  cần tới bước dọn trùng thay vì gộp theo mã.
- Gói Free của Supabase: email khôi phục mật khẩu chỉ có link (không sửa được mẫu email nếu chưa có
  SMTP riêng); project tạm dừng sau 7 ngày không hoạt động.

---

## Tài liệu

| Tài liệu | Nội dung |
|---|---|
| [docs/HUONG_DAN_SUPABASE.md](docs/HUONG_DAN_SUPABASE.md) | Tạo máy chủ Supabase, đăng nhập Google, Google Maps |
| [docs/BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md) | Chuẩn bị máy và build chi tiết |
| [docs/DECISION_LOG.md](docs/DECISION_LOG.md) | Nhật ký quyết định kỹ thuật (DEC-xxx) |
| [docs/CHANGE_REQUESTS.md](docs/CHANGE_REQUESTS.md) | Yêu cầu thay đổi |
| [docs/TEST_PLAN.md](docs/TEST_PLAN.md) | Kế hoạch kiểm thử |
| [docs/phases/](docs/phases/) | Khảo sát, yêu cầu, use case, thiết kế kiến trúc |
| [CHANGELOG.md](CHANGELOG.md) | Lịch sử phiên bản |

---

**Tác giả:** UriShaw · [urishaw2005@gmail.com](mailto:urishaw2005@gmail.com)
