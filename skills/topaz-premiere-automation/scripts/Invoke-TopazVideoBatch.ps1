[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$ManifestPath,
  [string]$TopazFfmpegPath,
  [string]$ModelDir = "$env:ProgramData\Topaz Labs LLC\Topaz Video\models",
  [int]$Width = 3840,
  [int]$Height = 2160,
  [string]$RheaModel = "rhea-1",
  [string]$ApolloModel = "apo-8",
  [ValidateSet("copy", "none")] [string]$AudioMode = "copy",
  [int]$GpuDevice = 0,
  [int]$Vram = 1,
  [int]$FrameLimit = 0,
  [switch]$NoFrameInterpolation,
  [switch]$AlwaysFrameInterpolation,
  [switch]$NoForce24Fps,
  [switch]$Force,
  [switch]$DryRun,
  [ValidateSet("quiet", "panic", "fatal", "error", "warning", "info", "verbose", "debug", "trace")]
  [string]$FfmpegLogLevel = "error"
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

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

function Convert-RateToDouble {
  param([string]$Rate)
  if (-not $Rate -or $Rate -eq "0/0") { return $null }
  if ($Rate -match '^([0-9.]+)/([0-9.]+)$') {
    $num = [double]$Matches[1]
    $den = [double]$Matches[2]
    if ($den -eq 0) { return $null }
    return $num / $den
  }
  return [double]$Rate
}

function Format-ArgsForLog {
  param([string[]]$ArgsList)
  return ($ArgsList | ForEach-Object {
    if ($_ -match '[\s"`]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
  }) -join " "
}

function Get-ManifestItems {
  param([string]$PathValue)
  if (-not (Test-Path -LiteralPath $PathValue)) { throw "Manifest not found: $PathValue" }
  $raw = Get-Content -LiteralPath $PathValue -Raw
  $parsed = $raw | ConvertFrom-Json
  if ($parsed.PSObject.Properties.Name -contains "items") { return @($parsed.items) }
  return @($parsed)
}

function Get-VideoStreamProbe {
  param([string]$FfprobePath, [string]$PathValue)
  $probeJson = & $FfprobePath -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate,r_frame_rate,codec_name,codec_tag_string,pix_fmt -of json $PathValue
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $PathValue" }
  $streams = @((($probeJson | ConvertFrom-Json).streams))
  if ($streams.Count -eq 0) { throw "No video stream found: $PathValue" }
  return $streams[0]
}

function Invoke-TopazProcessRedacted {
  param([string]$ExePath, [string[]]$ArgsList)
  $oldErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $ExePath @ArgsList 2>&1 | ForEach-Object {
      $line = $_.ToString()
      if ($line -match 'TopazAuthManager.*parseAuth' -or $line -match '"auth_studio"|refresh_studio|username_studio') {
        Write-Host "[TopazAuthManager] auth details redacted"
      } else {
        Write-Host $line
      }
    }
    return $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $oldErrorActionPreference
  }
}

Assert-NoXDrive $ManifestPath
Assert-NoXDrive $ModelDir

$ffmpeg = Resolve-TopazFfmpeg $TopazFfmpegPath
$ffprobe = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"

if (-not (Test-Path -LiteralPath $ModelDir)) { throw "Topaz model directory not found: $ModelDir" }
if (-not (Test-Path -LiteralPath $ffprobe)) { throw "ffprobe.exe not found next to Topaz ffmpeg: $ffprobe" }

$env:TVAI_MODEL_DIR = $ModelDir
$env:TVAI_MODEL_DATA_DIR = $ModelDir

$items = @(Get-ManifestItems $ManifestPath)
if ($items.Count -eq 0) { throw "Manifest has no items: $ManifestPath" }

$index = 0
foreach ($item in $items) {
  $index++
  $source = [string]$item.source
  $output = [string]$item.output
  $trimStart = [string]$item.trimStart
  $duration = [string]$item.duration

  if (-not $source) { throw "Item $index is missing source." }
  if (-not $output) { throw "Item $index is missing output." }

  Assert-NoXDrive $source
  Assert-NoXDrive $output

  if (-not (Test-Path -LiteralPath $source)) { throw "Source not found for item $index`: $source" }
  if ((Test-Path -LiteralPath $output) -and -not $Force) { throw "Output exists for item $index. Use -Force to overwrite: $output" }

  $sourceProbe = Get-VideoStreamProbe $ffprobe $source
  $sourceAvgRate = Convert-RateToDouble ([string]$sourceProbe.avg_frame_rate)
  $sourceRealRate = Convert-RateToDouble ([string]$sourceProbe.r_frame_rate)
  $sourceRateForDecision = if ($sourceAvgRate -ne $null) { $sourceAvgRate } else { $sourceRealRate }
  $sourceIsExact24 = ($sourceRateForDecision -ne $null) -and ([math]::Abs($sourceRateForDecision - 24.0) -lt 0.001)

  $itemNoFi = ($item.PSObject.Properties.Name -contains "noFrameInterpolation") -and ([bool]$item.noFrameInterpolation)
  $itemHasFiPreference = $item.PSObject.Properties.Name -contains "frameInterpolation"
  $useFrameInterpolation = (-not $NoFrameInterpolation) -and (-not $itemNoFi)
  if ($itemHasFiPreference -and -not $NoFrameInterpolation) {
    $useFrameInterpolation = [bool]$item.frameInterpolation
  } elseif ($sourceIsExact24 -and -not $AlwaysFrameInterpolation) {
    $useFrameInterpolation = $false
  }

  $filterParts = @()
  if ($useFrameInterpolation) {
    $filterParts += "tvai_fi=model=$ApolloModel`:slowmo=1`:rdt=-0.000001`:device=$GpuDevice`:vram=$Vram`:instances=1"
  }
  $filterParts += "tvai_up=model=$RheaModel`:scale=0`:w=$Width`:h=$Height`:preblur=0`:noise=0`:details=0`:halo=0`:blur=0`:compression=0`:estimate=8`:device=$GpuDevice`:vram=$Vram`:instances=1"
  $filterParts += "scale=w=$Width`:h=$Height`:flags=lanczos`:threads=0"
  if (-not $NoForce24Fps) {
    $filterParts += "fps=fps=24"
  }
  $filterComplex = $filterParts -join ","
  $modelsUsed = if ($useFrameInterpolation) { "$ApolloModel and $RheaModel" } else { $RheaModel }

  $outputDir = Split-Path -Parent $output
  if ($outputDir) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }

  $args = @("-hide_banner", "-loglevel", $FfmpegLogLevel, "-nostdin", "-y", "-nostats")
  if ($trimStart) { $args += @("-ss", $trimStart) }
  $args += @("-i", $source)
  if ($duration) { $args += @("-t", $duration) }
  $args += @(
    "-sws_flags", "spline+accurate_rnd+full_chroma_int",
    "-filter_complex", $filterComplex,
    "-c:v", "prores_ks",
    "-profile:v", "4",
    "-vendor", "apl0",
    "-tag:v", "ap4h",
    "-pix_fmt", "yuv444p10le",
    "-metadata:s:v:0", "encoder=AppleProRes4444"
  )

  if ($AudioMode -eq "copy") {
    $args += @("-c:a", "copy")
  } else {
    $args += @("-an")
  }

  $args += @("-map_metadata", "0", "-map_metadata:s:v", "0:s:v")

  if (-not $NoForce24Fps) {
    $args += @("-r:v", "24", "-fps_mode:v", "cfr")
  } else {
    $args += @("-fps_mode:v", "passthrough")
  }

  $args += @(
    "-movflags", "frag_keyframe+empty_moov+delay_moov+use_metadata_tags+write_colr",
    "-bf", "0",
    "-metadata", "videoai=Processed using $modelsUsed. Changed resolution to ${Width}x${Height}"
  )

  if ($FrameLimit -gt 0) { $args += @("-frames:v", [string]$FrameLimit) }
  $args += $output

  $sourceRateText = if ($sourceRateForDecision -ne $null) { "{0:N6}" -f $sourceRateForDecision } else { "unknown" }
  $fiText = if ($useFrameInterpolation) { "on" } else { "off" }
  Write-Host "[$index/$($items.Count)] $source -> $output"
  Write-Host "Source fps: $sourceRateText, frame interpolation: $fiText"
  Write-Host (Format-ArgsForLog (@($ffmpeg) + $args))

  if (-not $DryRun) {
    $exitCode = Invoke-TopazProcessRedacted $ffmpeg $args
    if ($exitCode -ne 0) { throw "Topaz ffmpeg failed for item $index with exit code $exitCode." }

    $probe = Get-VideoStreamProbe $ffprobe $output
    $avg = Convert-RateToDouble ([string]$probe.avg_frame_rate)
    $real = Convert-RateToDouble ([string]$probe.r_frame_rate)
    $rateOk = (($avg -ne $null) -and ([math]::Abs($avg - 24.0) -lt 0.001)) -or (($real -ne $null) -and ([math]::Abs($real - 24.0) -lt 0.001))

    if ([int]$probe.width -ne $Width -or [int]$probe.height -ne $Height) {
      throw "Output resolution check failed: $output reports $($probe.width)x$($probe.height), expected ${Width}x${Height}."
    }
    if (-not $rateOk) {
      throw "Output fps check failed: $output avg=$($probe.avg_frame_rate) r=$($probe.r_frame_rate), expected 24fps."
    }
    if ([string]$probe.codec_tag_string -ne "ap4h") {
      throw "Output codec tag check failed: $output reports $($probe.codec_tag_string), expected ap4h."
    }

    Write-Host "Verified: ${Width}x${Height}, 24fps, ProRes 4444 tag ap4h"
  }
}

Write-Host "Batch complete."
