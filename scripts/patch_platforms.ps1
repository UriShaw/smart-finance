# Vá các file nền tảng do `flutter create` sinh ra (idempotent - chạy nhiều lần không sao).
# - Windows: tên exe "SmartFinance.exe", tiêu đề cửa sổ, thông tin phiên bản.
# - Android: quyền Internet, deep link đăng nhập Google (io.smartfinance.app://login-callback).
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Edit-File([string]$path, [scriptblock]$transform) {
  if (-not (Test-Path $path)) { return }
  $old = [IO.File]::ReadAllText($path)
  $new = & $transform $old
  if ($new -ne $old) {
    [IO.File]::WriteAllText($path, $new, $Utf8NoBom)
    Write-Host "    patched: $path"
  }
}

# ---------------------------------------------------------------- Windows
Edit-File (Join-Path $Root 'windows\CMakeLists.txt') {
  param($s)
  $s -replace 'set\(BINARY_NAME "[^"]*"\)', 'set(BINARY_NAME "SmartFinance")'
}
Edit-File (Join-Path $Root 'windows\runner\main.cpp') {
  param($s)
  $s -replace 'window\.Create\(L"[^"]*"', 'window.Create(L"Smart Finance"'
}
Edit-File (Join-Path $Root 'windows\runner\Runner.rc') {
  param($s)
  $s = $s -replace 'VALUE "FileDescription", "[^"]*"', 'VALUE "FileDescription", "Smart Finance"'
  $s = $s -replace 'VALUE "ProductName", "[^"]*"', 'VALUE "ProductName", "Smart Finance"'
  $s = $s -replace 'VALUE "InternalName", "[^"]*"', 'VALUE "InternalName", "SmartFinance"'
  $s = $s -replace 'VALUE "OriginalFilename", "[^"]*"', 'VALUE "OriginalFilename", "SmartFinance.exe"'
  $s = $s -replace 'VALUE "CompanyName", "[^"]*"', 'VALUE "CompanyName", "Smart Finance"'
  $s
}

# ---------------------------------------------------------------- Android
Edit-File (Join-Path $Root 'android\app\src\main\AndroidManifest.xml') {
  param($s)
  if ($s -notmatch 'android.permission.INTERNET') {
    $s = $s -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.INTERNET`"/>`n    <uses-permission android:name=`"android.permission.ACCESS_NETWORK_STATE`"/>"
  }
  $s = $s -replace 'android:label="smart_finance"', 'android:label="Smart Finance"'
  if ($s -notmatch 'io\.smartfinance\.app') {
    $filter = @"
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="io.smartfinance.app" android:host="login-callback" />
            </intent-filter>
        </activity>
"@
    $idx = $s.IndexOf('</activity>')
    if ($idx -ge 0) { $s = $s.Substring(0, $idx) + $filter.TrimStart() + $s.Substring($idx + '</activity>'.Length) }
  }
  $s
}

