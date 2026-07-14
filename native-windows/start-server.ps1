[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\qwen3.6-35b-abliterated-q4_k_m.gguf"),
    [string]$LlamaServer = "",
    [string]$Alias = "qwen3.6-35b",
    [ValidateSet("safe", "balanced", "speed", "long", "video-fast")]
    [string]$Profile = "safe",
    [int]$Port = 8080,
    [int]$NCPUMOE = -1,
    [int]$Threads = -1,
    [int]$ThreadsBatch = -1,
    [int]$UBatch = -1,
    [switch]$NoMmap,
    [switch]$Mlock
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw "Model does not exist: $ModelPath. Run native-windows\setup.ps1 or pass -ModelPath."
}

if ([string]::IsNullOrWhiteSpace($LlamaServer)) {
    $runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
    $candidate = Get-ChildItem -LiteralPath $runtimeRoot -Filter "llama-server.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $candidate) {
        $candidate = Get-Command "llama-server.exe" -ErrorAction SilentlyContinue
    }
    if (-not $candidate) {
        throw "llama-server.exe was not found. Run native-windows\setup.ps1 or pass -LlamaServer."
    }
    if ($candidate.PSObject.Properties.Name -contains "Source" -and $candidate.Source) {
        $LlamaServer = $candidate.Source
    } else {
        $LlamaServer = $candidate.FullName
    }
}

$profiles = @{
    # First GPU boot. Keeps the video flags that matter while preserving RAM headroom.
    safe       = @{ ctx = 65536;  ncmoe = 36; ubatch = 512;  batch = 2048; k = "q8_0"; v = "q8_0"; fa = "auto"; cacheRam = 128; mmap = $true }
    balanced   = @{ ctx = 131072; ncmoe = 36; ubatch = 1024; batch = 1024; k = "q4_0"; v = "q4_0"; fa = "on";   cacheRam = 128; mmap = $true }
    speed      = @{ ctx = 65536;  ncmoe = 28; ubatch = 2048; batch = 2048; k = "q8_0"; v = "q8_0"; fa = "auto"; cacheRam = 256; mmap = $true }
    long       = @{ ctx = 262144; ncmoe = 36; ubatch = 1024; batch = 1024; k = "q4_0"; v = "q4_0"; fa = "on";   cacheRam = 128; mmap = $true }
    # Video-style experiment: no mmap can reduce page faults, but is memory-hungry.
    'video-fast' = @{ ctx = 65536;  ncmoe = 28; ubatch = 1024; batch = 2048; k = "q8_0"; v = "q8_0"; fa = "auto"; cacheRam = 256; mmap = $false }
}
$p = $profiles[$Profile]

$nCpuMoe = if ($NCPUMOE -ge 0) { $NCPUMOE } else { $p.ncmoe }
$nThreads = if ($Threads -ge 0) { $Threads } else { 6 }
$nThreadsBatch = if ($ThreadsBatch -ge 0) { $ThreadsBatch } else { 7 }
$nUbatch = if ($UBatch -ge 0) { $UBatch } else { $p.ubatch }
$useMmap = $p.mmap -and (-not $NoMmap)

# The official Windows SYCL package uses Level Zero for Intel Arc.
$env:ONEAPI_DEVICE_SELECTOR = "level_zero:gpu"
$env:ZES_ENABLE_SYSMAN = "1"

$args = @(
    "--model", (Resolve-Path -LiteralPath $ModelPath).Path,
    "--alias", $Alias,
    "--host", "0.0.0.0",
    "--port", "$Port",
    "--ctx-size", "$($p.ctx)",
    "--n-gpu-layers", "99",
    "--n-cpu-moe", "$nCpuMoe",
    "--threads", "$nThreads",
    "--threads-batch", "$nThreadsBatch",
    "--batch-size", "$($p.batch)",
    "--ubatch-size", "$nUbatch",
    "--cache-type-k", "$($p.k)",
    "--cache-type-v", "$($p.v)",
    "--flash-attn", "$($p.fa)",
    "--parallel", "1",
    "--cache-ram", "$($p.cacheRam)",
    "--cache-reuse", "256",
    "--timeout", "86400",
    "--cache-prompt",
    "--cont-batching",
    "--jinja",
    "--no-webui",
    "--metrics"
)

if ($useMmap) {
    $args += "--mmap"
} else {
    $args += "--no-mmap"
}
if ($Mlock) {
    $args += "--mlock"
}

Write-Host "Starting llama-server with profile '$Profile'"
Write-Host "  server:       $LlamaServer"
Write-Host "  model:        $ModelPath"
Write-Host "  context:      $($p.ctx)"
Write-Host "  GPU layers:   99"
Write-Host "  CPU MoE:      $nCpuMoe of 40 layers"
Write-Host "  threads:      $nThreads decode / $nThreadsBatch batch"
Write-Host "  physical ubatch: $nUbatch"
Write-Host "  logical batch:   $($p.batch)"
Write-Host "  KV cache:     $($p.k) / $($p.v)"
Write-Host "  flash attention: $($p.fa)"
Write-Host "  mmap/mlock:   $useMmap / $Mlock"

& $LlamaServer @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
