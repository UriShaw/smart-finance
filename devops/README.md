# DevOps · Build, cài đặt, phát hành

Bấm đúp các file `.bat` trong thư mục này:

| File | Việc |
|---|---|
| `setup.bat` | Cài môi trường lần đầu: Flutter, Visual Studio Build Tools, Developer Mode |
| `run_dev.bat` | Chạy bản debug trên Windows; `run_dev.bat android` chạy trên điện thoại đang cắm |
| `check.bat` | Kiểm tra nhanh: analyze + test |
| `build.bat` | Build EXE (Windows) → `releases/` ở gốc dự án. `build.bat -Apk` build thêm APK |
| `build_apk.bat` | Build EXE + APK, bỏ qua test |

| Thư mục | Nội dung |
|---|---|
| `scripts/` | Script PowerShell mà các file `.bat` gọi |
| `installer/` | Cấu hình Inno Setup tạo bộ cài Windows |
| `build_logs/` | Log build (tự giữ 5 bản gần nhất, không commit) |

Mỗi lần build tự tăng số build, ghi `CHANGELOG.md`, và chỉ giữ bản build mới nhất trong `releases/`.
