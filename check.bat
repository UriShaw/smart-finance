@echo off
REM Kiem tra nhanh: analyze + test (khong build). Log: build_logs\check_*.log
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\check.ps1"
exit /b %ERRORLEVEL%
