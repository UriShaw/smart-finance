<#
.SYNOPSIS
  Smart Finance - build 1 lệnh: kiểm tra môi trường -> quality gate -> build .exe
  -> lưu vào releases\<phiên bản>\ (kèm zip, manifest, checksum, changelog).

.EXAMPLE
  build.bat                      # tăng build number (1.0.0+1 -> 1.0.0+2)
  build.bat -Bump patch          # 1.0.0 -> 1.0.1
  build.bat -Bump minor -Notes "Thêm bản đồ"
  build.bat -Apk                 # build thêm APK Android
  build.bat -SkipTests           # bỏ qua test (không khuyến nghị)
  build.bat -Strict              # dừng nếu analyze/test lỗi
#>
[CmdletBinding()]
param(
  [ValidateSet('build', 'patch', 'minor', 'major', 'none')]
  [string]$Bump = 'build',
  [string]$Notes = '',
  [switch]$SkipTests,
  [switch]$Strict,
  [switch]$Apk,
  [switch]$NoZip,
  [switch]$NoOpen,
  [ValidateSet('production', 'staging', 'development')]
  [string]$AppEnv = 'production'
)

# 'Continue' vì flutter/dart ghi thông tin ra stderr; lỗi được kiểm tra qua exit code.
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$started = Get-Date

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Fail($msg) {
  Write-Host "`n[LỖI] $msg" -ForegroundColor Red
  Write-Host "Xem hướng dẫn: docs\BUILD_WINDOWS.md" -ForegroundColor Red
  exit 1
}

# Chạy lệnh ngoài, ghi log, trả về exit code (không ném lỗi).
function Invoke-Logged([string]$exe, [string[]]$argv, [string]$logFile) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $exe @argv 2>&1 | Tee-Object -FilePath $logFile -Append | Out-Host
  $code = $LASTEXITCODE
  $ErrorActionPreference = $old
  return $code
}

$LogDir = Join-Path $Root 'build_logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Log = Join-Path $LogDir "build_$stamp.log"

Write-Host "==============================================" -ForegroundColor Magenta
Write-Host "   SMART FINANCE - BUILD WINDOWS (.exe)" -ForegroundColor Magenta
Write-Host "==============================================" -ForegroundColor Magenta

# ------------------------------------------------------------------ 1. Môi trường
Step "Kiểm tra môi trường"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $candidates = @('C:\src\flutter\bin', "$env:USERPROFILE\flutter\bin", "$env:LOCALAPPDATA\flutter\bin", 'C:\flutter\bin')
  foreach ($c in $candidates) {
    if (Test-Path (Join-Path $c 'flutter.bat')) { $env:Path = "$c;$env:Path"; break }
  }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Fail "Chưa có Flutter SDK. Chạy 'setup.bat' (tự cài Flutter + Visual Studio Build Tools) rồi build lại."
}
$flutterVersion = ((& flutter --version 2>&1 | ForEach-Object { "$_" }) | Select-Object -First 1)
Ok "Flutter: $flutterVersion"

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
  $vs = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
  if ($vs) { Ok "Visual Studio C++: $($vs | Select-Object -First 1)" }
  else { Fail "Thiếu Visual Studio 'Desktop development with C++'. Chạy setup.bat." }
} else {
  Warn "Không tìm thấy vswhere - nếu build lỗi, chạy setup.bat để cài Visual Studio Build Tools."
}

# Plugin Flutter trên Windows cần symlink (Developer Mode).
$devMode = $false
try {
  $v = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction Stop
  $devMode = ($v.AllowDevelopmentWithoutDevLicense -eq 1)
} catch {}
if ($devMode) { Ok "Developer Mode: bật" }
else { Warn "Developer Mode chưa bật (cần cho plugin). Nếu build báo 'symlink support', mở: start ms-settings:developers" }

Invoke-Logged 'flutter' @('config', '--enable-windows-desktop') $Log | Out-Null

