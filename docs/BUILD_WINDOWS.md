# Build Smart Finance cho Windows

## Yêu cầu (setup.bat tự cài)

| Thành phần | Ghi chú |
|---|---|
| Windows 10/11 64-bit | winget có sẵn (App Installer) |
| Flutter SDK stable ≥ 3.27 | cài vào `C:\src\flutter`, thêm vào PATH |
| Visual Studio 2022 Build Tools | workload **Desktop development with C++** |
| Developer Mode | cần để plugin Flutter tạo symlink |
| Git | tùy chọn (ghi commit vào manifest) |
| Inno Setup 6 | tùy chọn – tạo bộ cài 1 file `SmartFinance_Setup_x.exe` |

## Các bước

```bat
setup.bat          :: 1 lần. Nếu cài Build Tools -> có thể cần khởi động lại máy
build.bat          :: mỗi lần muốn ra bản mới
```

`build.bat` làm tuần tự:

1. Kiểm tra Flutter, Visual Studio C++, Developer Mode.
2. Nếu chưa có thư mục `windows\` → `flutter create` (chỉ thêm file thiếu) + vá tên exe/tiêu đề.
3. Tính phiên bản mới từ `pubspec.yaml` (mặc định tăng build number).
4. Đọc `config\env.json` (tự tạo từ mẫu nếu thiếu).
5. **Quét secret**: chặn nếu thấy service-role key.
6. `flutter pub get`.
7. **Quality gate**: `dart format` (báo cáo), `flutter analyze`, `flutter test`.
   Mặc định lỗi được ghi vào manifest và vẫn build; `-Strict` để dừng khi lỗi.
8. `flutter build windows --release` (kèm `APP_VERSION`, `APP_ENV`).
9. Tạo `releases\v<version>_<ngày-giờ>\` + zip + (bộ cài) + manifest (SHA-256) + release notes,
   cập nhật `releases\latest`, `releases\README.md`, `CHANGELOG.md`, rồi ghi version mới vào `pubspec.yaml`.

Log đầy đủ: `build_logs\build_<thời gian>.log`.

## Lỗi thường gặp

| Thông báo | Cách xử lý |
|---|---|
| `Building with plugins requires symlink support` | Bật Developer Mode: `start ms-settings:developers` |
| `Unable to find suitable Visual Studio toolchain` | Chạy lại `setup.bat` hoặc cài workload C++ trong Visual Studio Installer |
| `pub get failed` | Kiểm tra mạng; `flutter upgrade`; xóa `pubspec.lock` rồi build lại |
| Exe mở rồi tắt ngay | Chạy `releases\latest\SmartFinance\SmartFinance.exe` từ cmd để xem lỗi; giữ đủ `.dll` + `data\` cạnh exe |
| Đăng nhập Google không quay về app | Thêm `http://localhost:3789/auth-callback` vào Supabase → Auth → Redirect URLs; cổng 3789 không bị chiếm |

## Phân phối

- Gửi **cả thư mục** `SmartFinance\` hoặc file `.zip` (exe cần các `.dll` và `data\` đi kèm).
- Hoặc cài Inno Setup 6 → build lại → gửi 1 file `SmartFinance_Setup_x.y.z+n.exe`.
- Dữ liệu người dùng lưu tại `%APPDATA%\Smart Finance\Smart Finance\` (không nằm trong thư mục cài, nên cập nhật phiên bản không mất dữ liệu).
