[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-ggml-model-Q4_K.gguf"),
    [int]$Port = 11434
)

$ErrorActionPreference = "Stop"
$runtimeDir = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime\b9986-cpu"
$llamaServer = Join-Path $runtimeDir "llama-server.exe"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw "The Qwen model was not found at '$ModelPath'. Run .\setup-hp.ps1 first."
}
if (-not (Test-Path -LiteralPath $llamaServer -PathType Leaf)) {
    throw "The CPU llama.cpp runtime was not found. Run .\setup-hp.ps1 first."
}

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($portOwner) {
    throw "TCP port $Port is already in use by process $($portOwner.OwningProcess). Stop it or pass -Port another value."
}

# Locked profile for the dual Xeon Silver 4114 HP Z6 G4.
$args = @(
    "--model", (Resolve-Path -LiteralPath $ModelPath).Path,
    "--alias", "qwen3.6-35b-hp",
    "--host", "0.0.0.0",
    "--port", "$Port",
    "--device", "none",
    "--n-gpu-layers", "0",
    "--n-cpu-moe", "40",
    "--ctx-size", "8192",
    "--threads", "20",
    "--threads-batch", "40",
    "--numa", "distribute",
    "--batch-size", "512",
    "--ubatch-size", "256",
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--flash-attn", "auto",
    "--parallel", "1",
    "--cache-ram", "128",
    "--timeout", "86400",
    "--cache-prompt",
    "--cont-batching",
    "--jinja",
    "--no-webui",
    "--metrics",
    "--mmap"
)

Write-Host "Starting the HP Z6 G4 CPU-only Qwen profile" -ForegroundColor Green
Write-Host "  server:       $llamaServer"
Write-Host "  model:        $ModelPath"
Write-Host "  context:      8192"
Write-Host "  CPU MoE:      40 of 40 layers"
Write-Host "  threads:      20 decode / 40 batch"
Write-Host "  batch:        512 / ubatch 256"
Write-Host "  KV cache:     q4_0 / q4_0"
Write-Host "  NUMA:         distribute"
Write-Host "  GPU:          disabled"
Write-Host ""
Write-Host "Keep this window open. Press Ctrl+C to stop the server." -ForegroundColor Yellow

& $llamaServer @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
