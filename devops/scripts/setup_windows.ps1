<#
.SYNOPSIS
  Cài môi trường build Smart Finance trên Windows 10/11 (chạy 1 lần):
  Git, Visual Studio 2022 Build Tools (C++), Flutter SDK (stable), bật Developer Mode.
  Dùng winget (có sẵn trên Windows 10 21H2+/11).
#>
param([string]$FlutterDir = 'C:\src\flutter')

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    [OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if (-not $hasWinget) { Warn "Không có winget. Cài 'App Installer' từ Microsoft Store rồi chạy lại, hoặc cài thủ công theo docs\BUILD_WINDOWS.md" }

# ---------------------------------------------------------------- Git
Step "Git"
if (Get-Command git -ErrorAction SilentlyContinue) { Ok (git --version) }
elseif ($hasWinget) {
  winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
  $env:Path += ";$env:ProgramFiles\Git\cmd"
}

# ---------------------------------------------------------------- Visual Studio Build Tools
Step "Visual Studio 2022 Build Tools (Desktop development with C++)"
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$hasVc = $false
if (Test-Path $vswhere) {
  $hasVc = [bool](& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
}
if ($hasVc) { Ok "Đã có C++ toolchain" }
elseif ($hasWinget) {
  Write-Host "    Đang cài (~3-6 GB, có thể mất 10-30 phút)..."
  winget install --id Microsoft.VisualStudio.2022.BuildTools -e --accept-source-agreements --accept-package-agreements `
    --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended"
} else { Warn "Cài thủ công: https://visualstudio.microsoft.com/downloads/ -> Build Tools -> 'Desktop development with C++'" }

# ---------------------------------------------------------------- Flutter
Step "Flutter SDK (stable)"
if (Get-Command flutter -ErrorAction SilentlyContinue) { Ok "Đã có Flutter trong PATH" }
elseif (Test-Path (Join-Path $FlutterDir 'bin\flutter.bat')) { Ok "Đã có Flutter tại $FlutterDir" }
else {
  try {
    $base = 'https://storage.googleapis.com/flutter_infra_release/releases'
    $rel = Invoke-RestMethod "$base/releases_windows.json"
    $hash = $rel.current_release.stable
    $archive = ($rel.releases | Where-Object { $_.hash -eq $hash } | Select-Object -First 1).archive
    $zip = Join-Path $env:TEMP 'flutter_stable.zip'
    Write-Host "    Tải $archive ..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest "$base/$archive" -OutFile $zip
    $parent = Split-Path -Parent $FlutterDir
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Host "    Giải nén vào $parent ..."
    Expand-Archive $zip -DestinationPath $parent -Force
    Remove-Item $zip -Force
    Ok "Flutter đã cài tại $FlutterDir"
  } catch {
    Warn "Tải Flutter thất bại: $($_.Exception.Message). Dự phòng: git clone https://github.com/flutter/flutter.git -b stable $FlutterDir"
    if (Get-Command git -ErrorAction SilentlyContinue) { git clone https://github.com/flutter/flutter.git -b stable $FlutterDir }
  }
}
$bin = Join-Path $FlutterDir 'bin'
if (Test-Path $bin) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$bin*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$bin", 'User')
    Ok "Đã thêm $bin vào PATH (mở cửa sổ mới để có hiệu lực)"
  }
  $env:Path = "$bin;$env:Path"
}

# ---------------------------------------------------------------- Developer Mode (symlink cho plugin)
Step "Developer Mode"
$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$enabled = $false
try { $enabled = ((Get-ItemProperty $key -Name AllowDevelopmentWithoutDevLicense -ErrorAction Stop).AllowDevelopmentWithoutDevLicense -eq 1) } catch {}
if ($enabled) { Ok "Đã bật" }
elseif ($isAdmin) {
  New-Item -Path $key -Force | Out-Null
  Set-ItemProperty -Path $key -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
  Ok "Đã bật Developer Mode"
} else {
  Warn "Cần bật Developer Mode: đang mở Settings > For developers ..."
  Start-Process 'ms-settings:developers'
}

# ---------------------------------------------------------------- Kiểm tra
Step "flutter doctor"
if (Get-Command flutter -ErrorAction SilentlyContinue) {
  flutter config --enable-windows-desktop
  flutter doctor
  Write-Host "`nXONG. Giờ chạy: build.bat" -ForegroundColor Green
} else {
  Warn "Chưa tìm thấy flutter. Mở cửa sổ mới rồi chạy lại setup.bat"
}
