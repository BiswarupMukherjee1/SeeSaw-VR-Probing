<#
  Build the APK and install it on the Quest 3 over USB (adb).
    .\deploy_quest.ps1 -ServerIp 192.168.1.50          # build + install + launch
    .\deploy_quest.ps1 -ServerIp 192.168.1.50 -SkipBuild   # only write the IP, install the last APK
  Needs: Quest in developer mode, USB cable, "Allow USB debugging" accepted inside the headset,
         Godot 4.7.2 export templates + Android SDK + JDK 17 set in Godot's editor settings.
  Everything this script caches goes to <project>\.cache and <project>\.tmp (never C:).
#>
param(
    [Parameter(Mandatory = $true)][string]$ServerIp,
    [int]$Port = 8765,
    [string]$Godot = "C:\Users\biswa\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
    [switch]$SkipBuild,
    [switch]$NoLaunch
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$proj = Join-Path $root "godot"
$apk = Join-Path $root "build\seesaw_xr.apk"
$package = "com.seesaw.xr"
if ((Split-Path -Qualifier $root) -eq "C:") { throw "Project is on C:. Move it to D: first." }

# --- keep caches off C:
$cache = Join-Path $root ".cache"; $tmp = Join-Path $root ".tmp"
New-Item -ItemType Directory -Force "$cache\gradle", $tmp, (Split-Path $apk) | Out-Null
$env:TEMP = $tmp; $env:TMP = $tmp
$env:GRADLE_USER_HOME = "$cache\gradle"
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
$jdk17 = "$env:LOCALAPPDATA\Programs\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
if (Test-Path $jdk17) { $env:JAVA_HOME = $jdk17; $env:PATH = "$jdk17\bin;$env:PATH" }
$cFree = [math]::Round((Get-PSDrive C).Free / 1MB)
Write-Host "C: free: $cFree MB"
if ($cFree -lt 300) { throw "C: has under 300 MB free. Free some space first, Android tools still write small files there." }

# --- 1. tell the app where the sidecar is
$json = "{`n`t`"host`": `"$ServerIp`",`n`t`"port`": $Port`n}`n"
[System.IO.File]::WriteAllText("$proj\config\server.json", $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "server.json -> $ServerIp`:$Port"

if (-not $SkipBuild) {
    # --- 2. Android build template (same as Project > Install Android Build Template)
    if (-not (Test-Path "$proj\android\build\build.gradle")) {
        $zip = "$env:APPDATA\Godot\export_templates\4.7.2.stable\android_source.zip"
        if (-not (Test-Path $zip)) { throw "Export templates 4.7.2.stable not installed (Editor > Manage Export Templates)." }
        New-Item -ItemType Directory -Force "$proj\android\build" | Out-Null
        Expand-Archive $zip "$proj\android\build" -Force
        [System.IO.File]::WriteAllText("$proj\android\.build_version", "4.7.2.stable", (New-Object System.Text.UTF8Encoding($false)))
    }
    # --- 3. import + export
    Write-Host "Importing..."
    & $Godot --headless --path $proj --import
    Write-Host "Exporting APK (first build downloads Gradle into .cache\gradle, takes a few minutes)..."
    & $Godot --headless --path $proj --export-debug "MetaQuest" $apk
    if (-not (Test-Path $apk)) { throw "Export failed, no APK at $apk" }
}
if (-not (Test-Path $apk)) { throw "No APK yet. Run without -SkipBuild." }

# --- 4. install
$adb = "$env:ANDROID_HOME\platform-tools\adb.exe"
$devices = & $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\sdevice$" }
if (-not $devices) { throw "No headset found. Plug in the Quest, put it on, accept 'Allow USB debugging'. (adb devices)" }
Write-Host "Installing on: $devices"
& $adb install -r $apk
if (-not $NoLaunch) {
    & $adb shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null
    Write-Host "Launched $package. Next time: Apps > Unknown sources > SeeSaw XR."
}
Write-Host "Done. Server for the headset: http://$ServerIp`:$Port  (start the sidecar with  run_sidecar.ps1 -Lan)"
