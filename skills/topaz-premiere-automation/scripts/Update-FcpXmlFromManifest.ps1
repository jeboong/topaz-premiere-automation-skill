[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$XmlPath,
  [Parameter(Mandatory = $true)] [string]$ManifestPath,
  [string]$OutputXmlPath,
  [int]$Width = 3840,
  [int]$Height = 2160,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

function Get-ManifestItems {
  param([string]$PathValue)
  $raw = Get-Content -LiteralPath $PathValue -Raw
  $parsed = $raw | ConvertFrom-Json
  if ($parsed.PSObject.Properties.Name -contains "items") { return @($parsed.items) }
  return @($parsed)
}

function ConvertTo-FileUri {
  param([string]$PathValue)
  $full = [System.IO.Path]::GetFullPath($PathValue)
  return ([System.Uri]$full).AbsoluteUri -replace '^file:///', 'file://localhost/'
}

Assert-NoXDrive $XmlPath
Assert-NoXDrive $ManifestPath
if ($OutputXmlPath) { Assert-NoXDrive $OutputXmlPath }

if (-not (Test-Path -LiteralPath $XmlPath)) { throw "XML not found: $XmlPath" }
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }

$xmlResolved = (Resolve-Path -LiteralPath $XmlPath).Path
if (-not $OutputXmlPath) { $OutputXmlPath = $xmlResolved }
if ((Test-Path -LiteralPath $OutputXmlPath) -and ($OutputXmlPath -ne $xmlResolved) -and -not $Force) {
  throw "Output XML exists. Use -Force to overwrite: $OutputXmlPath"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path (Split-Path -Parent $xmlResolved) ("{0}.backup_before_manifest_relink_{1}{2}" -f [System.IO.Path]::GetFileNameWithoutExtension($xmlResolved), $timestamp, [System.IO.Path]::GetExtension($xmlResolved))
Copy-Item -LiteralPath $xmlResolved -Destination $backupPath -Force

$items = @(Get-ManifestItems $ManifestPath)
$nameMap = @{}
foreach ($item in $items) {
  $source = [string]$item.source
  $output = [string]$item.output
  if (-not $source -or -not $output) { continue }
  Assert-NoXDrive $source
  Assert-NoXDrive $output
  $sourceName = [System.IO.Path]::GetFileName($source)
  $outputName = [System.IO.Path]::GetFileName($output)
  $nameMap[$sourceName] = [PSCustomObject]@{
    OutputName = $outputName
    OutputUri = ConvertTo-FileUri $output
  }
}

$doc = New-Object System.Xml.XmlDocument
$doc.PreserveWhitespace = $true
$doc.Load($xmlResolved)

$changedNames = 0
$changedPaths = 0
$changedSizes = 0

foreach ($nameNode in $doc.SelectNodes('//name')) {
  $text = $nameNode.InnerText
  if ($nameMap.ContainsKey($text)) {
    $nameNode.InnerText = $nameMap[$text].OutputName
    $changedNames++
  }
}

foreach ($pathNode in $doc.SelectNodes('//pathurl')) {
  $text = $pathNode.InnerText
  foreach ($sourceName in $nameMap.Keys) {
    if ($text -like "*$sourceName") {
      $pathNode.InnerText = $nameMap[$sourceName].OutputUri
      $changedPaths++
      break
    }
  }
}

foreach ($fileNode in $doc.SelectNodes('//file')) {
  $idAttr = $fileNode.Attributes['id']
  if ($idAttr -and $idAttr.Value -like '*-mp4') {
    $idAttr.Value = $idAttr.Value -replace '-mp4$', '-mov'
  }
}

foreach ($clipNode in $doc.SelectNodes('//clipitem')) {
  $idAttr = $clipNode.Attributes['id']
  if ($idAttr -and $idAttr.Value -like '*-mp4') {
    $idAttr.Value = $idAttr.Value -replace '-mp4$', '-mov'
  }
}

foreach ($widthNode in $doc.SelectNodes('/xmeml/sequence/media/video/format/samplecharacteristics/width')) {
  if ($widthNode.InnerText -ne [string]$Width) {
    $widthNode.InnerText = [string]$Width
    $changedSizes++
  }
}

foreach ($heightNode in $doc.SelectNodes('/xmeml/sequence/media/video/format/samplecharacteristics/height')) {
  if ($heightNode.InnerText -ne [string]$Height) {
    $heightNode.InnerText = [string]$Height
    $changedSizes++
  }
}

$doc.Save($OutputXmlPath)

Write-Host "Backup: $backupPath"
Write-Host "Wrote XML: $OutputXmlPath"
Write-Host "Changed names: $changedNames"
Write-Host "Changed paths: $changedPaths"
Write-Host "Changed sequence size fields: $changedSizes"
if ($changedPaths -eq 0) {
  Write-Warning "No pathurl nodes were changed. Check whether the XML already points to the manifest outputs."
}
