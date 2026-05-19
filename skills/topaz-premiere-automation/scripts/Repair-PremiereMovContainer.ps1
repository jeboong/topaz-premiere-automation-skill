[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$Path,
  [string]$FfmpegPath,
  [string]$BackupDir,
  [switch]$Recurse,
  [switch]$Require24Fps,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

function Resolve-Ffmpeg {
  param([string]$PathFromUser)
  if ($PathFromUser) {
    if (-not (Test-Path -LiteralPath $PathFromUser)) { throw "ffmpeg not found: $PathFromUser" }
    return (Resolve-Path -LiteralPath $PathFromUser).Path
  }
  $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $topaz = "$env:ProgramFiles\Topaz Labs LLC\Topaz Video\ffmpeg.exe"
  if (Test-Path -LiteralPath $topaz) { return (Resolve-Path -LiteralPath $topaz).Path }
  throw "ffmpeg was not found. Pass -FfmpegPath or install ffmpeg/Topaz Video."
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

function Get-MovProbe {
  param([string]$FfprobePath, [string]$PathValue)
  $json = & $FfprobePath -v error -select_streams v:0 -show_entries stream=codec_name,codec_tag_string,width,height,avg_frame_rate,r_frame_rate -show_entries format_tags=major_brand,compatible_brands -of json $PathValue
  if ($LASTEXITCODE -ne 0) { throw "ffprobe failed: $PathValue" }
  return ($json | ConvertFrom-Json)
}

Assert-NoXDrive $Path
if ($BackupDir) { Assert-NoXDrive $BackupDir }
if ($FfmpegPath) { Assert-NoXDrive $FfmpegPath }

$ffmpeg = Resolve-Ffmpeg $FfmpegPath
$ffprobe = Join-Path (Split-Path -Parent $ffmpeg) "ffprobe.exe"
if (-not (Test-Path -LiteralPath $ffprobe)) { throw "ffprobe.exe not found next to ffmpeg: $ffprobe" }

$resolvedPath = Resolve-Path -LiteralPath $Path
$target = Get-Item -LiteralPath $resolvedPath.Path
if ($target.PSIsContainer) {
  if ($Recurse) {
    $files = @(Get-ChildItem -LiteralPath $target.FullName -Filter "*.mov" -File -Recurse)
  } else {
    $files = @(Get-ChildItem -LiteralPath $target.FullName -Filter "*.mov" -File)
  }
} else {
  $files = @($target)
}

if ($files.Count -eq 0) { throw "No .mov files found: $Path" }

if (-not $BackupDir) {
  $root = if ($target.PSIsContainer) { $target.FullName } else { Split-Path -Parent $target.FullName }
  $BackupDir = Join-Path $root ("_premiere_mov_remux_backup_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

foreach ($file in $files) {
  Assert-NoXDrive $file.FullName
  $tmp = Join-Path $file.DirectoryName ($file.BaseName + ".qtbrand.tmp.mov")
  $backup = Join-Path $BackupDir $file.Name
  if ((Test-Path -LiteralPath $backup) -and -not $Force) { throw "Backup already exists. Use -Force or a new -BackupDir: $backup" }
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }

  Write-Host "Remuxing for Premiere: $($file.FullName)"
  & $ffmpeg -hide_banner -loglevel error -nostdin -y -i $file.FullName -map 0 -c copy -f mov -brand "qt  " -movflags use_metadata_tags+write_colr $tmp
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { throw "ffmpeg remux failed: $($file.FullName)" }

  $probe = Get-MovProbe $ffprobe $tmp
  $streams = @($probe.streams)
  if ($streams.Count -eq 0) { throw "Remuxed file has no video stream: $tmp" }
  $stream = $streams[0]
  $majorBrand = [string]$probe.format.tags.major_brand
  if ($majorBrand -ne "qt  ") { throw "Remuxed file major_brand is '$majorBrand', expected 'qt  ': $tmp" }
  if ([string]$stream.codec_tag_string -ne "ap4h") { Write-Warning "Video codec tag is $($stream.codec_tag_string), not ap4h: $tmp" }

  if ($Require24Fps) {
    $avg = Convert-RateToDouble ([string]$stream.avg_frame_rate)
    $real = Convert-RateToDouble ([string]$stream.r_frame_rate)
    $avgOk = ($avg -ne $null) -and ([math]::Abs($avg - 24.0) -lt 0.001)
    $realOk = ($real -ne $null) -and ([math]::Abs($real - 24.0) -lt 0.001)
    if (-not $avgOk -or -not $realOk) {
      throw "Remuxed file is not clean 24fps: avg=$($stream.avg_frame_rate) r=$($stream.r_frame_rate), file=$tmp"
    }
  }

  Move-Item -LiteralPath $file.FullName -Destination $backup -Force
  Move-Item -LiteralPath $tmp -Destination $file.FullName -Force
  Write-Host "OK: $($file.Name)"
}

Write-Host "Backups: $BackupDir"