# ---------------------------------------------------------------- Android: đọc thông báo ngân hàng
# Mã nguồn native nằm ở native\android (nông, dễ sửa) -> chép vào đúng thư mục Android.
$appMain = Join-Path $Root 'android\app\src\main'
$nativeDir = Join-Path $Root 'native\android'
if ((Test-Path $appMain) -and (Test-Path $nativeDir)) {
  $javaDir = Join-Path $appMain 'java\io\smartfinance\smart_finance'
  New-Item -ItemType Directory -Force -Path $javaDir | Out-Null
  Get-ChildItem $nativeDir -Filter *.java | ForEach-Object {
    $dest = Join-Path $javaDir $_.Name
    $srcText = [IO.File]::ReadAllText($_.FullName)
    $destText = if (Test-Path $dest) { [IO.File]::ReadAllText($dest) } else { '' }
    if ($srcText -ne $destText) {
      [IO.File]::WriteAllText($dest, $srcText, $Utf8NoBom)
      Write-Host "    synced: $($_.Name)"
    }
  }

  # Âm báo "ting ting" (res\raw) dùng cho âm báo khi có tiền về.
  $rawSrc = Join-Path $nativeDir 'res\raw'
  if (Test-Path $rawSrc) {
    $rawDest = Join-Path $appMain 'res\raw'
    New-Item -ItemType Directory -Force -Path $rawDest | Out-Null
    Get-ChildItem $rawSrc -File | ForEach-Object {
      $dest = Join-Path $rawDest $_.Name
      if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $_.Length) {
        Copy-Item $_.FullName $dest -Force
        Write-Host "    synced: res\raw\$($_.Name)"
      }
    }
  }

  # MainActivity: giữ nguyên package hiện có, chỉ thay nội dung để đăng ký kênh BankChannel.
  $mainKt = Get-ChildItem (Join-Path $appMain 'kotlin') -Recurse -Filter 'MainActivity.kt' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($mainKt) {
    $cur = [IO.File]::ReadAllText($mainKt.FullName)
    if ($cur -notmatch 'BankChannel') {
      $pkgLine = ([regex]::Match($cur, '(?m)^package\s+[\w.]+')).Value
      if (-not $pkgLine) { $pkgLine = 'package io.smartfinance.smart_finance' }
      $body = [IO.File]::ReadAllText((Join-Path $nativeDir 'MainActivity.kt'))
      $body = [regex]::Replace($body, '(?m)^package\s+[\w.]+', $pkgLine)
      if ($pkgLine -ne 'package io.smartfinance.smart_finance') {
        $body = $body -replace '(import io\.flutter\.embedding\.android\.FlutterActivity)', "import io.smartfinance.smart_finance.BankChannel`n`$1"
      }
      [IO.File]::WriteAllText($mainKt.FullName, $body, $Utf8NoBom)
      Write-Host "    patched: MainActivity.kt"
    }
  }
}

Edit-File (Join-Path $Root 'android\app\src\main\AndroidManifest.xml') {
  param($s)
  if ($s -notmatch 'RECEIVE_BOOT_COMPLETED') {
    $s = $s -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.RECEIVE_BOOT_COMPLETED`"/>"
  }
  if ($s -notmatch 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS') {
    $s = $s -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`"/>"
  }
  if ($s -notmatch 'ACCESS_FINE_LOCATION') {
    $s = $s -replace '(<manifest[^>]*>)', "`$1`n    <uses-permission android:name=`"android.permission.ACCESS_FINE_LOCATION`"/>`n    <uses-permission android:name=`"android.permission.ACCESS_COARSE_LOCATION`"/>"
  }
  if ($s -notmatch 'BankNotificationListener') {
    $block = @"
        <!-- Đọc thông báo biến động số dư ngân hàng (người dùng tự cấp quyền) -->
        <service
            android:name="io.smartfinance.smart_finance.BankNotificationListener"
            android:label="Smart Finance - Ghi giao dịch ngân hàng"
            android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.service.notification.NotificationListenerService" />
            </intent-filter>
        </service>
        <receiver
            android:name="io.smartfinance.smart_finance.BootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
    </application>
"@
    $idx = $s.LastIndexOf('</application>')
    if ($idx -ge 0) { $s = $s.Substring(0, $idx) + $block.TrimStart() + $s.Substring($idx + '</application>'.Length) }
  }
  if ($s -notmatch 'com\.google\.android\.geo\.API_KEY') {
    # Google Maps: build.gradle.kts điền MAPS_API_KEY từ GOOGLE_MAPS_API_KEY (config\env.json).
    $maps = "`n        <meta-data android:name=`"com.google.android.geo.API_KEY`" android:value=`"`${MAPS_API_KEY}`"/>"
    $m = [regex]::Match($s, '<application[^>]*>')
    if ($m.Success) { $s = $s.Insert($m.Index + $m.Length, $maps) }
  }
  if ($s -notmatch 'TTS_SERVICE') {
    $tts = "        <intent>`n            <action android:name=`"android.intent.action.TTS_SERVICE`" />`n        </intent>`n    </queries>"
    if ($s -match '</queries>') {
      $s = $s.Replace('</queries>', $tts)
    } else {
      $s = $s.Replace('</manifest>', "    <queries>`n$tts`n</manifest>")
    }
  }
  $s
}
exit 0