# ------------------------------------------------------------------ 2. Nền tảng Windows/Android
Step "Chuẩn bị thư mục nền tảng"
if (-not (Test-Path (Join-Path $Root 'windows\runner'))) {
  Warn "Chưa có thư mục windows\ - tạo bằng flutter create (chỉ thêm file thiếu, không ghi đè lib\)"
  $code = Invoke-Logged 'flutter' @('create', '--platforms=windows,android', '--org', 'io.smartfinance', '--project-name', 'smart_finance', '.') $Log
  if ($code -ne 0) { Fail "flutter create thất bại" }
  $defaultTest = Join-Path $Root 'test\widget_test.dart'
  if ((Test-Path $defaultTest) -and ((Get-Content $defaultTest -Raw) -match 'MyApp')) { Remove-Item $defaultTest -Force }
}
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'patch_platforms.ps1')
if ($LASTEXITCODE -ne 0) { Fail "Patch nền tảng thất bại" }
Ok "Nền tảng sẵn sàng"

# ------------------------------------------------------------------ 3. Phiên bản
Step "Tính phiên bản"
$pubspecPath = Join-Path $Root 'pubspec.yaml'
$pubspec = [IO.File]::ReadAllText($pubspecPath)
$m = [regex]::Match($pubspec, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if (-not $m.Success) { Fail "Không đọc được 'version: x.y.z+n' trong pubspec.yaml" }
$maj = [int]$m.Groups[1].Value; $min = [int]$m.Groups[2].Value
$pat = [int]$m.Groups[3].Value; $num = [int]$m.Groups[4].Value
switch ($Bump) {
  'major' { $maj++; $min = 0; $pat = 0; $num++ }
  'minor' { $min++; $pat = 0; $num++ }
  'patch' { $pat++; $num++ }
  'build' { $num++ }
  'none'  { }
}
$BuildName = "$maj.$min.$pat"
$BuildNumber = $num
$FullVersion = "$BuildName+$BuildNumber"
Ok "Phiên bản mới: $FullVersion"

# ------------------------------------------------------------------ 4. Cấu hình môi trường
Step "Cấu hình ($AppEnv)"
$envFile = Join-Path $Root 'config\env.json'
if (-not (Test-Path $envFile)) {
  Copy-Item (Join-Path $Root 'config\env.example.json') $envFile
  Warn "Tạo config\env.json từ mẫu (chưa có Supabase -> app chạy offline). Điền SUPABASE_URL/ANON_KEY để bật đồng bộ."
}
$envJson = Get-Content $envFile -Raw | ConvertFrom-Json
$cloud = ($envJson.SUPABASE_URL -and $envJson.SUPABASE_ANON_KEY)
if ($cloud) { Ok "Supabase: $($envJson.SUPABASE_URL)" } else { Warn "Supabase chưa cấu hình -> build chế độ offline" }

# ------------------------------------------------------------------ 5. Quét secret
Step "Quét secret (không cho phép service-role key trong app)"
function Test-ServiceRoleJwt([string]$text) {
  foreach ($mm in [regex]::Matches($text, 'eyJ[A-Za-z0-9_-]+\.([A-Za-z0-9_-]+)\.[A-Za-z0-9_-]+')) {
    $p = $mm.Groups[1].Value.Replace('-', '+').Replace('_', '/')
    switch ($p.Length % 4) { 2 { $p += '==' } 3 { $p += '=' } }
    try {
      $payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p))
      if ($payload -match '"role"\s*:\s*"service_role"') { return $true }
    } catch {}
  }
  return $false
}
$scanFiles = @(Get-ChildItem -Path (Join-Path $Root 'lib') -Recurse -Include *.dart) + (Get-Item $envFile)
foreach ($f in $scanFiles) {
  $t = [IO.File]::ReadAllText($f.FullName)
  if ((Test-ServiceRoleJwt $t) -or ($t -match 'sb_secret_[A-Za-z0-9]')) {
    Fail "Phát hiện SERVICE ROLE / secret key trong $($f.FullName). Chỉ dùng anon key trong app!"
  }
}
Ok "Không có secret nguy hiểm"

