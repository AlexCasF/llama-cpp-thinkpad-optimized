[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Hermes3.6-35B-A3B-Uncensored-Genesis-V3-APEX-Compact.gguf"),
    [int]$Port = 11434
)

$ErrorActionPreference = "Stop"
$runtimeDir = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime\b9986"
$llamaServer = Join-Path $runtimeDir "llama-server.exe"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw @"
The tested V3 APEX Compact production GGUF was not found:
  $ModelPath

Run .\setup.ps1 first, or pass another model path:
  .\start.ps1 -ModelPath 'D:\models\Hermes3.6-35B-A3B-Uncensored-Genesis-V3-APEX-Compact.gguf'
"@
}
if (-not (Test-Path -LiteralPath $llamaServer -PathType Leaf)) {
    throw "The pinned SYCL llama.cpp runtime was not found. Run .\setup.ps1 first."
}

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($portOwner) {
    throw "TCP port $Port is already in use by process $($portOwner.OwningProcess). Stop it or pass -Port another value."
}

# Locked production profile for the ThinkPad Ultra 5 228V / Intel Arc 130V.
$ctxSize = 65536
$nCpuMoe = 36
$nThreads = 6
$nThreadsBatch = 7
$nBatch = 1024
$nUbatch = 1024
$cacheTypeK = "q4_0"
$cacheTypeV = "q4_0"
$flashAttention = "auto"
$cacheRam = 128

# The official Windows SYCL package uses Level Zero for Intel Arc.
$env:ONEAPI_DEVICE_SELECTOR = "level_zero:gpu"
$env:ZES_ENABLE_SYSMAN = "1"

$serverArgs = @(
    "--model", (Resolve-Path -LiteralPath $ModelPath).Path,
    "--alias", "qwen3.6-35b",
    "--host", "0.0.0.0",
    "--port", "$Port",
    "--ctx-size", "$ctxSize",
    "--n-gpu-layers", "99",
    "--n-cpu-moe", "$nCpuMoe",
    "--threads", "$nThreads",
    "--threads-batch", "$nThreadsBatch",
    "--batch-size", "$nBatch",
    "--ubatch-size", "$nUbatch",
    "--cache-type-k", "$cacheTypeK",
    "--cache-type-v", "$cacheTypeV",
    "--flash-attn", "$flashAttention",
    "--parallel", "1",
    "--cache-ram", "$cacheRam",
    "--cache-reuse", "256",
    "--timeout", "86400",
    "--cache-prompt",
    "--cont-batching",
    "--jinja",
    "--no-webui",
    "--metrics",
    "--mmap"
)

Write-Host "Starting the tested V3 APEX Compact 64K production profile" -ForegroundColor Green
Write-Host "  server:          $llamaServer"
Write-Host "  model:           $ModelPath"
Write-Host "  context:         $ctxSize"
Write-Host "  GPU layers:      99"
Write-Host "  CPU MoE:         $nCpuMoe of 40 layers"
Write-Host "  threads:         $nThreads decode / $nThreadsBatch batch"
Write-Host "  batch:           $nBatch / ubatch $nUbatch"
Write-Host "  KV cache:        $cacheTypeK / $cacheTypeV"
Write-Host "  flash attention: $flashAttention"
Write-Host "  mmap:            enabled"
Write-Host ""
Write-Host "Keep this window open. Press Ctrl+C to stop the server." -ForegroundColor Yellow

& $llamaServer @serverArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
