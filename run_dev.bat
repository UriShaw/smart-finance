@echo off
REM Chay ban debug (hot reload) tren Windows.
chcp 65001 >nul
cd /d "%~dp0"
if not exist config\env.json copy config\env.example.json config\env.json >nul
if not exist windows\runner (
  flutter create --platforms=windows,android --org io.smartfinance --project-name smart_finance .
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\patch_platforms.ps1"
flutter pub get
REM Chay tren dien thoai Android: run_dev.bat android
if /I "%1"=="android" (
  flutter run --dart-define-from-file=config/env.json --dart-define=APP_ENV=development
  exit /b
)
flutter run -d windows --dart-define-from-file=config/env.json --dart-define=APP_ENV=development
