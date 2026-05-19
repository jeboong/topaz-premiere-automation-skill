[CmdletBinding()]
param(
  [string]$TopazFfmpegPath,
  [string]$ModelDir = "$env:ProgramData\Topaz Labs LLC\Topaz Video\models",
  [string]$RheaModel = "rhea-1",
  [string]$ApolloModel = "apo-8"
)

$ErrorActionPreference = "Stop"

function Resolve-TopazFfmpeg {
  param([string]$PathFromUser)
  if ($PathFromUser) {
    if (-not (Test-Path -LiteralPath $PathFromUser)) { throw "Topaz ffmpeg not found: $PathFromUser" }
    return (Resolve-Path -LiteralPath $PathFromUser).Path
  }

  $candidates = @(@(
    "$env:ProgramFiles\Topaz Labs LLC\Topaz Video\ffmpeg.exe",
    "${env:ProgramFiles(x86)}\Topaz Labs LLC\Topaz Video\ffmpeg.exe"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

  if ($candidates.Count -gt 0) { return (Resolve-Path -LiteralPath $candidates[0]).Path }
  throw "Topaz Video ffmpeg.exe was not found. Install Topaz Video, not Topaz Video AI, or pass -TopazFfmpegPath."
}

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

$ffmpeg = Resolve-TopazFfmpeg $TopazFfmpegPath
Assert-NoXDrive $ffmpeg
Assert-NoXDrive $ModelDir

if (-not (Test-Path -LiteralPath $ModelDir)) { throw "Topaz model directory not found: $ModelDir" }

$env:TVAI_MODEL_DIR = $ModelDir
$env:TVAI_MODEL_DATA_DIR = $ModelDir

$rheaFiles = @(Get-ChildItem -LiteralPath $ModelDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$RheaModel*" })
$apolloFiles = @(Get-ChildItem -LiteralPath $ModelDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$ApolloModel*" })

if ($rheaFiles.Count -eq 0) { throw "Rhea model files not found under $ModelDir. Expected prefix: $RheaModel" }
if ($apolloFiles.Count -eq 0) { throw "Apollo model files not found under $ModelDir. Expected prefix: $ApolloModel" }

Write-Host "Topaz Video ffmpeg: $ffmpeg"
Write-Host "Model directory: $ModelDir"
Write-Host "Found Rhea files: $($rheaFiles.Count)"
Write-Host "Found Apollo files: $($apolloFiles.Count)"

$upHelp = & $ffmpeg -hide_banner -h filter=tvai_up 2>&1
$fiHelp = & $ffmpeg -hide_banner -h filter=tvai_fi 2>&1

if (($upHelp -join "`n") -notmatch "tvai_up") { throw "Topaz tvai_up filter did not respond correctly." }
if (($fiHelp -join "`n") -notmatch "tvai_fi") { throw "Topaz tvai_fi filter did not respond correctly." }

Write-Host "Topaz filters available: tvai_up, tvai_fi"
Write-Host "Ready for batch upscale."
