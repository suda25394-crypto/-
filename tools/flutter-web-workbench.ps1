param(
    [int]$Port = 5181,
    [string]$FlutterSdk = 'D:\tools\couple-flutter\flutter',
    [int]$Width = 390,
    [int]$Height = 844,
    [switch]$LayoutOnly
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'apps\android'
$homeFile = Join-Path $app 'lib\src\ui\home.dart'
$node = (Get-Command node.exe -ErrorAction Stop).Source

function Find-FlutterChrome {
    $processes = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
        Where-Object { $_.CommandLine -match 'flutter_tools_chrome_device' -and $_.CommandLine -notmatch '--type=' }
    foreach ($process in $processes) {
        if ($process.CommandLine -match '--remote-debugging-port=(\d+)') {
            $debugPort = [int]$Matches[1]
            try {
                $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$debugPort/json/list" -TimeoutSec 1
                if ($targets | Where-Object { $_.url -like "http://127.0.0.1:$Port/*" }) {
                    return @{ Pid = $process.ProcessId; Port = $debugPort }
                }
            } catch { }
        }
    }
}

function Arrange-FlutterWindows($target) {
    if (!(Get-Command agent-desktop.cmd -ErrorAction SilentlyContinue)) { return }
    $screen = (agent-desktop.cmd list-displays | ConvertFrom-Json).data |
        Where-Object is_primary | Select-Object -First 1
    if (!$screen) { return }
    $windows = (agent-desktop.cmd list-windows | ConvertFrom-Json).data
    $browser = $windows | Where-Object { $_.pid -eq $target.Pid -and $_.visible } | Select-Object -First 1
    $editor = $windows | Where-Object { $_.app_name -eq 'Code.exe' -and $_.title -like "*$(Split-Path -Leaf $repo)*" } |
        Select-Object -First 1
    $terminal = $windows | Where-Object { $_.title -eq 'Flutter Web Debug' } | Select-Object -First 1
    $margin = 18
    $x = [int]$screen.bounds.x + $margin
    $y = [int]$screen.bounds.y + $margin
    $available = [int]$screen.bounds.height - 115
    $browserWidth = [int][Math]::Min($screen.bounds.width * 0.46, ($Width + 53) * $screen.scale)
    $editorWidth = [int]$screen.bounds.width - $browserWidth - 3 * $margin
    $terminalHeight = if ($terminal) { [int][Math]::Min(340, $available * 0.27) } else { 0 }
    $editorHeight = $available - $terminalHeight
    if ($browser) {
        agent-desktop.cmd restore --window-id $browser.id | Out-Null
        agent-desktop.cmd resize-window --window-id $browser.id --width $browserWidth --height $available | Out-Null
        agent-desktop.cmd move-window --window-id $browser.id --x ($x + $editorWidth + $margin) --y $y | Out-Null
    }
    if ($editor) {
        if ($editor.minimized) { agent-desktop.cmd restore --window-id $editor.id | Out-Null }
        agent-desktop.cmd resize-window --window-id $editor.id --width $editorWidth --height $editorHeight | Out-Null
        agent-desktop.cmd move-window --window-id $editor.id --x $x --y $y | Out-Null
    }
    if ($terminal) {
        agent-desktop.cmd resize-window --window-id $terminal.id --width $editorWidth --height $terminalHeight | Out-Null
        agent-desktop.cmd move-window --window-id $terminal.id --x $x --y ($y + $editorHeight) | Out-Null
    }
}

if ($LayoutOnly) {
    $deadline = (Get-Date).AddMinutes(2)
    do {
        $target = Find-FlutterChrome
        if ($target) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    if (!$target) { throw 'Flutter Chrome did not open on the requested port.' }
    Arrange-FlutterWindows $target
    & $node (Join-Path $PSScriptRoot 'flutter-phone-preview.mjs') $target.Port $Port $Width $Height
    exit $LASTEXITCODE
}

$bin = Join-Path $FlutterSdk 'bin'
if (!(Test-Path -LiteralPath (Join-Path $bin 'flutter.bat'))) { throw 'Point -FlutterSdk to the installed Flutter SDK.' }
$env:Path = "$bin;$env:Path"
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
$Host.UI.RawUI.WindowTitle = 'Flutter Web Debug'

$code = Get-Command code.cmd -ErrorAction SilentlyContinue
if ($code) { & $code.Source $repo --goto "${homeFile}:27:1" }

$existing = Find-FlutterChrome
if ($existing) {
    Arrange-FlutterWindows $existing
    Write-Host "Flutter is already running at http://127.0.0.1:$Port/"
    exit 0
}

Start-Process -FilePath 'powershell.exe' -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath),
    '-LayoutOnly', '-Port', $Port, '-Width', $Width, '-Height', $Height
) -WindowStyle Hidden

& $node (Join-Path $PSScriptRoot 'flutter-web-run.mjs') $app $Port
exit $LASTEXITCODE
