[CmdletBinding()]
param(
    [string]$ModelDirectory = (Join-Path $env:USERPROFILE "llama-models"),
    [string]$BuildTag = "b9986"
)

$ErrorActionPreference = "Stop"
$modelFile = "Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-ggml-model-Q4_K.gguf"
$modelPath = Join-Path $ModelDirectory $modelFile
$modelUrl = "https://huggingface.co/huihui-ai/Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-MTP-GGUF/resolve/main/$modelFile?download=true"
$expectedSize = [int64]21712410016
$expectedSha256 = "a20002fdac5d529946ef2ab3a4ad5da953e77ca7e30dcc6ca9b6b738e0c7ff4d"

New-Item -ItemType Directory -Force -Path $ModelDirectory | Out-Null

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "Windows curl.exe was not found. This script requires the built-in Windows 10/11 curl client."
}

$validModel = $false
if (Test-Path -LiteralPath $modelPath -PathType Leaf) {
    $item = Get-Item -LiteralPath $modelPath
    if ($item.Length -eq $expectedSize) {
        Write-Host "Verifying existing model SHA-256..." -ForegroundColor Cyan
        $hash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $validModel = $hash -eq $expectedSha256
        if (-not $validModel) {
            Write-Warning "Existing model hash does not match the tested artifact; it will be downloaded again."
        }
    }
}

if (-not $validModel) {
    if (Test-Path -LiteralPath $modelPath -PathType Leaf) {
        $existingModel = Get-Item -LiteralPath $modelPath
        if ($existingModel.Length -ge $expectedSize) {
            Remove-Item -LiteralPath $modelPath -Force
        }
    }
    Write-Host "Downloading the verified 21.7 GB Q4_K model. This is resumable and may take a while..." -ForegroundColor Cyan
    $curlArgs = @(
        "-L", "--fail", "--retry", "5", "--retry-delay", "5",
        "-o", $modelPath
    )
    if (Test-Path -LiteralPath $modelPath -PathType Leaf) {
        $curlArgs += @("-C", "-")
    }
    $curlArgs += $modelUrl
    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Model download failed with exit code $LASTEXITCODE. Re-run this script to resume."
    }

    $item = Get-Item -LiteralPath $modelPath
    if ($item.Length -ne $expectedSize) {
        throw "Downloaded model has $($item.Length) bytes; expected $expectedSize. Re-run to resume or repair the download."
    }
    $hash = (Get-FileHash -LiteralPath $modelPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $expectedSha256) {
        throw "Model SHA-256 mismatch. Expected $expectedSha256, got $hash."
    }
}

Write-Host "Model verified: $modelPath" -ForegroundColor Green
& (Join-Path $PSScriptRoot "native-windows\setup.ps1") -BuildTag $BuildTag -ModelPath $modelPath -SkipModelExport
if ($LASTEXITCODE -ne 0) {
    throw "llama.cpp runtime setup failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Setup complete. Start the server with:" -ForegroundColor Green
Write-Host "  .\start-production.ps1"
Write-Host "or double-click start-production.cmd."
