<#
  Kiểm tra nhanh (không build): flutter analyze + flutter test -> devops\build_logs\check_<thời gian>.log
  Nhanh hơn build.bat khi chỉ muốn biết code có lỗi không.
#>
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
# devops\scripts -> gốc repo; app Flutter nằm trong frontend\
$Repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Root = Join-Path $Repo 'frontend'
Set-Location $Root
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  foreach ($c in @('C:\src\flutter\bin', "$env:USERPROFILE\flutter\bin", "$env:LOCALAPPDATA\flutter\bin", 'C:\flutter\bin')) {
    if (Test-Path (Join-Path $c 'flutter.bat')) { $env:Path = "$c;$env:Path"; break }
  }
}
$LogDir = Join-Path $Repo 'devops\build_logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir ("check_" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".log")
function Run([string[]]$argv) {
  "`n==> flutter $($argv -join ' ')" | Add-Content -Path $Log -Encoding utf8
  & flutter @argv 2>&1 | ForEach-Object { $line = "$_"; Add-Content -Path $Log -Value $line -Encoding utf8; Write-Host $line }
  return $LASTEXITCODE
}
$null = Run @('pub', 'get')
$a = Run @('analyze', '--no-fatal-infos')
$t = Run @('test', '--reporter', 'expanded')
$summary = "`n==> KET QUA: analyze=$a tests=$t"
$summary | Add-Content -Path $Log -Encoding utf8
Write-Host $summary
exit ([int]($a -ne 0 -or $t -ne 0))
