[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\qwen3.6-35b-abliterated-q4_k_m.gguf"),
    [string]$LlamaBench = "",
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "..\results\native"),
    [int]$Repetitions = 2,
    [int]$TuneNCPUMOE = 32,
    [int]$TuneThreads = 6,
    [int]$TuneUBatch = 1024,
    [switch]$NoMmap
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
    throw "Model does not exist: $ModelPath"
}
if (Get-Process -Name "ollama","llama-server" -ErrorAction SilentlyContinue) {
    throw "Stop Ollama and any llama-server process before benchmarking; the model needs most of the 32GB."
}

if ([string]::IsNullOrWhiteSpace($LlamaBench)) {
    $runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
    $candidate = Get-ChildItem -LiteralPath $runtimeRoot -Filter "llama-bench.exe" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $candidate) { throw "llama-bench.exe was not found. Run native-windows\setup.ps1 or pass -LlamaBench." }
    $LlamaBench = $candidate.FullName
}

$env:ONEAPI_DEVICE_SELECTOR = "level_zero:gpu"
$env:ZES_ENABLE_SYSMAN = "1"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$mmap = if ($NoMmap) { 0 } else { 1 }

function Invoke-BenchCase {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][int]$NCPUMOE,
        [Parameter(Mandatory = $true)][int]$Threads,
        [Parameter(Mandatory = $true)][int]$UBatch,
        [Parameter(Mandatory = $true)][int]$Prompt,
        [Parameter(Mandatory = $true)][int]$Generate
    )

    $csv = Join-Path $OutputDirectory "$Label.csv"
    $log = Join-Path $OutputDirectory "$Label.log"
    $args = @(
        "-m", (Resolve-Path -LiteralPath $ModelPath).Path,
        "-ngl", "99",
        "-ncmoe", "$NCPUMOE",
        "-t", "$Threads",
        "-ub", "$UBatch",
        "-p", "$Prompt",
        "-n", "$Generate",
        "-ctk", "q8_0",
        "-ctv", "q8_0",
        "-fa", "auto",
        "-mmp", "$mmap",
        "-r", "$Repetitions",
        "-o", "csv"
    )
    Write-Host "=== $Label ==="
    & $LlamaBench @args 1> $csv 2> $log
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "FAILED: $Label (see $log)"
    } else {
        Write-Host "Saved: $csv"
    }
}

Write-Host "Using mmap=$mmap. Results will be written to $OutputDirectory."

# Stage 1: expert placement. 40 means all 40 layers' MoE weights stay on CPU.
foreach ($n in @(40, 36, 32, 28, 24)) {
    Invoke-BenchCase -Label "tg-moe-$n" -NCPUMOE $n -Threads $TuneThreads -UBatch 512 -Prompt 0 -Generate 128
    Invoke-BenchCase -Label "pp-moe-$n" -NCPUMOE $n -Threads $TuneThreads -UBatch 512 -Prompt 2048 -Generate 0
}

# Stage 2: decode threads. Eight logical processors does not imply eight is fastest.
foreach ($t in @(4, 5, 6, 7)) {
    Invoke-BenchCase -Label "tg-threads-$t" -NCPUMOE $TuneNCPUMOE -Threads $t -UBatch 512 -Prompt 0 -Generate 128
}

# Stage 3: physical batch for agent prompt processing.
foreach ($ub in @(256, 512, 1024, 2048)) {
    Invoke-BenchCase -Label "pp-ubatch-$ub" -NCPUMOE $TuneNCPUMOE -Threads $TuneThreads -UBatch $ub -Prompt 4096 -Generate 0
}

Write-Host ""
Write-Host "Compare avg_ts in the CSV files. Re-run with -NoMmap to test the video-style no-mmap variant."
