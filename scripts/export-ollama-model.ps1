[CmdletBinding()]
param(
    [string]$Model = "huihui_ai/Qwen3.6-abliterated:35b",
    [string]$DestinationDirectory = (Join-Path $env:USERPROFILE "llama-models"),
    [string]$DestinationName = "qwen3.6-35b-abliterated-q4_k_m.gguf"
)

$ErrorActionPreference = "Stop"

$modelsRoot = if ($env:OLLAMA_MODELS) {
    $env:OLLAMA_MODELS
} else {
    Join-Path $env:USERPROFILE ".ollama\models"
}

if ($Model -notmatch '^(?<namespace>[^/]+)/(?<repo>[^:]+):(?<tag>.+)$') {
    throw "Expected model syntax namespace/repository:tag, got: $Model"
}

$namespace = $Matches.namespace
$repo = $Matches.repo
$tag = $Matches.tag
$manifestsRoot = Join-Path $modelsRoot "manifests\registry.ollama.ai"
$manifestPath = Join-Path $manifestsRoot "$namespace\$repo\$tag"

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    $candidate = Get-ChildItem -LiteralPath $manifestsRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -ieq $tag -and
            $_.Directory.Name -ieq $repo -and
            $_.Directory.Parent.Name -ieq $namespace
        } |
        Select-Object -First 1
    if (-not $candidate) {
        throw "Could not find Ollama manifest for '$Model' below '$manifestsRoot'. Run 'ollama show $Model' first."
    }
    $manifestPath = $candidate.FullName
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$modelLayer = $manifest.layers |
    Where-Object { $_.mediaType -eq "application/vnd.ollama.image.model" } |
    Select-Object -First 1

if (-not $modelLayer) {
    $modelLayer = $manifest.layers |
        Where-Object { $_.mediaType -notmatch '(template|license|params|system|messages)' } |
        Sort-Object -Property size -Descending |
        Select-Object -First 1
}
if (-not $modelLayer -or -not $modelLayer.digest) {
    throw "The manifest does not contain a recognizable model layer."
}

$digestFile = $modelLayer.digest -replace ':', '-'
$blobPath = Join-Path $modelsRoot "blobs\$digestFile"
if (-not (Test-Path -LiteralPath $blobPath -PathType Leaf)) {
    throw "Model blob is missing: $blobPath"
}

$stream = [System.IO.File]::OpenRead($blobPath)
try {
    $header = New-Object byte[] 4
    if ($stream.Read($header, 0, 4) -ne 4) { throw "Model blob is too short." }
    $magic = [System.Text.Encoding]::ASCII.GetString($header)
    if ($magic -ne "GGUF") {
        throw "Selected Ollama blob is not a GGUF file (header was '$magic')."
    }
} finally {
    $stream.Dispose()
}

New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
$destination = Join-Path $DestinationDirectory $DestinationName

if (Test-Path -LiteralPath $destination) {
    $sourceLength = (Get-Item -LiteralPath $blobPath).Length
    $destinationLength = (Get-Item -LiteralPath $destination).Length
    if ($sourceLength -eq $destinationLength) {
        Write-Host "Destination already exists and has the expected size: $destination"
    } else {
        throw "Destination exists with a different size: $destination"
    }
} else {
    try {
        New-Item -ItemType HardLink -Path $destination -Target $blobPath | Out-Null
        Write-Host "Created a zero-copy hard link to the Ollama GGUF blob."
    } catch {
        Write-Warning "Hard-link creation failed; copying the 24 GB model instead. $($_.Exception.Message)"
        Copy-Item -LiteralPath $blobPath -Destination $destination
    }
}

$full = (Resolve-Path -LiteralPath $destination).Path
$wslPath = if ($full -match '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') {
    "/mnt/$($Matches.drive.ToLower())/$($Matches.rest -replace '\\','/')"
} else {
    $full
}

Write-Host ""
Write-Host "Windows path: $full"
Write-Host "WSL directory: $([System.IO.Path]::GetDirectoryName($wslPath))"
Write-Host "WSL filename:  $([System.IO.Path]::GetFileName($wslPath))"
