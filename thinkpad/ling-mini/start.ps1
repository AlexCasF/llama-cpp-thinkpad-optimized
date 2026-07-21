[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Huihui-Ling-mini-2.0-abliterated.Q4_K_S.gguf"),
    [int]$Port = 11434,
    [ValidateSet("fast", "fast-q4", "long", "ngram")]
    [string]$Profile = "long",
    [ValidateSet("on", "auto", "off")]
    [string]$FlashAttention = "on"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Profile and runtime configuration.
$profileName = "ThinkPad / Ling-mini 2.0 / $Profile"
$modelAlias = "ling-mini-2.0"
$runtimeDir = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime\b10075"
$llamaServer = Join-Path $runtimeDir "llama-server.exe"
$backendName = "Intel SYCL / Level Zero"
$useLevelZero = $true

# Inference configuration. The default is the tested 128K profile. The switch
# below retains explicit short-context speed controls for optional comparisons.
$ctxSize = 131072
$nGpuLayers = 99
$nCpuMoe = 0
$nThreads = 6
$nThreadsBatch = 7
$nBatch = 2048
$nUbatch = 1024
$cacheTypeK = "q4_0"
$cacheTypeV = "q4_0"
$flashAttention = $FlashAttention
$parallel = 1
$cacheRam = 256
$cacheReuse = 256
$timeout = 86400
$mmapEnabled = $true
$cachePromptEnabled = $true
$continuousBatchingEnabled = $true
$jinjaEnabled = $true
$webUiEnabled = $false
$metricsEnabled = $true
$deviceArgs = @()
$numaArgs = @()
$fitArgs = @("--fit", "on", "--fit-target", "512")
$ropeArgs = @(
    "--rope-scaling", "yarn",
    "--rope-scale", "4",
    "--yarn-orig-ctx", "32768",
    "--override-kv", "bailingmoe2.context_length=int:131072"
)
$specArgs = @()

switch ($Profile) {
    "fast" {
        $ctxSize = 32768
        $nBatch = 4096
        $nUbatch = 2048
        $cacheTypeK = "q8_0"
        $cacheTypeV = "q8_0"
        $ropeArgs = @()
    }
    "fast-q4" {
        $ctxSize = 32768
        $nBatch = 4096
        $nUbatch = 2048
        $cacheTypeK = "q4_0"
        $cacheTypeV = "q4_0"
        $ropeArgs = @()
    }
    "long" {
        # The 128K defaults above are already the long profile.
    }
    "ngram" {
        $specArgs = @(
            "--spec-type", "ngram-mod",
            "--spec-ngram-mod-n-match", "24",
            "--spec-ngram-mod-n-min", "48",
            "--spec-ngram-mod-n-max", "64"
        )
    }
}

function Write-ServerLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host "[server] $Message" -ForegroundColor $Color
}

function Assert-File {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found at '$Path'. Run .\setup.ps1 first."
    }
}

function Assert-PortAvailable {
    $portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($portOwner) {
        throw "TCP port $Port is already in use by process $($portOwner.OwningProcess). Stop it or pass -Port another value."
    }
}

function Get-FeatureArgs {
    $featureArgs = @(
        "--parallel", "$parallel",
        "--cache-ram", "$cacheRam",
        "--cache-reuse", "$cacheReuse",
        "--timeout", "$timeout"
    )
    if ($cachePromptEnabled) { $featureArgs += "--cache-prompt" }
    if ($continuousBatchingEnabled) { $featureArgs += "--cont-batching" }
    if ($jinjaEnabled) { $featureArgs += "--jinja" }
    if (-not $webUiEnabled) { $featureArgs += "--no-webui" }
    if ($metricsEnabled) { $featureArgs += "--metrics" }
    $featureArgs += $(if ($mmapEnabled) { "--mmap" } else { "--no-mmap" })
    return $featureArgs
}

try {
    Assert-File -Path $ModelPath -Description "The Ling-mini model"
    Assert-File -Path $llamaServer -Description "The pinned SYCL llama.cpp runtime"
    Assert-PortAvailable
    $resolvedModelPath = (Resolve-Path -LiteralPath $ModelPath).Path

    if ($useLevelZero) {
        $env:ONEAPI_DEVICE_SELECTOR = "level_zero:gpu"
        $env:ZES_ENABLE_SYSMAN = "1"
    }

    $serverArgs = @(
        "--model", $resolvedModelPath,
        "--alias", $modelAlias,
        "--host", "0.0.0.0",
        "--port", "$Port",
        "--ctx-size", "$ctxSize",
        "--n-gpu-layers", "$nGpuLayers",
        "--n-cpu-moe", "$nCpuMoe",
        "--threads", "$nThreads",
        "--threads-batch", "$nThreadsBatch",
        "--batch-size", "$nBatch",
        "--ubatch-size", "$nUbatch",
        "--cache-type-k", $cacheTypeK,
        "--cache-type-v", $cacheTypeV,
        "--flash-attn", $flashAttention
    ) + $deviceArgs + $numaArgs + $fitArgs + $ropeArgs + $specArgs + (Get-FeatureArgs)

    Write-ServerLog "Profile: $profileName" Green
    Write-ServerLog "Runtime: $llamaServer"
    Write-ServerLog "Model: $resolvedModelPath"
    Write-ServerLog "Backend: $backendName"
    Write-ServerLog "Context: $ctxSize"
    Write-ServerLog "GPU layers: $nGpuLayers / CPU MoE layers: $nCpuMoe"
    Write-ServerLog "Threads: $nThreads decode / $nThreadsBatch batch"
    Write-ServerLog "Batch: $nBatch / ubatch $nUbatch"
    Write-ServerLog "KV cache: $cacheTypeK / $cacheTypeV"
    Write-ServerLog "Flash attention: $flashAttention"
    Write-ServerLog "mmap: $(if ($mmapEnabled) { 'enabled' } else { 'disabled' })"
    if ($ropeArgs.Count -gt 0) { Write-ServerLog "RoPE: YaRN from 32K to 128K" }
    if ($specArgs.Count -gt 0) { Write-ServerLog "Speculation: ngram-mod" }
    Write-ServerLog "Keep this window open. Press Ctrl+C to stop the server." Yellow

    & $llamaServer @serverArgs
    $serverExitCode = $LASTEXITCODE
    if ($serverExitCode -ne 0) {
        throw "llama-server exited with code $serverExitCode."
    }
    Write-ServerLog "Server stopped." Green
}
catch {
    Write-ServerLog "FAILED: $($_.Exception.Message)" Red
    throw
}
