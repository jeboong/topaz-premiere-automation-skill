[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$ProjectPath,
  [Parameter(Mandatory = $true)] [string]$ManifestPath,
  [string]$OutputProjectPath,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

function ConvertFrom-GzipBytes {
  param([byte[]]$Bytes)
  $inputStream = New-Object System.IO.MemoryStream(,$Bytes)
  $gzip = New-Object System.IO.Compression.GZipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
  $outputStream = New-Object System.IO.MemoryStream
  $gzip.CopyTo($outputStream)
  $gzip.Dispose()
  $inputStream.Dispose()
  return $outputStream.ToArray()
}

function ConvertTo-GzipBytes {
  param([byte[]]$Bytes)
  $outputStream = New-Object System.IO.MemoryStream
  $gzip = New-Object System.IO.Compression.GZipStream($outputStream, [System.IO.Compression.CompressionMode]::Compress)
  $gzip.Write($Bytes, 0, $Bytes.Length)
  $gzip.Dispose()
  return $outputStream.ToArray()
}

function Read-PremiereProjectText {
  param([string]$PathValue)
  $bytes = [System.IO.File]::ReadAllBytes($PathValue)
  $isGzip = ($bytes.Length -ge 2 -and $bytes[0] -eq 0x1f -and $bytes[1] -eq 0x8b)
  if ($isGzip) { $bytes = ConvertFrom-GzipBytes $bytes }
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  return [PSCustomObject]@{ Text = $text; IsGzip = $isGzip }
}

function Write-PremiereProjectText {
  param([string]$PathValue, [string]$Text, [bool]$AsGzip)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  if ($AsGzip) { $bytes = ConvertTo-GzipBytes $bytes }
  [System.IO.File]::WriteAllBytes($PathValue, $bytes)
}

function Escape-XmlText {
  param([string]$Value)
  return [System.Security.SecurityElement]::Escape($Value)
}

function Get-PathVariants {
  param([string]$PathValue)
  $full = [System.IO.Path]::GetFullPath($PathValue)
  $slash = $full -replace '\\', '/'
  $uri = ([System.Uri]$full).AbsoluteUri
  $uriLocal = $uri -replace '^file:///', 'file://localhost/'
  $leaf = [System.IO.Path]::GetFileName($full)

  $values = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($full, $slash, $uri, $uriLocal, $leaf)) {
    if ($value -and -not $values.Contains($value)) { $values.Add($value) }
    $escaped = Escape-XmlText $value
    if ($escaped -and -not $values.Contains($escaped)) { $values.Add($escaped) }
  }
  return @($values)
}

function Get-ManifestItems {
  param([string]$PathValue)
  $raw = Get-Content -LiteralPath $PathValue -Raw
  $parsed = $raw | ConvertFrom-Json
  if ($parsed.PSObject.Properties.Name -contains "items") { return @($parsed.items) }
  return @($parsed)
}

Assert-NoXDrive $ProjectPath
Assert-NoXDrive $ManifestPath
if ($OutputProjectPath) { Assert-NoXDrive $OutputProjectPath }

if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "Project not found: $ProjectPath" }
if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Manifest not found: $ManifestPath" }

$projectResolved = (Resolve-Path -LiteralPath $ProjectPath).Path
if (-not $OutputProjectPath) { $OutputProjectPath = $projectResolved }

if ((Test-Path -LiteralPath $OutputProjectPath) -and ($OutputProjectPath -ne $projectResolved) -and -not $Force) {
  throw "Output project exists. Use -Force to overwrite: $OutputProjectPath"
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path (Split-Path -Parent $projectResolved) ("{0}.backup_before_relink_{1}{2}" -f [System.IO.Path]::GetFileNameWithoutExtension($projectResolved), $timestamp, [System.IO.Path]::GetExtension($projectResolved))
Copy-Item -LiteralPath $projectResolved -Destination $backupPath -Force

$project = Read-PremiereProjectText $projectResolved
$text = $project.Text
$items = @(Get-ManifestItems $ManifestPath)
$report = @()

foreach ($item in $items) {
  $source = [string]$item.source
  $output = [string]$item.output
  if (-not $source -or -not $output) { continue }
  Assert-NoXDrive $source
  Assert-NoXDrive $output

  $oldVariants = Get-PathVariants $source
  $newVariants = Get-PathVariants $output
  $replacements = 0

  for ($i = 0; $i -lt $oldVariants.Count; $i++) {
    $old = $oldVariants[$i]
    $new = $newVariants[[Math]::Min($i, $newVariants.Count - 1)]
    if ($old -and $new -and $text.Contains($old)) {
      $before = $text.Length
      $text = $text.Replace($old, $new)
      if ($text.Length -ne $before -or -not $text.Contains($old)) { $replacements++ }
    }
  }

  $report += [PSCustomObject]@{
    source = $source
    output = $output
    replacements = $replacements
  }
}

Write-PremiereProjectText $OutputProjectPath $text $project.IsGzip

$reportPath = Join-Path (Split-Path -Parent $OutputProjectPath) ("relink_report_{0}.json" -f $timestamp)
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$missing = @($report | Where-Object { $_.replacements -eq 0 })
Write-Host "Backup: $backupPath"
Write-Host "Wrote project: $OutputProjectPath"
Write-Host "Relink report: $reportPath"
Write-Host "Items: $($report.Count), no replacement found: $($missing.Count)"
if ($missing.Count -gt 0) {
  Write-Warning "Some manifest sources were not found in the project. Inspect the relink report before trusting the project."
}
