[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$InputFolder,
  [Parameter(Mandatory = $true)] [string]$SceneName,
  [string]$OutputFolder,
  [string]$ManifestPath,
  [int]$StartCut = 10,
  [int]$CutStep = 10,
  [int]$Version = 1,
  [string[]]$Extensions = @(".mp4", ".mov", ".mxf", ".avi")
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

Assert-NoXDrive $InputFolder
if ($OutputFolder) { Assert-NoXDrive $OutputFolder }
if ($ManifestPath) { Assert-NoXDrive $ManifestPath }

if (-not (Test-Path -LiteralPath $InputFolder)) { throw "Input folder not found: $InputFolder" }

$inputResolved = (Resolve-Path -LiteralPath $InputFolder).Path
if (-not $OutputFolder) { $OutputFolder = $inputResolved }
if (-not $ManifestPath) { $ManifestPath = Join-Path $inputResolved "topaz_manifest.json" }

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$files = Get-ChildItem -LiteralPath $inputResolved -File |
  Where-Object { $Extensions -contains $_.Extension.ToLowerInvariant() } |
  Sort-Object Name

if ($files.Count -eq 0) { throw "No video files found in $inputResolved for extensions: $($Extensions -join ', ')" }

$items = @()
$cut = $StartCut
foreach ($file in $files) {
  $cutName = "C{0:D4}" -f $cut
  $versionName = "v{0:D3}" -f $Version
  $outputName = "{0}_{1}_{2}.mov" -f $SceneName, $cutName, $versionName
  $items += [PSCustomObject]@{
    source = $file.FullName
    output = (Join-Path $OutputFolder $outputName)
  }
  $cut += $CutStep
}

$manifest = [PSCustomObject]@{
  schema = "topaz-premiere-automation.manifest.v1"
  generatedAt = (Get-Date).ToString("s")
  sceneName = $SceneName
  items = $items
}

$json = $manifest | ConvertTo-Json -Depth 8
Set-Content -LiteralPath $ManifestPath -Value $json -Encoding UTF8
Write-Host "Wrote manifest: $ManifestPath"
Write-Host "Items: $($items.Count)"
