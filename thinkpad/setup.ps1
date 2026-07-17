[CmdletBinding()]
param(
    [string]$ModelDirectory = (Join-Path $env:USERPROFILE "llama-models"),
    [string]$BuildTag = "b9986"
)

$ErrorActionPreference = "Stop"
$modelFile = "Hermes3.6-35B-A3B-Uncensored-Genesis-V3-APEX-Compact.gguf"
$modelPath = Join-Path $ModelDirectory $modelFile
$modelUrl = "https://huggingface.co/LuffyTheFox/Qwen3.6-35B-A3B-Uncensored-Genesis-Hermes-V3-GGUF/resolve/main/${modelFile}?download=true"
$expectedSize = [int64]17327724672
$expectedSha256 = "50594a0b81d4c951e6925b0e4e6804d2d9d3ce060cabfdf3c697e552415fed0f"

$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$runtimeDir = Join-Path $runtimeRoot $BuildTag
$archive = Join-Path $runtimeRoot "llama-$BuildTag-bin-win-sycl-x64.zip"
$assetName = "llama-$BuildTag-bin-win-sycl-x64.zip"
$releaseUri = "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BuildTag"

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
    Write-Host "Downloading the verified 17.3 GB V3 APEX Compact model. This is resumable and may take a while..." -ForegroundColor Cyan
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

$release = Invoke-RestMethod -Uri $releaseUri -Headers @{ "User-Agent" = "llama-server-kit" }
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) {
    throw "The release '$BuildTag' does not contain the Windows SYCL asset '$assetName'."
}
if (-not $asset.digest -or $asset.digest -notmatch '^sha256:') {
    throw "The release asset does not provide a SHA-256 digest: $assetName"
}
$expectedRuntimeSha256 = $asset.digest.Substring(7).ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$needsRuntimeDownload = $true
if (Test-Path -LiteralPath $archive -PathType Leaf) {
    Write-Host "Verifying the cached llama.cpp SYCL runtime..." -ForegroundColor Cyan
    $actualRuntimeSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $needsRuntimeDownload = $actualRuntimeSha256 -ne $expectedRuntimeSha256
}
if ($needsRuntimeDownload) {
    Write-Host "Downloading $assetName..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
}

$actualRuntimeSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualRuntimeSha256 -ne $expectedRuntimeSha256) {
    throw "llama.cpp runtime SHA-256 mismatch. Expected $expectedRuntimeSha256, got $actualRuntimeSha256."
}

$server = Join-Path $runtimeDir "llama-server.exe"
$bench = Join-Path $runtimeDir "llama-bench.exe"
if (-not (Test-Path -LiteralPath $server) -or -not (Test-Path -LiteralPath $bench)) {
    New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $runtimeDir -Force
}
if (-not (Test-Path -LiteralPath $server) -or -not (Test-Path -LiteralPath $bench)) {
    throw "The SYCL archive was extracted, but llama-server.exe or llama-bench.exe is missing."
}

Write-Host "Model verified: $modelPath" -ForegroundColor Green
Write-Host "SYCL device check:" -ForegroundColor Cyan
& $bench --list-devices
if ($LASTEXITCODE -ne 0) {
    throw "The SYCL device check failed."
}

Write-Host "Runtime: $server" -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete. Start the server with:" -ForegroundColor Green
Write-Host "  & '$PSScriptRoot\start.ps1'"
Write-Host "or double-click '$PSScriptRoot\start.cmd'."
