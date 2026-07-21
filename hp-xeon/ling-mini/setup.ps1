[CmdletBinding()]
param(
    [string]$ModelDirectory = (Join-Path $env:USERPROFILE "llama-models"),
    [string]$BuildTag = "b10075"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Profile and model configuration.
$profileName = "HP Z6 G4 / Ling-mini 2.0 hybrid"
$modelFile = "Huihui-Ling-mini-2.0-abliterated.Q4_K_S.gguf"
$modelUrl = "https://huggingface.co/mradermacher/Huihui-Ling-mini-2.0-abliterated-GGUF/resolve/main/${modelFile}?download=true"
$expectedModelSize = [int64]9302853088
$expectedModelSha256 = "f80fb22a69b33c019a7e127bd8aa2ee9607b885b1a9dccb9f7d00e9fec3274d2"

# Runtime configuration.
$runtimeFlavor = "Windows CUDA 12.4"
$runtimeRoot = Join-Path $env:LOCALAPPDATA "llama-server-kit\runtime"
$runtimeDirectoryName = "$BuildTag-cuda124"
$runtimeDir = Join-Path $runtimeRoot $runtimeDirectoryName
$runtimeArchive = Join-Path $runtimeRoot "llama-$BuildTag-bin-win-cuda-12.4-x64.zip"
$runtimeAssetName = "llama-$BuildTag-bin-win-cuda-12.4-x64.zip"
$releaseUri = "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BuildTag"
$runtimeCheckExeName = "llama-bench.exe"
$runtimeCheckArgs = @("--list-devices")
$requiredRuntimeFiles = @("llama-server.exe", "llama-bench.exe")
$useLevelZero = $false

$modelPath = Join-Path $ModelDirectory $modelFile
$partialModelPath = "$modelPath.part"
$modelSizeGiB = [math]::Round($expectedModelSize / 1GB, 1)

function Write-SetupLog {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )
    Write-Host "[setup] $Message" -ForegroundColor $Color
}

function Get-Sha256 {
    param([Parameter(Mandatory)] [string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Ensure-Model {
    if (Test-Path -LiteralPath $modelPath -PathType Leaf) {
        $existingModel = Get-Item -LiteralPath $modelPath
        if ($existingModel.Length -eq $expectedModelSize) {
            Write-SetupLog "Verifying existing model SHA-256..." Cyan
            if ((Get-Sha256 $modelPath) -eq $expectedModelSha256) {
                Write-SetupLog "Model verified: $modelPath" Green
                return
            }
        }

        Write-SetupLog "Existing model is incomplete or has the wrong SHA-256." Yellow
        if ($existingModel.Length -lt $expectedModelSize -and -not (Test-Path -LiteralPath $partialModelPath)) {
            Move-Item -LiteralPath $modelPath -Destination $partialModelPath -Force
        } else {
            Remove-Item -LiteralPath $modelPath -Force
        }
    }

    if (Test-Path -LiteralPath $partialModelPath -PathType Leaf) {
        $partialModel = Get-Item -LiteralPath $partialModelPath
        if ($partialModel.Length -ge $expectedModelSize) {
            Remove-Item -LiteralPath $partialModelPath -Force
        }
    }

    Write-SetupLog "Downloading the verified $modelSizeGiB GB model. This is resumable..." Cyan
    $curlArgs = @(
        "-L", "--fail", "--retry", "5", "--retry-delay", "5", "--retry-all-errors",
        "-o", $partialModelPath
    )
    if (Test-Path -LiteralPath $partialModelPath -PathType Leaf) {
        $partialModel = Get-Item -LiteralPath $partialModelPath
        if ($partialModel.Length -gt 0) {
            $curlArgs += @("-C", "-")
        }
    }
    $curlArgs += $modelUrl
    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Model download failed with exit code $LASTEXITCODE. Re-run this script to resume."
    }

    $downloadedModel = Get-Item -LiteralPath $partialModelPath
    if ($downloadedModel.Length -ne $expectedModelSize) {
        throw "Downloaded model has $($downloadedModel.Length) bytes; expected $expectedModelSize. Re-run to resume."
    }
    $actualSha256 = Get-Sha256 $partialModelPath
    if ($actualSha256 -ne $expectedModelSha256) {
        throw "Model SHA-256 mismatch. Expected $expectedModelSha256, got $actualSha256."
    }
    Move-Item -LiteralPath $partialModelPath -Destination $modelPath -Force
    Write-SetupLog "Model downloaded and verified: $modelPath" Green
}

function Ensure-Runtime {
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

    Write-SetupLog "Checking the pinned llama.cpp $runtimeFlavor release..." Cyan
    $release = Invoke-RestMethod -Uri $releaseUri -Headers @{ "User-Agent" = "llama-server-kit" }
    $asset = $release.assets | Where-Object { $_.name -eq $runtimeAssetName } | Select-Object -First 1
    if (-not $asset) {
        throw "Release '$BuildTag' does not contain '$runtimeAssetName'."
    }
    if (-not $asset.digest -or $asset.digest -notmatch '^sha256:') {
        throw "Release asset does not provide a SHA-256 digest: $runtimeAssetName"
    }
    $expectedRuntimeSha256 = $asset.digest.Substring(7).ToLowerInvariant()

    $downloadRuntime = $true
    if (Test-Path -LiteralPath $runtimeArchive -PathType Leaf) {
        Write-SetupLog "Verifying cached llama.cpp runtime..." Cyan
        $downloadRuntime = (Get-Sha256 $runtimeArchive) -ne $expectedRuntimeSha256
    }
    if ($downloadRuntime) {
        Write-SetupLog "Downloading $runtimeAssetName..." Cyan
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $runtimeArchive
    }
    $actualRuntimeSha256 = Get-Sha256 $runtimeArchive
    if ($actualRuntimeSha256 -ne $expectedRuntimeSha256) {
        throw "llama.cpp runtime SHA-256 mismatch. Expected $expectedRuntimeSha256, got $actualRuntimeSha256."
    }

    $missingRuntimeFiles = @($requiredRuntimeFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $runtimeDir $_) -PathType Leaf) })
    if ($missingRuntimeFiles.Count -gt 0) {
        Write-SetupLog "Extracting the llama.cpp runtime..." Cyan
        New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null
        Expand-Archive -LiteralPath $runtimeArchive -DestinationPath $runtimeDir -Force
    }
    $missingRuntimeFiles = @($requiredRuntimeFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $runtimeDir $_) -PathType Leaf) })
    if ($missingRuntimeFiles.Count -gt 0) {
        throw "Runtime extraction is missing: $($missingRuntimeFiles -join ', ')"
    }

    $runtimeCheckPath = Join-Path $runtimeDir $runtimeCheckExeName
    Write-SetupLog "Running runtime check: $runtimeCheckExeName $($runtimeCheckArgs -join ' ')" Cyan
    & $runtimeCheckPath @runtimeCheckArgs
    if ($LASTEXITCODE -ne 0) {
        throw "The llama.cpp runtime check failed with exit code $LASTEXITCODE."
    }
    Write-SetupLog "Runtime ready: $runtimeCheckPath" Green
}

try {
    Write-SetupLog "Profile: $profileName" Green
    New-Item -ItemType Directory -Force -Path $ModelDirectory | Out-Null
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw "Windows curl.exe was not found. This script requires the built-in Windows 10/11 curl client."
    }
    Ensure-Model
    Ensure-Runtime
    Write-SetupLog "Setup complete. Start with .\start.ps1 or double-click .\start.cmd." Green
}
catch {
    Write-SetupLog "FAILED: $($_.Exception.Message)" Red
    throw
}
