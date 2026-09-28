# Smart Finance

Ứng dụng quản lý chi tiêu cá nhân **offline-first**, xây lại từ đầu bằng **Flutter + Supabase**
theo mô hình Waterfall (tài liệu trong `docs/`). Chạy trên **Windows (.exe)** và Android.

- Offline: mọi thao tác ghi vào SQLite trên máy ngay lập tức → hàng đợi (outbox) → tự đẩy lên cloud khi có mạng.
- Sau khi đồng bộ thành công, **bộ nhớ tạm được dọn** (ảnh đã upload, hàng đợi, bản ghi đã xóa, giao dịch cũ quá hạn giữ) để không đầy bộ nhớ.
- Đăng nhập Google / email qua Supabase Auth; nhiều tài khoản trên một máy, chuyển nhanh kiểu Gmail,
  dữ liệu mỗi tài khoản tách riêng (RLS).
- (Android) Tự ghi giao dịch từ thông báo ngân hàng, số dư theo đúng ngân hàng báo, xem lại tin nhắn gốc,
  chống trùng khi nhiều điện thoại cùng nhận thông báo.
- Tổng quan, giao dịch (ảnh khoảnh khắc, vị trí, ghi chú), lịch sử (tìm kiếm/lọc/phân trang), lịch chi tiêu,
  thống kê, bản đồ kiểu Google Photos (OSM / Google Maps, địa hình, vệ tinh), sao lưu/khôi phục, khóa PIN.
- Giao diện Liquid Glass, responsive (điện thoại → desktop), Sáng/Tối, 🇻🇳 🇬🇧 简体 繁體.

## ⚡ Build 1 lệnh

```bat
setup.bat      :: chỉ lần đầu: cài Flutter + Visual Studio Build Tools (C++) + bật Developer Mode
build.bat      :: tạo SmartFinance.exe và lưu vào releases\
```

Mỗi lần chạy `build.bat` sẽ tạo **một thư mục phiên bản riêng**:

```
releases\
  README.md                                  <- bảng liệt kê mọi phiên bản
  latest\                                    <- bản mới nhất
  v1.0.0+2_20260923-1530\
    SmartFinance\SmartFinance.exe (+ dll, data\)   <- chạy trực tiếp
    SmartFinance_v1.0.0+2_windows_x64.zip
    SmartFinance_Setup_1.0.0+2.exe          <- nếu máy có Inno Setup
    manifest.json   (version, sha256, kết quả analyze/test, migrations)
    RELEASE_NOTES.md
```

Tùy chọn: `build.bat -Bump patch|minor|major`, `-Notes "..."`, `-Apk`, `-SkipTests`, `-Strict`, `-NoZip`.
Chi tiết: [docs/BUILD_WINDOWS.md](docs/BUILD_WINDOWS.md). Chạy bản dev (hot reload): `run_dev.bat`.

## Bật đồng bộ cloud (tùy chọn)

1. Tạo project Supabase + đăng nhập Google: xem [docs/HUONG_DAN_SUPABASE.md](docs/HUONG_DAN_SUPABASE.md).
2. Điền `config/env.json` (tạo từ `config/env.example.json`): `SUPABASE_URL`, `SUPABASE_ANON_KEY`
   (publishable key), tuỳ chọn `GOOGLE_MAPS_API_KEY`.
   **Tuyệt đối không** đặt service-role key vào app — script build sẽ chặn.
3. `build.bat` lại. Không cấu hình → app vẫn chạy 100% offline.

## Cấu trúc

```
lib/
  core/        config, constants, theme, localization, network, storage, security, utils, errors
  data/        local (SQLite DAO), remote (Supabase), models (mapper), repositories, sync, backup
  domain/      entities, repositories (RemoteGateway), usecases (logic thuần - có unit test)
  features/    auth, bank, home, transactions, moments, calendar, statistics, categories, map, settings
  shared/      widgets, providers (Riverpod)
test/          unit + widget test (sync engine, RLS-logic, backup, localization, responsive)
integration_test/
supabase/      setup_all.sql, migrations (versioned SQL + RLS), tests (pgTAP RLS), seed
native/        mã Android (đọc thông báo ngân hàng, giọng đọc) - script build chép vào android/
docs/          Phase 1-7, Decision Log, Change Requests, test plan
scripts/       build.ps1, check.ps1, setup_windows.ps1, patch_platforms.ps1
```

Luồng: **UI → Controller/Provider → UseCase/Repository → Local DB / Remote** (UI không gọi Supabase trực tiếp).