# ------------------------------------------------------------------ 6. Dependencies
Step "flutter pub get"
if ((Invoke-Logged 'flutter' @('pub', 'get') $Log) -ne 0) { Fail "pub get thất bại (kiểm tra mạng / phiên bản Flutter)" }
Ok "Dependencies OK"

# ------------------------------------------------------------------ 7. Quality gate
Step "Quality gate: format / analyze / test"
$quality = [ordered]@{ format = 'SKIPPED'; analyze = 'SKIPPED'; tests = 'SKIPPED' }

$fmt = Invoke-Logged 'dart' @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test') $Log
$quality.format = $(if ($fmt -eq 0) { 'PASSED' } else { 'NEEDS_FORMAT' })
if ($fmt -ne 0) { Warn "Code chưa format chuẩn (chạy: dart format lib test)" } else { Ok "Format" }

$an = Invoke-Logged 'flutter' @('analyze', '--no-fatal-infos', '--no-fatal-warnings') $Log
$quality.analyze = $(if ($an -eq 0) { 'PASSED' } else { 'FAILED' })
if ($an -ne 0) {
  if ($Strict) { Fail "flutter analyze có lỗi (xem $Log)" }
  Warn "flutter analyze có lỗi - xem log. Vẫn thử build (dùng -Strict để chặn)."
} else { Ok "Analyze" }

if (-not $SkipTests) {
  $tc = Invoke-Logged 'flutter' @('test', '--reporter', 'compact') $Log
  $quality.tests = $(if ($tc -eq 0) { 'PASSED' } else { 'FAILED' })
  if ($tc -ne 0) {
    if ($Strict) { Fail "Unit/widget test thất bại (xem $Log)" }
    Warn "Có test thất bại - xem log. Vẫn build (dùng -Strict để chặn)."
  } else { Ok "Tests" }
} else { Warn "Bỏ qua test (-SkipTests)" }

# ------------------------------------------------------------------ 8. Build
Step "flutter build windows --release"
$defines = @(
  "--dart-define-from-file=config/env.json",
  "--dart-define=APP_VERSION=$FullVersion",
  "--dart-define=APP_ENV=$AppEnv"
)
$buildArgs = @('build', 'windows', '--release', "--build-name=$BuildName", "--build-number=$BuildNumber") + $defines
if ((Invoke-Logged 'flutter' $buildArgs $Log) -ne 0) { Fail "Build Windows thất bại - xem $Log" }

$outDir = @('build\windows\x64\runner\Release', 'build\windows\runner\Release') |
  ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $outDir) { Fail "Không tìm thấy thư mục output build" }
$exe = Get-ChildItem $outDir -Filter *.exe | Select-Object -First 1
if (-not $exe) { Fail "Không thấy file .exe trong $outDir" }
if (-not (Test-Path (Join-Path $outDir 'sqlite3.dll'))) { Warn "Không thấy sqlite3.dll cạnh exe - kiểm tra plugin sqlite3_flutter_libs" }
Ok "Đã build: $($exe.Name)"

# ------------------------------------------------------------------ 9. Lưu phiên bản
Step "Lưu vào thư mục releases"
$relRoot = Join-Path $Root 'releases'
$relName = "v${BuildName}+${BuildNumber}_$(Get-Date -Format 'yyyyMMdd-HHmm')"
$relDir = Join-Path $relRoot $relName
$appDir = Join-Path $relDir 'SmartFinance'
New-Item -ItemType Directory -Force -Path $appDir -ErrorAction Stop | Out-Null
Copy-Item -Path (Join-Path $outDir '*') -Destination $appDir -Recurse -Force -ErrorAction Stop
$exePath = Join-Path $appDir $exe.Name

