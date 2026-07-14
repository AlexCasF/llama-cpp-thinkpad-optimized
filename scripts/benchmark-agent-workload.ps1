[CmdletBinding()]
param(
    [string]$ModelPath = (Join-Path $env:USERPROFILE "llama-models\Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-ggml-model-Q4_K.gguf"),
    [int]$Port = 18114,
    [int]$RequestsPerVariant = 10,
    [int]$RestartEveryRequests = 0,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot ("..\results\agent-benchmark-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),
    [string[]]$OnlyVariant = @(),
    [switch]$KeepFinalServer
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$serverItem = Get-ChildItem -LiteralPath $runtimeRoot -Filter "llama-server.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $serverItem) { throw "Pinned llama-server.exe was not found. Run setup-production.ps1 first." }
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) { throw "Model does not exist: $ModelPath" }

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$logDirectory = Join-Path $OutputDirectory "server-logs"
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$baseUri = "http://127.0.0.1:$Port"

$variants = @(
    [ordered]@{ Name = "baseline-1024"; NCPUMOE = 36; Threads = 6; ThreadsBatch = 7; Batch = 1024; UBatch = 1024; Flash = "on" },
    [ordered]@{ Name = "threads-7";     NCPUMOE = 36; Threads = 7; ThreadsBatch = 7; Batch = 1024; UBatch = 1024; Flash = "on" },
    [ordered]@{ Name = "moe35";         NCPUMOE = 35; Threads = 6; ThreadsBatch = 7; Batch = 1024; UBatch = 1024; Flash = "on" },
    [ordered]@{ Name = "prefill-1536";  NCPUMOE = 36; Threads = 6; ThreadsBatch = 7; Batch = 2048; UBatch = 1536; Flash = "on" },
    [ordered]@{ Name = "flash-auto";    NCPUMOE = 36; Threads = 6; ThreadsBatch = 7; Batch = 1024; UBatch = 1024; Flash = "auto" }
)
if ($OnlyVariant.Count -gt 0) {
    $variants = @($variants | Where-Object { $_.Name -in $OnlyVariant })
    if ($variants.Count -eq 0) { throw "No requested variant matched. Available: baseline-1024, threads-7, moe35, prefill-1536, flash-auto" }
}
$targetPromptTokens = @(100, 500, 1000, 2000, 3000, 5000, 7000, 8000, 9000, 10000)
$targetPromptTokens = $targetPromptTokens | Select-Object -First $RequestsPerVariant

function Stop-InferenceProcesses {
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @("ollama.exe", "llama-server.exe") }
    foreach ($process in $processes) {
        Write-Host "Stopping inference process $($process.Name) PID $($process.ProcessId)" -ForegroundColor Yellow
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -match '[\s"]') {
        return '"' + $Value.Replace('"', '\"') + '"'
    }
    return $Value
}

function Get-Metrics {
    $metrics = @{}
    try {
        $text = (Invoke-WebRequest -UseBasicParsing -Uri "$baseUri/metrics" -TimeoutSec 10).Content
        foreach ($line in ($text -split "`n")) {
            if ($line -match '^llamacpp:(\S+)\s+([-+0-9.eE]+)\s*$') {
                $metrics[$Matches[1]] = [double]$Matches[2]
            }
        }
    } catch {
        # A request row will still contain wall-clock timings if metrics are unavailable.
    }
    return $metrics
}

function Get-SlotState {
    try {
        $result = Invoke-RestMethod -Uri "$baseUri/slots" -TimeoutSec 10
        return $result.value | Select-Object -First 1
    } catch {
        return $null
    }
}

