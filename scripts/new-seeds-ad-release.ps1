param(
  [string]$SourceHtml = 'files/recursive_vision_v9_deploy.html',
  [string]$OutputDir = 'files',
  [string]$VariantName = 'seeds-vision',
  [string]$OutputName = '',
  [string]$PublisherId = 'ca-pub-8263634312399744',
  [string]$SlotA = '8077959277',
  [string]$SlotB = '1561704738',
  [bool]$EnableAds = $true,
  [switch]$RunDeploy,
  [string]$Alias = '',
  [string]$VercelConfig = 'vercel.json',
  [bool]$SetIndexAsEntry = $true
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot $SourceHtml
if (!(Test-Path $sourcePath)) {
  throw "Source file not found: $SourceHtml"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = '.'
}

$outDir = Join-Path $repoRoot $OutputDir
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$slug = ($VariantName -replace '[^a-zA-Z0-9]+', '-').ToLower()
if ([string]::IsNullOrWhiteSpace($slug)) {
  $slug = 'seeds-vision'
}
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

if ([string]::IsNullOrWhiteSpace($OutputName)) {
  $OutputName = "$slug-$timestamp.html"
} elseif (![IO.Path]::GetExtension($OutputName)) {
  $OutputName = "$OutputName.html"
}

$targetRelPath = Join-Path $OutputDir $OutputName
$targetPath = Join-Path $repoRoot $targetRelPath

$raw = Get-Content -Raw $sourcePath
$adSlotA = ($SlotA -replace '\D').Trim()
$adSlotB = ($SlotB -replace '\D').Trim()
if ([string]::IsNullOrWhiteSpace($adSlotA)) {
  $adSlotA = $adSlotB
}
if ([string]::IsNullOrWhiteSpace($adSlotB)) {
  $adSlotB = ''
}
if ([string]::IsNullOrWhiteSpace($adSlotA)) {
  throw 'At least one ad slot id is required.'
}

$pub = ($PublisherId -replace '\s').Trim()
if (-not $pub.StartsWith('ca-pub-')) {
  Write-Warning "Publisher ID does not match ca-pub-... pattern: $pub"
}
$enabledLiteral = if ($EnableAds) { 'true' } else { 'false' }
$replacement = @"
const DEFAULT_AD_CONFIG = {
  enabled: $enabledLiteral,
  clientId: '$pub',
  slotId: '$adSlotA',
  slotIdLeaderboard: '$adSlotA',
  slotIdRect: '$adSlotB',
  responsive: true
};
"@

$configPattern = '(?s)const DEFAULT_AD_CONFIG = \{.*?\};'
$updated = [regex]::Replace(
  $raw,
  $configPattern,
  $replacement,
  1
)

if (-not [regex]::IsMatch($raw, $configPattern)) {
  throw 'Failed to locate DEFAULT_AD_CONFIG block in source HTML.'
}

Set-Content -Path $targetPath -Value $updated -Encoding utf8
Write-Host "Created: $targetRelPath"

if (-not $RunDeploy) {
  Write-Host 'RunDeploy=false: only HTML prepared.'
  return
}

if ([string]::IsNullOrWhiteSpace($Alias)) {
  $Alias = "aro-$slug"
}

  if ($SetIndexAsEntry) {
  $configPath = Join-Path $repoRoot $VercelConfig
  if (!(Test-Path $configPath)) {
    throw "Vercel config not found: $VercelConfig"
  }

  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($null -eq $config.rewrites) {
    $config | Add-Member -NotePropertyName rewrites -NotePropertyValue @()
  }

  $rewriteTarget = "/" + (($targetRelPath -replace '\\', '/') -replace '^\./', '' -replace '^/', '')

  $updatedRewrite = $false
  for ($i = 0; $i -lt $config.rewrites.Count; $i++) {
    if ($config.rewrites[$i].source -eq '/') {
      $config.rewrites[$i].destination = $rewriteTarget
      $updatedRewrite = $true
      break
    }
  }

  if (-not $updatedRewrite) {
    $newRewrite = [ordered]@{ source = '/'; destination = $rewriteTarget }
    $config.rewrites = ,([PSCustomObject]$newRewrite) + $config.rewrites
  }

  $config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding utf8
  Write-Host "Updated entry route in $VercelConfig to $rewriteTarget"
}

if ($RunDeploy) {
  # Keep security headers aligned to the generated entry file as well.
  $configPath = Join-Path $repoRoot $VercelConfig
  if (!(Test-Path $configPath)) {
    throw "Vercel config not found: $VercelConfig"
  }

  $config = Get-Content -Raw $configPath | ConvertFrom-Json
  if ($null -eq $config.headers) {
    $config | Add-Member -NotePropertyName headers -NotePropertyValue @()
  }

  $sourcePosix = ($SourceHtml -replace '^\\', '') -replace '^\.\/', '' -replace '\\', '/'
  $sourcePosix = "/$sourcePosix".TrimStart('/')
  $targetPosix = ($targetRelPath -replace '^\\', '') -replace '^\.\/', '' -replace '\\', '/'
  $targetPosix = "/$targetPosix".TrimStart('/')

  $sourceHeader = $config.headers | Where-Object { $_.source -eq "/$sourcePosix" } | Select-Object -First 1
  $targetHeader = $config.headers | Where-Object { $_.source -eq "/$targetPosix" } | Select-Object -First 1

  if (-not $targetHeader) {
    if (-not $sourceHeader -and $config.headers.Count -gt 0) {
      $sourceHeader = $config.headers[0]
    }

    $newHeader = [PSCustomObject]@{
      source = "/$targetPosix"
      headers = if ($sourceHeader) { $sourceHeader.headers } else {
        @(
          [PSCustomObject]@{ key = 'X-Frame-Options'; value = 'DENY' },
          [PSCustomObject]@{ key = 'Referrer-Policy'; value = 'no-referrer' },
          [PSCustomObject]@{ key = 'Permissions-Policy'; value = 'geolocation=(), microphone=(), camera=()' },
          [PSCustomObject]@{
            key = 'Content-Security-Policy'
            value = "default-src 'self'; img-src 'self' data: blob: https://pagead2.googlesyndication.com https://tpc.googlesyndication.com https://googleads.g.doubleclick.net; connect-src 'self' https://generativelanguage.googleapis.com https://pagead2.googlesyndication.com https://tpc.googlesyndication.com https://googleads.g.doubleclick.net; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://pagead2.googlesyndication.com; frame-src 'self' https://tpc.googlesyndication.com https://googleads.g.doubleclick.net; object-src 'none';"
          }
        )
      }
    }
    $config.headers = @($newHeader) + @($config.headers | Where-Object { $_.source -ne "/$sourcePosix" })
    Write-Host "Updated header mapping in $VercelConfig to /$targetPosix"
  }

  $config | ConvertTo-Json -Depth 20 | Set-Content -Path $configPath -Encoding utf8
}

Push-Location $repoRoot
try {
  Write-Host "Deploying from: $repoRoot"
  $output = & npx -y vercel@latest --prod --yes 2>&1 | Out-String
  Write-Host $output

  $prodUrl = ''
  foreach ($line in ($output -split "`r?`n")) {
    if ($line -match 'https://[^"\s]+\.vercel\.app[^"\s]*') {
      $prodUrl = $Matches[0]
      break
    }
  }

  if ($prodUrl) {
    Write-Host "Deploy URL: $prodUrl"

    if ($Alias) {
      $aliasTarget = $Alias.Trim()
      if (-not [string]::IsNullOrWhiteSpace($aliasTarget)) {
        if ($aliasTarget -notmatch '^https?://') {
          $aliasTarget = if ($aliasTarget -like '*.vercel.app') { $aliasTarget } else { "${aliasTarget}.vercel.app" }
          Write-Host "Alias target normalized to: $aliasTarget"
        }
        Write-Host "Setting alias: $prodUrl -> $aliasTarget"
        & npx -y vercel@latest alias set $prodUrl $aliasTarget
      }
    }
  }
  else {
    Write-Host 'Deploy succeeded, but URL extraction failed. Check the log above.'
  }
}
finally {
  Pop-Location
}
