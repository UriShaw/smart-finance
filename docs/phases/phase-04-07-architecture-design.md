# Phase 4 — Architecture · Phase 5 — UI/UX · Phase 6 — Database & Security · Phase 7 — Dependency Baseline

## Phase 4 — System Architecture

```
┌──────────── Flutter app (Windows / Android) ─────────────┐
│ Widgets (features/*)  ── không chứa business logic       │
│    │ ref.watch / ref.read                                │
│ Riverpod providers (shared/providers)                    │
│    │                                                     │
│ Repositories (data/repositories) ── ghi LOCAL trước      │
│    │            │                                        │
│ SQLite (sqflite/ffi)   Outbox ──► SyncEngine ──► RemoteGateway (interface)
│    ▲                                  │            └─ SupabaseGateway
│    └──── pull / conflict resolver ◄───┘                  │
│ Domain usecases (thuần Dart, có unit test)               │
└──────────────────────────────────────────────────────────┘
                     │ HTTPS (anon key + JWT user)
┌──────────── Supabase ────────────────────────────────────┐
│ Auth (Google) · Postgres + RLS · Storage (receipts)      │
│ Edge Functions: ai-assistant, admin-metrics              │
└──────────────────────────────────────────────────────────┘
```

### Sync design (spec H)

- **Ghi:** User → Repository (transaction SQLite: upsert bản ghi + enqueue outbox) → UI cập nhật qua `DataEvents` → debounce 2s → SyncEngine.
- **Outbox:** 1 dòng/entity (gộp thay đổi), cột `revision` tăng mỗi lần enqueue → chỉ xóa khi revision không đổi (không mất thay đổi xảy ra trong lúc đẩy).
- **Push:** thứ tự categories → recurring → budgets → transactions (khóa ngoại). Upsert theo UUID ⇒ idempotent.
- **Retry:** exponential backoff `5s·2^n` (tối đa 30 phút) + jitter 20%; lỗi mạng/auth dừng lượt; lỗi bản ghi đơn lẻ không chặn bản ghi khác (partial failure). ≥5 lần → `sync_status = failed` (vẫn thử tiếp).
- **Ảnh:** upload trước metadata; lỗi upload → vẫn đẩy metadata nhưng KHÔNG đánh dấu synced, giữ outbox + file tạm; thành công → xóa file tạm (trừ khi bật "giữ ảnh gốc").
- **Pull:** theo con trỏ `server_updated_at` (clock_timestamp phía server) từng bảng, trang 500.
- **Conflict (DEC-007):** LWW theo `updated_at` client + bảo vệ pending local (local ≥ remote ⇒ giữ local). Server có **LWW guard**: update cũ hơn bị bỏ qua.
- **Delete:** tombstone `deleted_at`; sau khi lên cloud → xóa hẳn ở máy; server dọn sau 90 ngày.
- **Dọn bộ nhớ tạm (CR-002):** CacheJanitor chạy sau mỗi lần sync: tombstone đã sync, ảnh đã upload, ảnh mồ côi, và giao dịch cũ hơn *N ngày* (mặc định 180) → chuyển sang `tx_archive` rút gọn (id, loại, số tiền, ngày, danh mục) ⇒ số dư/thống kê/ngân sách vẫn đúng khi offline, chi tiết cũ tải lại từ cloud khi cần. Không bao giờ xóa bản ghi còn trong outbox.
- **Trigger sync:** mở app, đăng nhập, ghi local, có mạng trở lại, quay lại app, mỗi 5 phút, kéo để làm mới, nút "Đồng bộ ngay".

### Auth
Windows: OAuth PKCE + loopback `http://localhost:3789/auth-callback`. Android: deep link `io.smartfinance.app://login-callback`.
Dùng offline trước rồi đăng nhập → `LocalDataClaimer` chuyển dữ liệu `local` sang user id thật (đổi id danh mục mặc định).

## Phase 5 — UI/UX & Design System

