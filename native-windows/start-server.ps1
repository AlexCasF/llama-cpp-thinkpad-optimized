[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Hermes3.6-35B-A3B-Uncensored-Genesis-APEX-Compact.gguf"),
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw "Model does not exist: $ModelPath. Run native-windows\setup.ps1 or pass -ModelPath."
}

$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$candidate = Get-ChildItem -LiteralPath $runtimeRoot -Filter "llama-server.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $candidate) {
    throw "llama-server.exe was not found. Run native-windows\setup.ps1 first."
}
$llamaServer = $candidate.FullName

# Locked production profile for the matching ThinkPad hardware.
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

$args = @(
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
    "--metrics"
)

$args += "--mmap"

Write-Host "Starting the locked ThinkPad production profile"
Write-Host "  server:       $llamaServer"
Write-Host "  model:        $ModelPath"
Write-Host "  context:      $ctxSize"
Write-Host "  GPU layers:   99"
Write-Host "  CPU MoE:      $nCpuMoe of 40 layers"
Write-Host "  threads:      $nThreads decode / $nThreadsBatch batch"
Write-Host "  logical batch:   $nBatch"
Write-Host "  physical ubatch: $nUbatch"
Write-Host "  KV cache:     $cacheTypeK / $cacheTypeV"
Write-Host "  flash attention: $flashAttention"
Write-Host "  mmap/mlock:   True / False"

# Start the server as a tracked child so Ctrl+C cleanup cannot leave it behind.
# Quote each argument because Start-Process receives one command-line string.
$quotedArgs = $args | ForEach-Object {
    '"' + ($_ -replace '"', '\"') + '"'
}
$serverProcess = $null
$exitCode = 0

try {
    $serverProcess = Start-Process -FilePath $llamaServer `
        -ArgumentList $quotedArgs `
        -NoNewWindow `
        -PassThru

    Wait-Process -Id $serverProcess.Id
    $serverProcess.Refresh()
    $exitCode = $serverProcess.ExitCode
}
finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Write-Host "Stopping llama-server child process $($serverProcess.Id)..." -ForegroundColor Yellow
        Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

exit $exitCode
