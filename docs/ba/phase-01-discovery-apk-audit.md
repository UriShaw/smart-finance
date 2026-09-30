# Phase 1 — Discovery & APK Audit

## 1. Objective
Khảo sát `app-debug.apk` (ứng dụng cũ) để hiểu chức năng/luồng/dữ liệu, làm đầu vào cho Smart Finance mới.
Không convert APK, không khôi phục source 1:1, không sao chép branding.

## 2. Findings

Phương pháp: giải nén APK, đọc tên lớp trong 15 file `classes*.dex`, chuỗi SQL Room, `AndroidManifest.xml` (binary XML), tài nguyên.
Mức tin cậy: **Confirmed** (thấy trực tiếp) / **Likely** (suy luận mạnh) / **Unknown**.

### 2.1 Công nghệ

| Hạng mục | Phát hiện | Tin cậy |
|---|---|---|
| Ngôn ngữ/UI | Kotlin + Jetpack Compose (Material 3), package `com.example` | Confirmed |
| Kiến trúc | 1 `FinanceViewModel` + `FinanceParserRepository` (MVVM, ViewModel lớn) | Confirmed |
| Local DB | Room – `AppDatabase`, `TransactionDao`, 1 bảng `transactions` | Confirmed |
| Cloud | Firebase Auth + Cloud Firestore (+ Analytics) | Confirmed |
| Đăng nhập | Google Sign-In (Credential Manager / Play Services) | Confirmed |
| AI | Gọi thẳng Gemini REST `generativelanguage.googleapis.com/v1beta/models/gemini-…:generateContent` từ app (Retrofit + Moshi) | Confirmed |
| Bảo mật | `USE_BIOMETRIC` (khóa sinh trắc) | Confirmed |
| Nền | `BankNotificationListenerService`, `KeepAliveService` (foreground), `BootReceiver`, `SoundAmplifier` (TTS) | Confirmed |
| API key AI | Có khả năng nằm trong APK (gọi Gemini trực tiếp) | Likely |

### 2.2 Màn hình & điều hướng

| Màn hình | Nguồn | Tin cậy |
|---|---|---|
| Onboarding | `OnboardingScreenKt` | Confirmed |
| Main (bottom navigation `NavigationItem`) | `MainScreenKt` | Confirmed |
| Home | `HomeScreenKt` | Confirmed |
| History | `HistoryScreenKt` | Confirmed |
| Statistics | `StatisticsScreenKt` | Confirmed |
| Settings | `SettingsScreenKt` | Confirmed |
| Chi tiết giao dịch (bottom sheet) | `TransactionDetailBottomSheetKt` | Confirmed |
| Lịch chi tiêu, Ngân sách, Định kỳ, Bản đồ | Không thấy lớp tương ứng | Unknown → thiết kế mới |

### 2.3 Data model cũ (Room, Confirmed)

```sql
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT, userId TEXT, msgRaw TEXT, amount INTEGER,
  is_income INTEGER, balance INTEGER, category TEXT, merchant TEXT, confidence REAL,
  timestamp INTEGER, accountNumber TEXT, note TEXT, cloudId TEXT)
```

Nhận xét: id tự tăng (không idempotent giữa thiết bị), category là text tự do, không có soft-delete,
không có updated_at → không giải quyết xung đột được; lưu `msgRaw` (nội dung SMS/thông báo ngân hàng)
và `accountNumber` → dữ liệu nhạy cảm.

### 2.4 Chức năng cũ

| Chức năng | Tin cậy |
|---|---|
| Tự ghi giao dịch từ thông báo ngân hàng (regex `RegexParser`, số → chữ tiếng Việt, đọc TTS) | Confirmed |
| Phân loại bằng Gemini (`GeminiCategorization`) | Confirmed |
| Đồng bộ Firestore theo userId | Confirmed |
| Thống kê, lịch sử | Confirmed |
| Khóa sinh trắc | Likely |
| Ảnh hóa đơn, vị trí, ngân sách, định kỳ, export | Unknown (không thấy) |

### 2.5 Điểm mạnh / yếu

- **Mạnh:** tự động ghi nhận qua thông báo ngân hàng; tiếng Việt; AI phân loại.
- **Yếu:** secret AI ở client; id không idempotent; không tombstone; logic dồn vào 1 ViewModel;
  phụ thuộc Firebase; service nền tiêu pin; không có test; nhiều lỗi lịch sử (serialization Firestore,
  lệch userId, mất session khi cold start, R8 phá reflection).

## 3. Old App → New Smart Finance

| Cũ | Mới | Lý do |
|---|---|---|
| Kotlin/Compose (Android) | Flutter (Windows + Android) | Yêu cầu exe + đa nền tảng |
| Firebase Auth/Firestore | Supabase Auth/Postgres/Storage + RLS | DEC-001 |
| Room, id INTEGER | SQLite + UUID client, soft delete, updated_at, outbox | Offline-first, idempotent |
| Gemini gọi thẳng từ app | Edge Function giữ key, app chỉ gửi 1 câu | Không lộ secret |
| category TEXT | bảng categories + id xác định (UUID v5) | Không trùng giữa thiết bị |
| Notification listener | **CR-001** (chưa đưa vào MVP) | Chỉ Android, quyền nhạy cảm |
| Không có | Ảnh hóa đơn, vị trí/bản đồ, lịch, ngân sách, định kỳ, backup, PIN | Theo spec D |

## 4. Kiến trúc đề xuất (high-level)
UI → Riverpod provider → Repository → SQLite (ghi trước) → Outbox → Sync Engine → Supabase (RLS).
Chi tiết: Phase 4.

## 5. Open Questions
1. Có cần tính năng đọc thông báo ngân hàng trên Android không? → CR-001.
2. Đơn vị tiền tệ mặc định VND, có cần đa tiền tệ có tỷ giá? → MVP: chỉ đổi hiển thị (DEC-006).
3. AI provider nào (Gemini/OpenAI)? → abstraction ở Edge Function, mặc định Gemini.
4. Web Admin cần chức năng gì ngoài dashboard số liệu tổng hợp? → Phase 16.

## 6. Exit Gate
Người dùng chọn "code luôn MVP" (23/09/2026) → các phase 2-7 được viết gọn và triển khai code MVP.
