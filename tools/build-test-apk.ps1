param(
  [string]$AndroidSdk = $env:ANDROID_HOME,
  [string]$FlutterSdk
)
$ErrorActionPreference = 'Stop'
$app = Join-Path (Split-Path -Parent $PSScriptRoot) 'apps/android'
if (!$FlutterSdk) {
  $FlutterSdk = Split-Path -Parent (Split-Path -Parent (Get-Command flutter.bat -ErrorAction Stop).Source)
}
$local = Join-Path $app 'android/local.properties'
$lines = if (Test-Path -LiteralPath $local) { @(Get-Content -LiteralPath $local) } else { @() }
if (!$AndroidSdk -and !($lines -match '^sdk\.dir=')) { throw 'Set ANDROID_HOME to your Android SDK.' }
$version = Select-String -LiteralPath (Join-Path $app 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)\+([0-9]+)\s*$'
if (!$version) { throw 'Expected a versionName+versionCode in pubspec.yaml.' }
$props = [ordered]@{
  'flutter.sdk' = ($FlutterSdk -replace '\\','/');
  'flutter.buildMode'='debug';
  'flutter.versionName'=$version.Matches[0].Groups[1].Value;
  'flutter.versionCode'=$version.Matches[0].Groups[2].Value;
}
if ($AndroidSdk) { $props['sdk.dir'] = ($AndroidSdk -replace '\\','/') }
foreach ($key in $props.Keys) {
  $pattern = '^' + [regex]::Escape($key) + '='
  $lines = @($lines | Where-Object { $_ -notmatch $pattern }) + ($key + '=' + $props[$key])
}
[IO.File]::WriteAllLines($local,$lines,[Text.UTF8Encoding]::new($false))
Push-Location $app
try {
  & (Join-Path $FlutterSdk 'bin/flutter.bat') pub get --enforce-lockfile
  if ($LASTEXITCODE) { throw 'Flutter dependency restore failed' }
  & (Join-Path $app 'android/gradlew.bat') -p android ':app:assembleDebug' '-Ptarget-platform=android-arm,android-arm64,android-x64' '--console=plain'
  if ($LASTEXITCODE) { throw 'Android debug application build failed' }
  Get-FileHash (Join-Path $app 'build/app/outputs/flutter-apk/app-debug.apk') -Algorithm SHA256
} finally { Pop-Location }
