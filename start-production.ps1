[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Hermes3.6-35B-A3B-Uncensored-Genesis-APEX-Compact.gguf"),
    [int]$Port = 11434
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$launcher = Join-Path $repoRoot "native-windows\start-server.ps1"
$setup = Join-Path $repoRoot "native-windows\setup.ps1"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw @"
The tested APEX Compact production GGUF was not found:
  $ModelPath

Run .\setup-production.ps1 first, or pass another model path:
  .\start-production.ps1 -ModelPath 'D:\models\Hermes3.6-35B-A3B-Uncensored-Genesis-APEX-Compact.gguf'
"@
}

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($portOwner) {
    throw "TCP port $Port is already in use by process $($portOwner.OwningProcess). Stop it or pass -Port another value."
}

$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$runtimeReady = Get-ChildItem -LiteralPath $runtimeRoot -Filter "llama-server.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $runtimeReady) {
    Write-Host "Pinned SYCL runtime not found; installing it now..." -ForegroundColor Cyan
    & $setup -BuildTag "b9986" -ModelPath $ModelPath
    if ($LASTEXITCODE -ne 0) {
        throw "The llama.cpp SYCL runtime setup failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Starting the tested APEX Compact 64K production profile." -ForegroundColor Green
Write-Host "Keep this window open. Press Ctrl+C to stop the server." -ForegroundColor Yellow
& $launcher -ModelPath $ModelPath -Port $Port
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
