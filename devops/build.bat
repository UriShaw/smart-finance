@echo off
REM ============================================================
REM  Smart Finance - BUILD 1 LENH
REM  Tao file .exe va luu vao thu muc releases\<phien ban>\
REM  Vi du:  build.bat            (tang build number)
REM          build.bat -Bump patch -Notes "Sua loi dong bo"
REM          build.bat -Apk        (them APK Android)
REM ============================================================
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build.ps1" %*
set ERR=%ERRORLEVEL%
if not "%ERR%"=="0" (
  echo.
  echo Build THAT BAI (ma loi %ERR%). Xem thu muc devops\build_logs\
)
pause
exit /b %ERR%