$zipPath = $null
if (-not $NoZip) {
  $zipPath = Join-Path $relDir "SmartFinance_v${BuildName}+${BuildNumber}_windows_x64.zip"
  Compress-Archive -Path $appDir -DestinationPath $zipPath -Force -ErrorAction Stop
  Ok "Zip: $(Split-Path $zipPath -Leaf)"
}

# Bộ cài 1 file .exe (nếu có Inno Setup)
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
$setupPath = $null
if ($iscc) {
  $issArgs = @("/DAppVersion=$BuildName", "/DBuildNumber=$BuildNumber", "/DSourceDir=$appDir", "/DOutputDir=$relDir", "/DExeName=$($exe.Name)", (Join-Path $Root 'installer\smart_finance.iss'))
  if ((Invoke-Logged $iscc $issArgs $Log) -eq 0) {
    $setupPath = Get-ChildItem $relDir -Filter 'SmartFinance_Setup_*.exe' | Select-Object -First 1 -ExpandProperty FullName
    Ok "Bộ cài: $(Split-Path $setupPath -Leaf)"
  } else { Warn "Inno Setup lỗi - bỏ qua bộ cài" }
} else { Warn "Không có Inno Setup -> bỏ qua bộ cài 1 file (tùy chọn, xem docs\BUILD_WINDOWS.md)" }

# APK (tùy chọn)
$apkPath = $null
if ($Apk) {
  Step "flutter build apk --release"
  $apkArgs = @('build', 'apk', '--release', "--build-name=$BuildName", "--build-number=$BuildNumber") + $defines
  if ((Invoke-Logged 'flutter' $apkArgs $Log) -eq 0) {
    $apkSrc = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
    $apkPath = Join-Path $relDir "SmartFinance_v${BuildName}+${BuildNumber}.apk"
    Copy-Item $apkSrc $apkPath -Force
    Ok "APK: $(Split-Path $apkPath -Leaf)"
  } else { Warn "Build APK thất bại (cần Android SDK) - xem log" }
}

# Manifest + checksum
function Get-Sha256($path) { if ($path -and (Test-Path $path)) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() } else { $null } }
$gitCommit = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
  $gitCommit = (& git rev-parse --short HEAD 2>$null)
}
$manifest = [ordered]@{
  app            = 'Smart Finance'
  version        = $BuildName
  build_number   = $BuildNumber
  full_version   = $FullVersion
  environment    = $AppEnv
  built_at       = (Get-Date).ToString('o')
  built_on       = $env:COMPUTERNAME
  flutter        = $flutterVersion
  git_commit     = $gitCommit
  cloud_sync     = [bool]$cloud
  db_schema      = 1
  migrations     = @(Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter *.sql | Select-Object -ExpandProperty Name)
  quality        = $quality
  files          = [ordered]@{
    exe   = [ordered]@{ path = "SmartFinance/$($exe.Name)"; sha256 = (Get-Sha256 $exePath) }
    zip   = $(if ($zipPath) { [ordered]@{ path = (Split-Path $zipPath -Leaf); sha256 = (Get-Sha256 $zipPath) } } else { $null })
    setup = $(if ($setupPath) { [ordered]@{ path = (Split-Path $setupPath -Leaf); sha256 = (Get-Sha256 $setupPath) } } else { $null })
    apk   = $(if ($apkPath) { [ordered]@{ path = (Split-Path $apkPath -Leaf); sha256 = (Get-Sha256 $apkPath) } } else { $null })
  }
  notes          = $Notes
}
[IO.File]::WriteAllText((Join-Path $relDir 'manifest.json'), ($manifest | ConvertTo-Json -Depth 6), $Utf8NoBom)

$releaseNotes = @"
# Smart Finance $FullVersion

- Ngày build: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
- Môi trường: $AppEnv
- Đồng bộ cloud: $(if ($cloud) { 'bật' } else { 'tắt (offline)' })
- Quality gate: format=$($quality.format), analyze=$($quality.analyze), tests=$($quality.tests)
- Ghi chú: $(if ($Notes) { $Notes } else { '(không có)' })

