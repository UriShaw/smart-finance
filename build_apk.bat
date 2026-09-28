@echo off
REM Build ca exe + APK, bo qua test (nhap dup chuot la chay)
call "%~dp0build.bat" -Apk -SkipTests %*