function Get-HostState {
    $os = Get-CimInstance Win32_OperatingSystem
    $server = Get-CimInstance Win32_Process -Filter "Name = 'llama-server.exe'" |
        Where-Object { $_.ExecutablePath -eq $serverItem.FullName -or $_.CommandLine -like "*$($serverItem.FullName)*" } |
        Select-Object -First 1
    $workingSet = $null
    $gpuCommitted = $null
    if ($server) {
        $proc = Get-Process -Id $server.ProcessId -ErrorAction SilentlyContinue
        if ($proc) { $workingSet = [int64]$proc.WorkingSet64 }
        try {
            $gpu = Get-Counter '\GPU Process Memory(*)\Total Committed' -ErrorAction Stop
            $sample = $gpu.CounterSamples | Where-Object { $_.InstanceName -match "pid_$($server.ProcessId)_" } | Select-Object -First 1
            if ($sample) { $gpuCommitted = [int64]$sample.CookedValue }
        } catch { }
    }
    return [ordered]@{
        FreePhysicalMemoryMB = [math]::Round($os.FreePhysicalMemory / 1024, 1)
        ServerWorkingSetMB = if ($null -eq $workingSet) { $null } else { [math]::Round($workingSet / 1MB, 1) }
        GpuCommittedMB = if ($null -eq $gpuCommitted) { $null } else { [math]::Round($gpuCommitted / 1MB, 1) }
    }
}

function New-SharedPrompt {
    param([Parameter(Mandatory = $true)][int]$TargetTokens)
    $block = @"
[repository context item {0:D4}]
file: src/module_{0:D4}.ts
export function transform_{0:D4}(input: string): string {{
  const normalized = input.trim().replace(/\\s+/g, ' ');
  return normalized.slice(0, 240);
}}
test expectation: deterministic transformation for coding-agent benchmark item {0:D4}.
"@
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("You are reviewing a local coding repository. Use the supplied context to answer the request concisely.`n`n")
    $index = 1
    while ($builder.Length -lt ($TargetTokens * 5)) {
        [void]$builder.Append(($block -f $index))
        $index++
    }
    $desiredChars = [math]::Min($builder.Length, [math]::Max(400, $TargetTokens * 5))
    return $builder.ToString().Substring(0, $desiredChars)
}

function Start-VariantServer {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Variant)
    $stdout = Join-Path $logDirectory "$($Variant.Name).out.log"
    $stderr = Join-Path $logDirectory "$($Variant.Name).err.log"
    $args = @(
        "--model", $ModelPath,
        "--alias", "qwen3.6-35b",
        "--host", "127.0.0.1",
        "--port", "$Port",
        "--ctx-size", "131072",
        "--n-gpu-layers", "99",
        "--n-cpu-moe", "$($Variant.NCPUMOE)",
        "--threads", "$($Variant.Threads)",
        "--threads-batch", "$($Variant.ThreadsBatch)",
        "--batch-size", "$($Variant.Batch)",
        "--ubatch-size", "$($Variant.UBatch)",
        "--cache-type-k", "q4_0",
        "--cache-type-v", "q4_0",
        "--flash-attn", "$($Variant.Flash)",
        "--parallel", "1",
        "--cache-ram", "128",
        "--cache-reuse", "256",
        "--timeout", "86400",
        "--cache-prompt",
        "--cont-batching",
        "--jinja",
        "--no-webui",
        "--slots",
        "--metrics",
        "--mmap"
    )
    $argumentString = ($args | ForEach-Object { Quote-ProcessArgument $_ }) -join ' '
    Write-Host "Starting $($Variant.Name): $argumentString" -ForegroundColor Cyan
    return Start-Process -FilePath $serverItem.FullName -ArgumentList $argumentString -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
}

function Wait-ServerReady {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)
    for ($i = 0; $i -lt 180; $i++) {
        $Process.Refresh()
        if ($Process.HasExited) { throw "llama-server exited during startup. See the variant log." }
        try {
            $health = Invoke-RestMethod -Uri "$baseUri/health" -TimeoutSec 2
            if ($health.status -eq "ok") { return }
        } catch { }
        Start-Sleep -Seconds 1
    }
    throw "Timed out waiting for llama-server health."
}

$rows = New-Object System.Collections.Generic.List[object]
Stop-InferenceProcesses