## Chạy
Mở SmartFinance\$($exe.Name). Giữ nguyên các file .dll và thư mục data\ cạnh file exe.

## Migration
Chạy các file trong supabase\migrations theo thứ tự tên (supabase db push).
Rollback dev: supabase\migrations\rollback\. Production: ưu tiên forward migration.

## Smoke test
1. Mở app -> chọn dùng offline hoặc đăng nhập Google.
2. Thêm 1 giao dịch có ảnh -> thấy ở Tổng quan/Lịch sử/Lịch.
3. Tắt mạng -> thêm giao dịch -> bật mạng -> biểu tượng đồng bộ về "Đã đồng bộ".
"@
[IO.File]::WriteAllText((Join-Path $relDir 'RELEASE_NOTES.md'), $releaseNotes, $Utf8NoBom)

# CHANGELOG.md (thêm lên đầu)
$changelogPath = Join-Path $Root 'CHANGELOG.md'
$entry = "## [$FullVersion] - $(Get-Date -Format 'yyyy-MM-dd')`n- $(if ($Notes) { $Notes } else { 'Build tự động' }) (quality: analyze=$($quality.analyze), tests=$($quality.tests))`n`n"
$old = if (Test-Path $changelogPath) { [IO.File]::ReadAllText($changelogPath) } else { "# Changelog`n`n" }
$idx = $old.IndexOf("## [")
$new = if ($idx -ge 0) { $old.Substring(0, $idx) + $entry + $old.Substring($idx) } else { $old + $entry }
[IO.File]::WriteAllText($changelogPath, $new, $Utf8NoBom)

# releases\latest (bản mới nhất) + index
$latest = Join-Path $relRoot 'latest'
if (Test-Path $latest) { Remove-Item $latest -Recurse -Force }
Copy-Item $relDir $latest -Recurse
$index = "# Các phiên bản Smart Finance`n`n| Phiên bản | Thư mục | Ngày | Quality |`n|---|---|---|---|`n"
# Sắp theo số build (không theo tên: "+9" > "+16" khi so chữ).
Get-ChildItem $relRoot -Directory | Where-Object { $_.Name -ne 'latest' } | ForEach-Object {
  $mf = Join-Path $_.FullName 'manifest.json'
  if (Test-Path $mf) { [pscustomobject]@{ Dir = $_.Name; J = (Get-Content $mf -Raw | ConvertFrom-Json) } }
} | Sort-Object { [int]$_.J.build_number }, { [string]$_.J.built_at } -Descending | ForEach-Object {
  $j = $_.J
  $index += "| $($j.full_version) | $($_.Dir) | $(([datetime]$j.built_at).ToString('yyyy-MM-dd')) | analyze=$($j.quality.analyze), tests=$($j.quality.tests) |`n"
}
[IO.File]::WriteAllText((Join-Path $relRoot 'README.md'), $index, $Utf8NoBom)

# Ghi version mới vào pubspec (chỉ sau khi build thành công)
$pubspec = [regex]::Replace($pubspec, '(?m)^version:\s*\S+', "version: $FullVersion")
[IO.File]::WriteAllText($pubspecPath, $pubspec, $Utf8NoBom)

$elapsed = [int]((Get-Date) - $started).TotalSeconds
Write-Host "`n==============================================" -ForegroundColor Green
Write-Host " XONG! Smart Finance $FullVersion  (${elapsed}s)" -ForegroundColor Green
Write-Host " EXE    : $exePath" -ForegroundColor Green
if ($zipPath) { Write-Host " ZIP    : $zipPath" -ForegroundColor Green }
if ($setupPath) { Write-Host " SETUP  : $setupPath" -ForegroundColor Green }
if ($apkPath) { Write-Host " APK    : $apkPath" -ForegroundColor Green }
Write-Host " Mới nhất: $latest" -ForegroundColor Green
Write-Host " Log    : $Log" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green

if (-not $NoOpen) { Start-Process explorer.exe $relDir }
exit 0
