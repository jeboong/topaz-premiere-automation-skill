[CmdletBinding()]
param(
  [string]$ModelDir = "$env:ProgramData\Topaz Labs LLC\Topaz Video\models",
  [string]$EntryPath,
  [switch]$WhatIfOnly
)

$ErrorActionPreference = "Stop"

function Assert-NoXDrive {
  param([string]$PathValue)
  if ($PathValue -match '^[Xx]:\\') { throw "Refusing to access X drive: $PathValue" }
}

Assert-NoXDrive $ModelDir

if (-not $EntryPath) {
  $skillRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
  $EntryPath = Join-Path $skillRoot "assets\prores-4444-encoder-entry.json"
}

Assert-NoXDrive $EntryPath

$encoderPath = Join-Path $ModelDir "video-encoders.json"
if (-not (Test-Path -LiteralPath $encoderPath)) { throw "video-encoders.json not found: $encoderPath" }
if (-not (Test-Path -LiteralPath $EntryPath)) { throw "Entry JSON not found: $EntryPath" }

$encoders = @(Get-Content -LiteralPath $encoderPath -Raw | ConvertFrom-Json)
$entry = Get-Content -LiteralPath $EntryPath -Raw | ConvertFrom-Json

if ($encoders | Where-Object { $_.id -eq $entry.id }) {
  Write-Host "Encoder already present: $($entry.id)"
  return
}

$updated = New-Object System.Collections.Generic.List[object]
$inserted = $false
foreach ($encoder in $encoders) {
  $updated.Add($encoder)
  if (-not $inserted -and $encoder.id -eq "prores-422-hq-win") {
    $updated.Add($entry)
    $inserted = $true
  }
}
if (-not $inserted) { $updated.Add($entry) }

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path $ModelDir "video-encoders.backup_before_prores4444_$timestamp.json"
$json = $updated | ConvertTo-Json -Depth 20

Write-Host "Encoder config: $encoderPath"
Write-Host "Backup path: $backupPath"
Write-Host "Adding encoder: $($entry.id)"

if ($WhatIfOnly) {
  Write-Host "WhatIfOnly set; no files written."
  return
}

try {
  Copy-Item -LiteralPath $encoderPath -Destination $backupPath -Force
  Set-Content -LiteralPath $encoderPath -Value $json -Encoding UTF8
  Write-Host "Updated Topaz encoder config. Restart Topaz Video before checking the UI."
} catch {
  $fallback = Join-Path (Get-Location).Path "video-encoders.with-prores4444-win.json"
  Set-Content -LiteralPath $fallback -Value $json -Encoding UTF8
  Write-Warning "Could not write ProgramData config, likely due to permissions: $($_.Exception.Message)"
  Write-Warning "Wrote patched config here instead: $fallback"
  Write-Warning "Run PowerShell as Administrator or copy this file over $encoderPath after backing up the original."
}