- Tokens: `core/theme/app_theme.dart` (màu seed #4F7CFF, thu #16A34A, chi #E11D48, cảnh báo #F59E0B; radius 12/20/28; spacing 4-32).
- Liquid Glass: `GlassBackground` (gradient + blob), `GlassCard` (blur 18, viền sáng, bóng) – tắt blur khi bật **Giảm hiệu ứng**.
- Responsive: <600px NavigationBar 5 mục (Cài đặt kiêm menu "Thêm"); ≥600px NavigationRail đủ 8 mục; ≥1100px rail mở rộng; `ContentWidth` giới hạn bề rộng nội dung; lịch/thống kê/bản đồ chia 2 cột ≥900px.
- Accessibility: số tiền có dấu +/− ngoài màu; Semantics cho ô lịch, biểu đồ, badge sync; touch target ≥48; hỗ trợ text scale.

## Phase 6 — Database & Security

ERD (Postgres):

```
auth.users 1─1 profiles
auth.users 1─* categories ─┐ (id,user_id)
auth.users 1─* recurring_transactions ─┐
auth.users 1─* transactions ─ (category_id,user_id)→categories, (recurring_id,user_id)→recurring
auth.users 1─* budgets ─ (category_id,user_id)→categories
transactions 1─* attachments
app_admins (RBAC) · category_templates (admin) · audit_logs (metadata)
```

- Tiền: `amount_minor BIGINT` = giá trị ×100, CHECK > 0 (DEC-006).
- Khóa ngoại **kép (id, user_id)** ⇒ không tham chiếu dữ liệu của user khác.
- RLS mọi bảng: `user_id = auth.uid()` cho select/insert/update/delete. Admin **không** có policy đọc giao dịch; chỉ RPC tổng hợp `admin_dashboard_metrics()` (security definer, kiểm tra `is_admin()` ở backend, ghi audit).
- Storage `receipts` private, 5MB, chỉ ảnh; đường dẫn phải bắt đầu bằng `<uid>/`.
- Test RLS 2 user: `supabase/tests/rls_isolation.test.sql`.
- Local SQLite: `transactions`, `categories`, `budgets`, `recurring_rules`, `tx_archive`, view `v_ledger`, `outbox`, `sync_meta`; migrations đánh số trong `AppDatabase._migrations`.

## Phase 7 — Dependency Baseline

| Package | Ràng buộc | Lý do |
|---|---|---|
| flutter_riverpod | ^2.6.1 | State management (DEC-004), không cần codegen |
| supabase_flutter | ^2.8.0 | Auth/DB/Storage/Functions |
| sqflite / sqflite_common_ffi / sqlite3_flutter_libs | ^2.4.1 / ^2.3.4 / >=0.5.24 <0.7 | SQLite Android + Windows (DEC-003) |
| path, path_provider | ^1.9 / ^2.1.4 | Đường dẫn dữ liệu app |
| shared_preferences | ^2.3.2 | Cài đặt |
| uuid | ^4.5.1 | UUID v4/v5 client |
| intl + flutter_localizations | SDK | Định dạng số/ngày |
| crypto | ^3.0.5 | SHA-256 checksum backup, hash PIN |
| connectivity_plus | ^6.1.0 | Phát hiện mạng |
| url_launcher | ^6.3.0 | Mở trình duyệt đăng nhập (desktop) |
| image_picker / image | ^1.1.2 / ^4.2.0 | Chọn ảnh, nén/resize |
| file_selector | ^1.0.3 | Chọn nơi lưu backup/CSV |
| flutter_map / latlong2 | ^7.0.2 / ^0.9.1 | Bản đồ OSM (DEC-009) |
| flutter_lints | ^5.0.0 | Analyzer |

Biểu đồ vẽ bằng `CustomPainter` (không thêm package chart). `pubspec.lock` sinh ở lần build đầu → commit để khóa phiên bản.