try {
    foreach ($variant in $variants) {
        $server = $null
        try {
            $server = Start-VariantServer -Variant $variant
            Wait-ServerReady -Process $server
            Write-Host "$($variant.Name) is healthy." -ForegroundColor Green

            $sharedPrompts = @{}
            foreach ($target in $targetPromptTokens) {
                $sharedPrompts[$target] = New-SharedPrompt -TargetTokens $target
            }

            $requestIndex = 0
            foreach ($target in $targetPromptTokens) {
                $requestIndex++
                $prompt = $sharedPrompts[$target]
                $body = [ordered]@{
                    model = "qwen3.6-35b"
                    messages = @(
                        @{ role = "system"; content = "You are a deterministic coding-agent benchmark assistant. Answer concisely and do not call tools." },
                        @{ role = "user"; content = $prompt }
                    )
                    max_tokens = 64
                    temperature = 0
                    seed = 42
                    stream = $false
                    cache_prompt = $true
                } | ConvertTo-Json -Depth 8 -Compress

                $before = Get-Metrics
                $start = [DateTime]::UtcNow
                $stopwatch = [Diagnostics.Stopwatch]::StartNew()
                $errorText = $null
                $response = $null
                try {
                    $response = Invoke-RestMethod -Uri "$baseUri/v1/chat/completions" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 1800
                } catch {
                    $errorText = $_.Exception.Message
                }
                $stopwatch.Stop()
                $after = Get-Metrics
                $slot = Get-SlotState
                $hostState = Get-HostState

                $promptTokens = if ($response -and $response.usage) { [int]$response.usage.prompt_tokens } else { $null }
                $completionTokens = if ($response -and $response.usage) { [int]$response.usage.completion_tokens } else { $null }
                $cachedFromResponse = $null
                if ($response -and $response.PSObject.Properties.Name -contains 'tokens_cached') { $cachedFromResponse = [int]$response.tokens_cached }
                if ($null -eq $cachedFromResponse -and $response -and $response.usage -and $response.usage.prompt_tokens_details) {
                    $cachedFromResponse = [int]$response.usage.prompt_tokens_details.cached_tokens
                }
                $promptSeconds = if ($before.ContainsKey('prompt_seconds_total') -and $after.ContainsKey('prompt_seconds_total')) { $after['prompt_seconds_total'] - $before['prompt_seconds_total'] } else { $null }
                $predictedSeconds = if ($before.ContainsKey('tokens_predicted_seconds_total') -and $after.ContainsKey('tokens_predicted_seconds_total')) { $after['tokens_predicted_seconds_total'] - $before['tokens_predicted_seconds_total'] } else { $null }
                $promptProcessed = if ($before.ContainsKey('prompt_tokens_total') -and $after.ContainsKey('prompt_tokens_total')) { $after['prompt_tokens_total'] - $before['prompt_tokens_total'] } else { $null }
                $predicted = if ($before.ContainsKey('tokens_predicted_total') -and $after.ContainsKey('tokens_predicted_total')) { $after['tokens_predicted_total'] - $before['tokens_predicted_total'] } else { $completionTokens }

                $row = [ordered]@{
                    Variant = $variant.Name
                    Request = $requestIndex
                    TargetPromptTokens = $target
                    PromptTokens = $promptTokens
                    CompletionTokens = $completionTokens
                    PromptTokensProcessed = $promptProcessed
                    PromptSeconds = $promptSeconds
                    PromptTokensPerSecond = if ($promptSeconds -and $promptSeconds -gt 0 -and $promptProcessed -gt 0) { [math]::Round($promptProcessed / $promptSeconds, 3) } else { $null }
                    PredictedTokens = $predicted
                    PredictedSeconds = $predictedSeconds
                    GenerationTokensPerSecond = if ($predictedSeconds -and $predictedSeconds -gt 0 -and $predicted -gt 0) { [math]::Round($predicted / $predictedSeconds, 3) } else { $null }
                    WallSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
                    CachedPromptTokens = if ($null -ne $cachedFromResponse) { $cachedFromResponse } elseif ($slot -and $slot.PSObject.Properties.Name -contains 'n_prompt_tokens_cache') { $slot.n_prompt_tokens_cache } else { $null }
                    SlotPromptTokens = if ($slot -and $slot.PSObject.Properties.Name -contains 'n_prompt_tokens') { $slot.n_prompt_tokens } else { $null }
                    FreePhysicalMemoryMB = $hostState.FreePhysicalMemoryMB
                    ServerWorkingSetMB = $hostState.ServerWorkingSetMB
                    GpuCommittedMB = $hostState.GpuCommittedMB
                    StartedUtc = $start.ToString("o")
                    Error = $errorText
                }
                $rows.Add([pscustomobject]$row)
                if ($errorText) {
                    Write-Warning "$($variant.Name) request $requestIndex failed: $errorText"
                    if ($server.HasExited) { break }
                } else {
                    Write-Host ("{0} request {1}/{2}: prompt={3} cached={4} pp={5} tg={6} wall={7}s RAMfree={8}MB GPU={9}MB" -f `
                        $variant.Name, $requestIndex, $targetPromptTokens.Count, $promptTokens, $row.CachedPromptTokens, $row.PromptTokensPerSecond, $row.GenerationTokensPerSecond, $row.WallSeconds, $row.FreePhysicalMemoryMB, $row.GpuCommittedMB)
                }

                if ($RestartEveryRequests -gt 0 -and $requestIndex -lt $targetPromptTokens.Count -and ($requestIndex % $RestartEveryRequests) -eq 0) {
                    if ($server -and -not $server.HasExited) {
                        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
                        Wait-Process -Id $server.Id -Timeout 20 -ErrorAction SilentlyContinue
                    }
                    Start-Sleep -Seconds 3
                    $server = Start-VariantServer -Variant $variant
                    Wait-ServerReady -Process $server
                }
            }
        } catch {
            Write-Warning "$($variant.Name) aborted: $($_.Exception.Message)"
        } finally {
            if (-not $KeepFinalServer -and $server -and -not $server.HasExited) {
                Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
                Wait-Process -Id $server.Id -Timeout 20 -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 3
        }
    }
} finally {
    if (-not $KeepFinalServer) { Stop-InferenceProcesses }
}

$csvPath = Join-Path $OutputDirectory "requests.csv"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$summary = $rows | Group-Object Variant | ForEach-Object {
    $valid = @($_.Group | Where-Object { [string]::IsNullOrEmpty($_.Error) -and $null -ne $_.GenerationTokensPerSecond })
    [pscustomobject]@{
        Variant = $_.Name
        Requests = $_.Count
        Successful = $valid.Count
        AvgGenerationTokensPerSecond = if ($valid.Count) { [math]::Round(($valid.GenerationTokensPerSecond | Measure-Object -Average).Average, 3) } else { $null }
        MedianGenerationTokensPerSecond = if ($valid.Count) { [math]::Round(($valid.GenerationTokensPerSecond | Sort-Object)[[math]::Floor(($valid.Count - 1) / 2)], 3) } else { $null }
        AvgPromptTokensPerSecond = if ($valid.Count) { [math]::Round(($valid.PromptTokensPerSecond | Measure-Object -Average).Average, 3) } else { $null }
        AvgCachedPromptTokens = if ($valid.Count) { [math]::Round(($valid.CachedPromptTokens | Measure-Object -Average).Average, 1) } else { $null }
        MinFreePhysicalMemoryMB = if ($valid.Count) { [math]::Round(($valid.FreePhysicalMemoryMB | Measure-Object -Minimum).Minimum, 1) } else { $null }
        MaxGpuCommittedMB = if ($valid.Count) { [math]::Round(($valid.GpuCommittedMB | Measure-Object -Maximum).Maximum, 1) } else { $null }
    }
}
$summary | Export-Csv -LiteralPath (Join-Path $OutputDirectory "summary.csv") -NoTypeInformation -Encoding UTF8

Write-Host "Benchmark complete. Requests: $csvPath" -ForegroundColor Green
Write-Host "Summary:   $(Join-Path $OutputDirectory 'summary.csv')" -ForegroundColor Green
