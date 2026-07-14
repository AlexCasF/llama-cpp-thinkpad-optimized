[CmdletBinding()]
param(
    [string]$BuildTag = "b9986",
    [string]$ModelPath = ""
)

$ErrorActionPreference = "Stop"
$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$runtimeDir = Join-Path $runtimeRoot $BuildTag
$archive = Join-Path $runtimeRoot "llama-$BuildTag-bin-win-sycl-x64.zip"
$assetName = "llama-$BuildTag-bin-win-sycl-x64.zip"
$releaseUri = "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BuildTag"

New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
$release = Invoke-RestMethod -Uri $releaseUri -Headers @{ "User-Agent" = "llama-server-kit" }
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
if (-not $asset) {
    throw "The release '$BuildTag' does not contain the Windows SYCL asset '$assetName'."
}
if (-not $asset.digest -or $asset.digest -notmatch '^sha256:') {
    throw "The release asset does not provide a SHA-256 digest: $assetName"
}
$expectedHash = $asset.digest.Substring(7).ToLowerInvariant()

$needsDownload = $true
if (Test-Path -LiteralPath $archive -PathType Leaf) {
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $needsDownload = $actualHash -ne $expectedHash
}
if ($needsDownload) {
    Write-Host "Downloading $assetName..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive
}

$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $expectedHash) {
    throw "SHA-256 mismatch for $archive. Expected $expectedHash, got $actualHash."
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

if ($ModelPath) {
    if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
        throw "Model does not exist: $ModelPath"
    }
}

Write-Host ""
Write-Host "SYCL device check:"
& $bench --list-devices
if ($LASTEXITCODE -ne 0) { throw "The SYCL device check failed." }

Write-Host ""
Write-Host "Runtime: $server"
if ($ModelPath) {
    Write-Host "Model:   $ModelPath"
    Write-Host "Start:   .\start-production.ps1"
} else {
    Write-Host "Model setup skipped. Pass -ModelPath when starting the server."
}
