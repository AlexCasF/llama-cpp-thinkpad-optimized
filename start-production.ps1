[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-ggml-model-Q4_K.gguf"),
    [int]$Port = 11434
)

$ErrorActionPreference = "Stop"
$repoRoot = $PSScriptRoot
$launcher = Join-Path $repoRoot "native-windows\start-server.ps1"
$setup = Join-Path $repoRoot "native-windows\setup.ps1"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw @"
The tested production GGUF was not found:
  $ModelPath

Download the verified Q4_K GGUF into that directory, or pass another path:
  .\start-production.ps1 -ModelPath 'D:\models\qwen36-35b-q4_k.gguf'
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

Write-Host "Starting the tested 64K q4 production profile." -ForegroundColor Green
Write-Host "Keep this window open. Press Ctrl+C to stop the server." -ForegroundColor Yellow
& $launcher -ModelPath $ModelPath -Port $Port
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
