@echo off
REM Cai moi truong build (chay 1 lan): Git, Visual Studio Build Tools C++, Flutter, Developer Mode.
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup_windows.ps1" %*
pause
