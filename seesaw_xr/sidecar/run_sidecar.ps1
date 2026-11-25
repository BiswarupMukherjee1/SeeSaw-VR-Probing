<#
  Starts the See/Saw sidecar with every cache and temp folder on D: (never C:).
    .\run_sidecar.ps1              # desktop only (127.0.0.1)
    .\run_sidecar.ps1 -Lan         # reachable from the Quest over Wi-Fi
    .\run_sidecar.ps1 -Backend rgb # plumbing test, no torch / no model
#>
param(
    [switch]$Lan,
    [ValidateSet("dinov2", "rgb")][string]$Backend = "dinov2",
    [int]$Port = 8765,
    [string]$Python = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot            # seesaw_xr
if ((Split-Path -Qualifier $root) -eq "C:") { throw "Project is on C:. Move it to D: first." }

$cache = Join-Path $root ".cache"
$tmp = Join-Path $root ".tmp"
New-Item -ItemType Directory -Force "$cache\huggingface", "$cache\torch", "$cache\cuda", $tmp | Out-Null
$env:TEMP = $tmp; $env:TMP = $tmp
$env:HF_HOME = "$cache\huggingface"
$env:TORCH_HOME = "$cache\torch"
$env:CUDA_CACHE_PATH = "$cache\cuda"                 # NVIDIA kernel cache defaults to C:
$env:HF_HUB_DISABLE_XET = "1"                        # the Xet download host resets connections on some networks
$env:HF_HUB_DISABLE_SYMLINKS_WARNING = "1"
$env:PYTHONDONTWRITEBYTECODE = "1"

if (-not $Python) {
    $candidates = @(
        "$PSScriptRoot\.venv\Scripts\python.exe",
        "$root\..\seesaw_poc\seesaw_poc\sidecar\.venv\Scripts\python.exe"   # venv made for the first prototype
    )
    $Python = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Python) { throw "No Python venv found. Create one on D: (see README), or pass -Python <path>." }

$args2 = @("-m", "seesaw_sidecar", "--backend", $Backend, "--port", $Port)
if ($Lan) { $args2 += @("--host", "0.0.0.0") }
Set-Location $PSScriptRoot
& $Python @args2
