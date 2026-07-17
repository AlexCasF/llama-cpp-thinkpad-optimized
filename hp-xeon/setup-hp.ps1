[CmdletBinding()]
param(
    [string]$ModelDirectory = (Join-Path $env:USERPROFILE "llama-models"),
    [string]$BuildTag = "b9986"
)

$ErrorActionPreference = "Stop"

# Verified model artifact used by the original Qwen production setup.
$modelFile = "Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-ggml-model-Q4_K.gguf"
$modelPath = Join-Path $ModelDirectory $modelFile
$partialModelPath = "$modelPath.part"
$modelUrl = "https://huggingface.co/huihui-ai/Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated-MTP-GGUF/resolve/main/${modelFile}?download=true"
$expectedModelSize = [int64]21712410016
$expectedModelSha256 = "a20002fdac5d529946ef2ab3a4ad5da953e77ca7e30dcc6ca9b6b738e0c7ff4d"

# Official llama.cpp CPU runtime for 64-bit Windows.
$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$runtimeDir = Join-Path $runtimeRoot "$BuildTag-cpu"
$archive = Join-Path $runtimeRoot "llama-$BuildTag-bin-win-cpu-x64.zip"
$assetName = "llama-$BuildTag-bin-win-cpu-x64.zip"
$releaseUri = "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BuildTag"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

New-Item -ItemType Directory -Force -Path $ModelDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    throw "Windows curl.exe was not found. This script requires the built-in Windows 10/11 curl client."
}

$validModel = $false
if (Test-Path -LiteralPath $modelPath -PathType Leaf) {
    $item = Get-Item -LiteralPath $modelPath
    if ($item.Length -eq $expectedModelSize) {
        Write-Host "Verifying existing Qwen model SHA-256..." -ForegroundColor Cyan
        $validModel = (Get-Sha256 $modelPath) -eq $expectedModelSha256
    }
    if (-not $validModel) {
        Write-Warning "The existing Qwen model is incomplete or has the wrong SHA-256; it will be downloaded again."
        Remove-Item -LiteralPath $modelPath -Force
    }
}

if (-not $validModel) {
    if (Test-Path -LiteralPath $partialModelPath -PathType Leaf) {
        $partial = Get-Item -LiteralPath $partialModelPath
        if ($partial.Length -ge $expectedModelSize) {
            Remove-Item -LiteralPath $partialModelPath -Force
        }
    }

    Write-Host "Downloading the verified 21.7 GB Qwen Q4_K model. This is resumable..." -ForegroundColor Cyan
    $curlArgs = @(
        "-L", "--fail", "--retry", "5", "--retry-delay", "5",
        "-C", "-", "-o", $partialModelPath, $modelUrl
    )
    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Model download failed with exit code $LASTEXITCODE. Re-run this script to resume."
    }

    $item = Get-Item -LiteralPath $partialModelPath
    if ($item.Length -ne $expectedModelSize) {
        throw "Downloaded model has $($item.Length) bytes; expected $expectedModelSize. Re-run to resume."
    }
    $hash = Get-Sha256 $partialModelPath
    if ($hash -ne $expectedModelSha256) {
        throw "Model SHA-256 mismatch. Expected $expectedModelSha256, got $hash."
    }
    Move-Item -LiteralPath $partialModelPath -Destination $modelPath -Force
}

Write-Host "Model verified: $modelPath" -ForegroundColor Green

$release = Invoke-RestMethod -Uri $releaseUri -Headers @{ "User-Agent" = "llama-server-kit" }
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) {
    throw "The release '$BuildTag' does not contain '$assetName'."
}
if (-not $asset.digest -or $asset.digest -notmatch '^sha256:') {
    throw "The release asset does not provide a SHA-256 digest: $assetName"
}
$expectedRuntimeSha256 = $asset.digest.Substring(7).ToLowerInvariant()

$needsRuntimeDownload = $true
if (Test-Path -LiteralPath $archive -PathType Leaf) {
    Write-Host "Verifying the cached llama.cpp CPU runtime..." -ForegroundColor Cyan
    $needsRuntimeDownload = (Get-Sha256 $archive) -ne $expectedRuntimeSha256
}
if ($needsRuntimeDownload) {
    Write-Host "Downloading $assetName..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
}

$actualRuntimeSha256 = Get-Sha256 $archive
if ($actualRuntimeSha256 -ne $expectedRuntimeSha256) {
    throw "llama.cpp runtime SHA-256 mismatch. Expected $expectedRuntimeSha256, got $actualRuntimeSha256."
}

$server = Join-Path $runtimeDir "llama-server.exe"
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $runtimeDir -Force
}
if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
    throw "The CPU archive was extracted, but llama-server.exe was not found."
}

Write-Host ""
Write-Host "CPU runtime check:" -ForegroundColor Cyan
& $server --version
if ($LASTEXITCODE -ne 0) {
    throw "llama-server.exe failed its runtime check."
}

Write-Host ""
Write-Host "HP CPU-only setup complete." -ForegroundColor Green
Write-Host "Model:  $modelPath"
Write-Host "Start:  & '$PSScriptRoot\start-hp.ps1'"
