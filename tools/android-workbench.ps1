param(
    [string]$FlutterSdk = 'D:\tools\couple-flutter\flutter',
    [string]$AndroidSdk = 'D:\tools\android-sdk',
    [string]$Jdk = 'D:\tools\jdk21\jdk-21.0.12.1+1',
    [string]$Avd = 'Couple_Pixel_7_API_33',
    [switch]$LayoutOnly,
    [switch]$SkipLayout
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'apps\android'
$homeFile = Join-Path $app 'lib\src\ui\home.dart'
$runtime = Join-Path $app '.dart_tool\android-workbench'
$runner = Join-Path $PSScriptRoot 'flutter-android-run.mjs'
$adb = Join-Path $AndroidSdk 'platform-tools\adb.exe'
$emulator = Join-Path $AndroidSdk 'emulator\emulator.exe'
$desktop = (Get-Command agent-desktop.cmd -ErrorAction Stop).Source
$repoName = Split-Path -Leaf $repo

function Read-Desktop([string[]]$Arguments) {
    $result = (& $desktop @Arguments | Out-String) | ConvertFrom-Json
    if (!$result.ok) { throw "Window operation failed: $($result.error.message)" }
    $result.data
}

function Project-Editor($windows) {
    $windows | Where-Object {
        $_.app_name -eq 'Code.exe' -and $_.title -like "* - $repoName - Visual Studio Code*"
    } | Select-Object -First 1
}

function Project-EmulatorWindow($windows) {
    $windows | Where-Object {
        $_.app_name -like 'qemu-system-*' -and $_.title -like "Android Emulator - ${Avd}:*"
    } | Select-Object -First 1
}

function Set-WorkbenchLayout {
    $until = (Get-Date).AddSeconds(25)
    do {
        $wins = Read-Desktop @('list-windows')
        $phone = Project-EmulatorWindow $wins
        $editor = Project-Editor $wins
        if ($phone -and $editor) { break }
        Start-Sleep -Milliseconds 600
    } while ((Get-Date) -lt $until)
    if (!$phone -or !$editor) { throw 'Waiting for this AVD and its VS Code project window timed out.' }
    $display = Read-Desktop @('list-displays') | Where-Object is_primary | Select-Object -First 1
    $bounds = $display.bounds
    foreach ($w in @($phone, $editor)) {
        if ($w.minimized) { Read-Desktop @('restore', '--window-id', $w.id) | Out-Null }
    }
    # Reserve room for the emulator's separate toolbar, display frame and taskbar.
    $gap = [int](12 * $display.scale)
    $height = [int]$bounds.height - [int](60 * $display.scale) - $gap
    $leftWidth = [int]($bounds.width * 0.313)
    $toolsWidth = [int](56 * $display.scale)
    $phoneHeight = [int][Math]::Min($height, ($leftWidth - $toolsWidth - 2 * $gap) * 2.22)
    $phoneWidth = [int]($phoneHeight / 2.22)
    $phoneX = [int]$bounds.x + [Math]::Max($gap, [int](($leftWidth - $phoneWidth - $toolsWidth) / 2))
    $phoneY = [int]$bounds.y + $gap + [int](($height - $phoneHeight) / 2)
    $editorX = [int]$bounds.x + $leftWidth
    $editorWidth = [int]$bounds.width - $leftWidth - $gap
    Read-Desktop @('resize-window', '--window-id', $phone.id, '--width', $phoneWidth, '--height', $phoneHeight) | Out-Null
    Read-Desktop @('move-window', '--window-id', $phone.id, '--x', $phoneX, '--y', $phoneY) | Out-Null
    Read-Desktop @('resize-window', '--window-id', $editor.id, '--width', $editorWidth, '--height', $height) | Out-Null
    Read-Desktop @('move-window', '--window-id', $editor.id, '--x', $editorX, '--y', ([int]$bounds.y + $gap)) | Out-Null
    # A position-only move can leave both windows covered by Explorer after a
    # double-click. Raise just these two handles without changing keyboard focus.
    if (!('CoupleWorkbenchWindows' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class CoupleWorkbenchWindows {
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr w, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong(IntPtr w, int index);
    public static bool Present(long handle) {
        IntPtr window = new IntPtr(handle);
        const uint still = 0x13; // NOSIZE | NOMOVE | NOACTIVATE
        bool wasPinned = (GetWindowLong(window, -20) & 0x8) != 0;
        if (!SetWindowPos(window, new IntPtr(-1), 0, 0, 0, 0, still)) return false;
        return wasPinned || SetWindowPos(window, new IntPtr(-2), 0, 0, 0, 0, still);
    }
}
"@
    }
    foreach ($win in @($editor, $phone)) {
        if ($win.id -match '^w-(\d+)$') {
            [CoupleWorkbenchWindows]::Present([long]$Matches[1]) | Out-Null
        }
    }
}

function Get-ProjectSerial {
    foreach ($line in (& $adb devices)) {
        if ($line -match '^(emulator-\d+)\s+device\b') {
            $serial = $Matches[1]
            if ((& $adb -s $serial emu avd name | Select-Object -First 1) -eq $Avd) { return $serial }
        }
    }
}

function Get-AndroidWorker([string]$Device) {
    # Start-Process on Windows PowerShell 5.1 may append trailing whitespace.
    # Match whole arguments even with quoted or differently cased paths.
    $argPattern = '(?:^|\s)"?' + [regex]::Escape($runner) + '"?\s+"?' +
        [regex]::Escape($app) + '"?\s+"?' + [regex]::Escape($Device) + '"?\s*$'
    $candidates = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.Replace('/', '\') -match $argPattern
    })
    if (!$candidates.Count) { return }
    $stateFile = Join-Path $runtime 'status.json'
    if (Test-Path -LiteralPath $stateFile) {
        try {
            $state = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
            if ($state.device -eq $Device -and $state.phase -in @('starting', 'ready', 'reloading')) {
                $recorded = $candidates | Where-Object { $_.ProcessId -eq $state.pid } | Select-Object -First 1
                if ($recorded) { return $recorded }
            }
        } catch {
            # The process list also covers a fresh worker before its first status write.
        }
    }
    return ($candidates | Sort-Object CreationDate -Descending | Select-Object -First 1)
}

if ($LayoutOnly) { Set-WorkbenchLayout; exit 0 }

New-Item -ItemType Directory -Force -Path $runtime | Out-Null
$launchLog = Join-Path $runtime 'launcher.log'
function Report([string]$Line) {
    Add-Content -LiteralPath $launchLog -Value ("{0:o} {1}" -f (Get-Date), $Line)
    Write-Host $Line
}

# Serialize concurrent double-clicks until the persistent Node worker exists.
$hasher = [System.Security.Cryptography.SHA256]::Create()
$key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($repo.ToLowerInvariant()))).Replace('-', '')
$hasher.Dispose()
$mutex = New-Object System.Threading.Mutex($false, "Local\CoupleFlutterWorkbench-$key")
$locked = $false
try {
    try { $locked = $mutex.WaitOne([TimeSpan]::FromMinutes(4)) }
    catch [System.Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'Another Android workbench launch is still starting.' }
    foreach ($path in @($adb, $emulator, $homeFile, $runner, (Join-Path $FlutterSdk 'bin\flutter.bat'), (Join-Path $Jdk 'bin\java.exe'))) {
        if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing $path" }
    }
    $env:ANDROID_HOME = $AndroidSdk
    $env:ANDROID_SDK_ROOT = $AndroidSdk
    $env:JAVA_HOME = $Jdk
    $env:Path = "$(Join-Path $FlutterSdk 'bin');$(Join-Path $AndroidSdk 'platform-tools');$(Join-Path $Jdk 'bin');$env:Path"
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
    $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
    $windows = Read-Desktop @('list-windows')
    $serial = Get-ProjectSerial
    if (!$serial -and !(Project-EmulatorWindow $windows)) {
        if ((& $emulator -list-avds) -notcontains $Avd) { throw "Missing AVD: $Avd" }
        $booting = Get-CimInstance Win32_Process -Filter "Name='qemu-system-x86_64.exe' OR Name='emulator.exe'" |
            Where-Object { $_.CommandLine -match ('(?:^|\s)-avd\s+"?' + [Regex]::Escape($Avd) + '"?(?:\s|$)') }
        if (!$booting) {
            Start-Process -FilePath $emulator -ArgumentList @('-avd', $Avd, '-memory', '2048', '-gpu', 'auto', '-no-metrics') -WindowStyle Normal
        }
    }
    $editor = Project-Editor $windows
    if (!$editor -or $editor.title -notlike 'home.dart -*') {
        $code = (Get-Command code.cmd -ErrorAction Stop).Source
        & $code $repo --goto "${homeFile}:44:1"
    }

    $deadline = (Get-Date).AddMinutes(3)
    do {
        $serial = Get-ProjectSerial
        if ($serial -and ((& $adb -s $serial shell getprop sys.boot_completed) -join '').Trim() -eq '1') { break }
        if ((Get-Date) -ge $deadline) { throw "Android emulator '$Avd' did not boot within three minutes." }
        Start-Sleep -Seconds 2
    } while ($true)

    $worker = Get-AndroidWorker $serial
    if (!$worker) {
        $node = (Get-Command node.exe -ErrorAction Stop).Source
        $worker = Start-Process -FilePath $node -ArgumentList @(('"{0}"' -f $runner), ('"{0}"' -f $app), $serial) -WorkingDirectory $app -WindowStyle Hidden -PassThru
        Report "Started Android debug worker $($worker.Id) for $serial. Saving a Dart source reloads the app."
    } else {
        Report "Reusing debug worker $($worker.ProcessId) for $serial."
    }
    if (!$SkipLayout) { Set-WorkbenchLayout }
} catch {
    Report $_.Exception.Message
    throw
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
