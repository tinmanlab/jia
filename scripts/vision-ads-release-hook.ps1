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
  [bool]$SetIndexAsEntry = $true,
  [bool]$RunPreflight = $true,
  [bool]$FailOnWarning = $false,
  [bool]$VerifyDeployed = $true,
  [bool]$RequireCleanProgress = $false,
  [string]$ProgressFile = '',
  [string]$ExpectedUrl = '',
  [bool]$PruneAliases = $true,
  [string]$AliasCleanupPrefix = '',
  [string]$Command = 'deploy',
  [string]$Intent = '',
  [bool]$Strict = $false,
  [bool]$AutoOpen = $false
)

$ErrorActionPreference = 'Stop'

$explicitRunDeploy = $PSBoundParameters.ContainsKey('RunDeploy')
$explicitRunPreflight = $PSBoundParameters.ContainsKey('RunPreflight')
$explicitVerifyDeployed = $PSBoundParameters.ContainsKey('VerifyDeployed')
$explicitFailOnWarning = $PSBoundParameters.ContainsKey('FailOnWarning')
$explicitRequireCleanProgress = $PSBoundParameters.ContainsKey('RequireCleanProgress')
$explicitPruneAliases = $PSBoundParameters.ContainsKey('PruneAliases')
$explicitAliasCleanupPrefix = $PSBoundParameters.ContainsKey('AliasCleanupPrefix')
$explicitAlias = $PSBoundParameters.ContainsKey('Alias')
$explicitExpectedUrl = $PSBoundParameters.ContainsKey('ExpectedUrl')

function Resolve-IntentToCommand {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
  }

  $normalized = ($Text.ToLowerInvariant() -replace '[^a-z0-9가-힣\s]', ' ')
  if ($normalized -match 'status|상태|별칭|alias|현황|확인|조회') {
    return 'status'
  }
  if ($normalized -match 'help|도움|도와줘|사용법|guide|usage|방법') {
    return 'help'
  }
  if ($normalized -match '미리보기|미리|preview|test|테스트|점검|샌드박스|프리뷰') {
    return 'preview'
  }
  if ($normalized -match '실행|진행|배포실행|돌리|돌려|run') {
    return 'deploy'
  }
  if ($normalized -match '준비|사전검|사전\s*검사|생성|make|build|prepare|제작|build only|dry') {
    return 'prepare'
  }
  if ($normalized -match '배포|deploy|운영|프로덕션|올리|publish|릴리즈|출시|go live|golive') {
    return 'deploy'
  }

  return $null
}

$resolvedFromIntent = Resolve-IntentToCommand -Text $Intent
if (-not $resolvedFromIntent) {
  $resolvedFromIntent = Resolve-IntentToCommand -Text $Command
}
if ($resolvedFromIntent) {
  $Command = $resolvedFromIntent
}

switch ($Command.ToLowerInvariant()) {
  'prepare' { }
  'deploy' { }
  'preview' { }
  'status' { }
  'help' { }
  default {
    throw "Unsupported command: $Command. Use prepare|deploy|preview|status|help."
  }
}

function Show-HookUsage {
  @'
Usage:
  pwsh .\scripts\vision-ads-release-hook.ps1 [-Command <prepare|deploy|preview|status|help>] [options...]

Commands:
  prepare   - Run preflight checks and generate HTML only.
  deploy    - Run checks + production deploy to aro-vision (default).
  preview   - Run checks + deploy to a preview alias.
  status    - Show current Vercel alias mapping.
  help     - Show usage.
'@ | Write-Host

  Write-Host ''
  Write-Host 'Intent shortcuts examples:'
  Write-Host "  -Intent '진행' / '배포해줘' => deploy"
  Write-Host "  -Intent '사전검사만' / '준비' => prepare"
  Write-Host "  -Intent '미리보기' => preview"
  Write-Host "  -Intent '현재상태' / '별칭' => status"
  Write-Host "  -Intent '도움' => help"
  Write-Host ''
  Write-Host 'Strict mode: -Strict true blocks warnings and requires clean progress.'
  Write-Host 'AutoOpen: -AutoOpen true opens expected URL after successful deploy.'
}

function Ensure-VercelAuth {
  Write-Host 'Validating Vercel login...'
  $who = & npx -y vercel@latest whoami 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($who)) {
    Add-Check -Name 'Vercel authentication' -Status 'FAIL' -Message 'Vercel session is not authenticated. Run `npx -y vercel@latest login` in this environment.'
    throw 'Vercel login is required for deploy.'
  }
  Add-Check -Name 'Vercel authentication' -Status 'PASS' -Message ($who -replace "`r?`n", ' ').Trim()
}

function Validate-GeneratedHtml {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    Add-Check -Name 'Generated HTML integrity' -Status 'FAIL' -Message "Generated file missing: $Path"
    return
  }

  $content = Get-Content -Raw $Path
  if (Has-StringMatch $content 'DEFAULT_AD_CONFIG') {
    Add-Check -Name 'Generated HTML integrity' -Status 'PASS' -Message 'DEFAULT_AD_CONFIG block exists.'
  } else {
    Add-Check -Name 'Generated HTML integrity' -Status 'FAIL' -Message 'Missing DEFAULT_AD_CONFIG block.'
    return
  }

  if ($EnableAds -and $normalizedPublisherId) {
    if (Has-StringMatch $content [regex]::Escape($normalizedPublisherId)) {
      Add-Check -Name 'Generated ad config' -Status 'PASS' -Message "Publisher ID injected: $normalizedPublisherId"
    } else {
      Add-Check -Name 'Generated ad config' -Status 'FAIL' -Message 'Publisher ID not found in output.'
    }
  }
  if ($normalizedSlotA) {
    if (Has-StringMatch $content [regex]::Escape($normalizedSlotA)) {
      Add-Check -Name 'Generated ad config' -Status 'PASS' -Message "SlotA injected: $normalizedSlotA"
    } else {
      Add-Check -Name 'Generated ad config' -Status 'WARN' -Message "SlotA not found in output: $normalizedSlotA"
    }
  }
  if ($normalizedSlotB) {
    if (Has-StringMatch $content [regex]::Escape($normalizedSlotB)) {
      Add-Check -Name 'Generated ad config' -Status 'PASS' -Message "SlotB injected: $normalizedSlotB"
    } else {
      Add-Check -Name 'Generated ad config' -Status 'WARN' -Message "SlotB not found in output: $normalizedSlotB"
    }
  }
}

function Open-UrlIfRequested {
  param([string]$Url)

  if ([string]::IsNullOrWhiteSpace($Url)) {
    return
  }

  try {
    Start-Process $Url | Out-Null
  } catch {
    Add-Check -Name 'AutoOpen' -Status 'WARN' -Message "Failed to open URL automatically: $($_.Exception.Message)"
  }
}

function Configure-Command {
  param([string]$Mode)

  switch ($Mode.ToLowerInvariant()) {
    'prepare' {
      if (-not $explicitRunPreflight) { $script:RunPreflight = $true }
      if (-not $explicitRunDeploy) { $script:RunDeploy = $false }
      if (-not $explicitPruneAliases) { $script:PruneAliases = $false }
      if (-not $explicitAlias) { $script:Alias = '' }
      if (-not $explicitAliasCleanupPrefix) { $script:AliasCleanupPrefix = '' }
      $script:VerifyDeployed = $false
    }
    'deploy' {
      if (-not $explicitRunPreflight) { $script:RunPreflight = $true }
      if (-not $explicitRunDeploy) { $script:RunDeploy = $true }
      if (-not $explicitPruneAliases) { $script:PruneAliases = $true }
      if (-not $explicitAlias) { $script:Alias = 'aro-vision' }
      if (-not $explicitAliasCleanupPrefix) { $script:AliasCleanupPrefix = 'aro-vision' }
      if (-not $explicitExpectedUrl) { $script:ExpectedUrl = 'https://aro-vision.vercel.app' }
      if (-not $explicitVerifyDeployed) { $script:VerifyDeployed = $true }
      if ($Strict) {
        if (-not $explicitFailOnWarning) { $script:FailOnWarning = $true }
        if (-not $explicitRequireCleanProgress) { $script:RequireCleanProgress = $true }
      }
    }
    'preview' {
      if (-not $explicitRunPreflight) { $script:RunPreflight = $true }
      if (-not $explicitRunDeploy) { $script:RunDeploy = $true }
      if (-not $explicitPruneAliases) { $script:PruneAliases = $false }
      if (-not $explicitAlias) { $script:Alias = 'aro-vision-preview' }
      if (-not $explicitAliasCleanupPrefix) { $script:AliasCleanupPrefix = '' }
      if (-not $explicitExpectedUrl) {
        $previewAliasHost = if ($script:Alias -like '*://*') {
          ([uri]$script:Alias).Host
        } elseif ($script:Alias -like '*.vercel.app') {
          $script:Alias
        } else {
          "$($script:Alias).vercel.app"
        }
        $script:ExpectedUrl = "https://$previewAliasHost"
      }
      if (-not $explicitVerifyDeployed) { $script:VerifyDeployed = $true }
    }
    'status' { return }
    'help' { Show-HookUsage; exit 0 }
    default { throw "Unsupported command: $Mode" }
  }
}

Configure-Command -Mode $Command

if ($Command -eq 'status') {
  try {
    & npx -y vercel@latest alias ls
  }
  catch {
    throw "Failed to read alias list: $($_.Exception.Message)"
  }
  return
}

function Add-Check {
  param(
    [string]$Name,
    [string]$Status, # PASS, WARN, FAIL
    [string]$Message
  )

  $symbol = switch ($Status) {
    'PASS' { '[PASS]' }
    'WARN' { '[WARN]' }
    default { '[FAIL]' }
  }
  Write-Host "$symbol $Name => $Message"

  $script:checks += [pscustomobject]@{
    name = $Name
    status = $Status
    message = $Message
  }
}

function Remove-DeprecatedAliases {
  param(
    [string]$KeepAlias,
    [string]$Prefix
  )

  $aliasOutput = & npx -y vercel@latest alias ls 2>&1
  if ($LASTEXITCODE -ne 0) {
    Add-Check -Name 'Alias cleanup' -Status 'WARN' -Message 'Failed to list aliases for cleanup.'
    return
  }

  $entries = @()
  foreach ($line in ($aliasOutput -split "`r?`n")) {
    if ($line -match '^\s*(\S+)\s+(\S+\.vercel\.app)\s+') {
      $entries += [pscustomobject]@{ Source = $matches[1]; Alias = $matches[2] }
    }
  }

  $target = $entries | Where-Object { $_.Alias -eq $KeepAlias } | Select-Object -First 1
  if (-not $target) {
    Add-Check -Name 'Alias cleanup' -Status 'WARN' -Message "Keep alias not found: $KeepAlias"
    return
  }

  $targetSource = $target.Source
  $prefixPattern = if ([string]::IsNullOrWhiteSpace($Prefix)) { '' } else { $Prefix.Trim() }

  $toRemove = $entries | Where-Object {
    $_.Source -eq $targetSource -and $_.Alias -ne $KeepAlias -and (
      [string]::IsNullOrWhiteSpace($prefixPattern) -or $_.Alias -like "$prefixPattern*"
    )
  }

  if (-not $toRemove) {
    Add-Check -Name 'Alias cleanup' -Status 'PASS' -Message "No stale aliases found for source $targetSource."
    return
  }

  $removed = 0
  foreach ($entry in $toRemove) {
    Write-Host "Removing duplicate alias: $($entry.Alias)"
    $removeOutput = & npx -y vercel@latest alias rm $entry.Alias --yes 2>&1
    if ($LASTEXITCODE -eq 0) {
      $removed++
      Add-Check -Name 'Alias cleanup' -Status 'PASS' -Message "Removed stale alias: $($entry.Alias)"
    } else {
      Add-Check -Name 'Alias cleanup' -Status 'WARN' -Message "Failed to remove $($entry.Alias)"
      Write-Host $removeOutput
    }
  }

  if ($removed -eq 0) {
    Add-Check -Name 'Alias cleanup' -Status 'PASS' -Message "No stale aliases removed for source $targetSource."
  }
}


function Has-StringMatch {
  param(
    [string]$Text,
    [string]$Pattern
  )
  return [bool]($Text -match $Pattern)
}

function Normalize-Slug {
  param([string]$Value)
  $slug = ($Value -replace '[^a-zA-Z0-9]+', '-').ToLower()
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = 'seeds-vision' }
  return $slug
}

$checks = New-Object 'System.Collections.Generic.List[psobject]'
$repoRoot = Split-Path -Parent $PSScriptRoot
$slug = Normalize-Slug $VariantName
$sourcePath = Join-Path $repoRoot $SourceHtml
$outDir = Join-Path $repoRoot $OutputDir
$normalizedPublisherId = ($PublisherId -replace '\s').Trim().ToLower()
$adsTxtPublisherId = if ($normalizedPublisherId -like 'ca-pub-*') { $normalizedPublisherId -replace '^ca-', '' } else { $normalizedPublisherId }
$normalizedSlotA = ($SlotA -replace '\D').Trim()
$normalizedSlotB = ($SlotB -replace '\D').Trim()

if ([string]::IsNullOrWhiteSpace($OutputName)) {
  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $OutputName = "$slug-$timestamp.html"
} elseif (![IO.Path]::GetExtension($OutputName)) {
  $OutputName = "$OutputName.html"
}
$targetRelPath = Join-Path $OutputDir $OutputName
$targetPath = Join-Path $repoRoot $targetRelPath

if ($RunPreflight) {
  if (Test-Path $sourcePath) {
    Add-Check -Name 'Source HTML' -Status 'PASS' -Message "Found: $SourceHtml"
  } else {
    Add-Check -Name 'Source HTML' -Status 'FAIL' -Message "Missing: $SourceHtml"
  }

  if ([IO.Directory]::Exists($outDir)) {
    Add-Check -Name 'Output directory' -Status 'PASS' -Message "Ready: $OutputDir"
  } else {
    try {
      New-Item -ItemType Directory -Force -Path $outDir | Out-Null
      Add-Check -Name 'Output directory' -Status 'PASS' -Message "Created: $OutputDir"
    }
    catch {
      Add-Check -Name 'Output directory' -Status 'FAIL' -Message "Cannot create: $OutputDir"
    }
  }

  if ($normalizedSlotA) {
    Add-Check -Name 'Ad Slot A' -Status 'PASS' -Message "Numeric check: $normalizedSlotA"
  } else {
    Add-Check -Name 'Ad Slot A' -Status 'FAIL' -Message 'Missing or invalid slot id'
  }

  if (-not $normalizedSlotB) {
    Add-Check -Name 'Ad Slot B' -Status 'WARN' -Message 'Rect slot is empty (optional). Leaderboard/primary slot still used.'
  } else {
    Add-Check -Name 'Ad Slot B' -Status 'PASS' -Message "Numeric check: $normalizedSlotB"
  }

  if ($normalizedPublisherId -match '^ca-pub-\d{10,}$') {
    Add-Check -Name 'Publisher ID' -Status 'PASS' -Message $normalizedPublisherId
  } else {
    Add-Check -Name 'Publisher ID' -Status 'WARN' -Message "Unusual format: $normalizedPublisherId"
  }

  $raw = if (Test-Path $sourcePath) { Get-Content -Raw $sourcePath } else { '' }
  if (Has-StringMatch $raw 'const DEFAULT_AD_CONFIG\s*=\s*\{') {
    Add-Check -Name 'Template Ad Config' -Status 'PASS' -Message 'DEFAULT_AD_CONFIG block found'
  } else {
    Add-Check -Name 'Template Ad Config' -Status 'FAIL' -Message 'DEFAULT_AD_CONFIG block missing'
  }

  if (-not $EnableAds) {
    Add-Check -Name 'Ad Runtime' -Status 'PASS' -Message 'Ads disabled by argument'
  } elseif (Has-StringMatch $raw 'pagead2\.googlesyndication\.com/pagead/js/adsbygoogle\.js') {
    Add-Check -Name 'Ad Runtime' -Status 'PASS' -Message 'AdSense loader exists in template'
  } else {
    Add-Check -Name 'Ad Runtime' -Status 'FAIL' -Message 'AdSense loader not found in template'
  }

  $adsTxtPath = Join-Path $repoRoot 'ads.txt'
  if (Test-Path $adsTxtPath) {
    Add-Check -Name 'ads.txt' -Status 'PASS' -Message 'Found at project root'
    $adsTxtContent = (Get-Content -Raw $adsTxtPath).ToLower()
    $adsTxtCompact = $adsTxtContent -replace '\s', ''
    $idPresent = $adsTxtCompact.Contains($normalizedPublisherId) -or $adsTxtCompact.Contains($adsTxtPublisherId)
    if ($idPresent) {
      Add-Check -Name 'ads.txt Publisher' -Status 'PASS' -Message "Publisher ID included: $normalizedPublisherId"
    } else {
      $status = if ($RunDeploy) { 'FAIL' } else { 'WARN' }
      Add-Check -Name 'ads.txt Publisher' -Status $status -Message "Publisher ID not found in ads.txt ($normalizedPublisherId / $adsTxtPublisherId)"
    }
  } else {
    $status = if ($RunDeploy) { 'FAIL' } else { 'WARN' }
    Add-Check -Name 'ads.txt' -Status $status -Message 'Missing at project root'
  }

  @('privacy-policy.html','terms-of-service.html','contact.html') | ForEach-Object {
    if (Test-Path (Join-Path $repoRoot $_)) {
      Add-Check -Name "Legal page: $_" -Status 'PASS' -Message 'Present'
    } else {
      Add-Check -Name "Legal page: $_" -Status 'WARN' -Message 'Missing for policy compliance'
    }
  }

  if (Has-StringMatch $raw 'AIza[0-9A-Za-z\-_]{20,}') {
    Add-Check -Name 'API key exposure' -Status 'FAIL' -Message 'Potential hardcoded Google key-like token found'
  } else {
    Add-Check -Name 'API key exposure' -Status 'PASS' -Message 'No hardcoded Google key-like token found'
  }

  if ($RunDeploy) {
    $configPath = Join-Path $repoRoot $VercelConfig
    if (Test-Path $configPath) {
      Add-Check -Name 'Vercel config' -Status 'PASS' -Message "Found: $VercelConfig"
      try {
        $config = Get-Content -Raw $configPath | ConvertFrom-Json
        if ($config.rewrites -and ($config.rewrites | Where-Object { $_.source -eq '/' } | Select-Object -First 1)) {
          Add-Check -Name 'Rewrite rule' -Status 'PASS' -Message "Root rewrite exists"
        } else {
          Add-Check -Name 'Rewrite rule' -Status 'WARN' -Message 'Root rewrite not yet configured'
        }
      }
      catch {
        Add-Check -Name 'Vercel config' -Status 'FAIL' -Message 'JSON parse error'
      }
    } else {
      Add-Check -Name 'Vercel config' -Status 'FAIL' -Message "Missing: $VercelConfig"
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ProgressFile)) {
    $progressPath = if ([System.IO.Path]::IsPathRooted($ProgressFile)) { $ProgressFile } else { Join-Path $repoRoot $ProgressFile }
    if (Test-Path $progressPath) {
      $progressContent = Get-Content -Raw $progressPath
      $todoCount = ([regex]::Matches($progressContent, '(?m)^\s*-\s\[[\sXx]\]')).Count
      if ($todoCount -gt 0) {
        $status = if ($RequireCleanProgress) { 'FAIL' } else { 'WARN' }
        Add-Check -Name "Progress items: $progressPath" -Status $status -Message "Unchecked items: $todoCount"
      } else {
        Add-Check -Name "Progress items: $progressPath" -Status 'PASS' -Message 'No unchecked checklist items'
      }
    } else {
      Add-Check -Name "Progress items: $progressPath" -Status 'WARN' -Message 'Progress file not found'
    }
  }

  $failCount = ($checks | Where-Object { $_.status -eq 'FAIL' }).Count
  $warnCount = ($checks | Where-Object { $_.status -eq 'WARN' }).Count
  Write-Host "Preflight summary => PASS=$($checks.Count - $warnCount - $failCount), WARN=$warnCount, FAIL=$failCount"
  if ($failCount -gt 0) {
    throw "Preflight blocked deployment: $failCount fail checks."
  }
  if ($RunDeploy -and $FailOnWarning -and $warnCount -gt 0) {
    throw "Preflight blocked deployment by FailOnWarning: $warnCount warning checks."
  }
}

$releaseScript = Join-Path $PSScriptRoot 'new-seeds-ad-release.ps1'
if (!(Test-Path $releaseScript)) {
  throw "Release script not found: $releaseScript"
}

$releaseParams = @{
  SourceHtml     = $SourceHtml
  OutputDir      = $OutputDir
  VariantName    = $VariantName
  OutputName     = $OutputName
  PublisherId    = $normalizedPublisherId
  SlotA          = $normalizedSlotA
  SlotB          = $normalizedSlotB
  EnableAds      = $EnableAds
  RunDeploy      = $RunDeploy.IsPresent
  Alias         = $Alias
  VercelConfig   = $VercelConfig
  SetIndexAsEntry = $SetIndexAsEntry
}

if (-not (Test-Path (Split-Path -Parent $targetPath))) {
  throw "Output directory unavailable: $OutputDir"
}

Write-Host "Preflight passed. Running release..."
$releaseOutput = & $releaseScript @releaseParams 2>&1 | Out-String
Write-Host $releaseOutput
Validate-GeneratedHtml -Path $targetPath

if ($RunDeploy) {
  Ensure-VercelAuth

  if (-not $Alias) {
    $Alias = "aro-$slug"
  }
  $CanonicalAlias = if ($Alias -like '*://*') {
    ([uri]$Alias).Host
  } elseif ($Alias -like '*.vercel.app') {
    $Alias
  } else {
    "$Alias.vercel.app"
  }

  if (-not [string]::IsNullOrWhiteSpace($ExpectedUrl)) {
    $verifyUrl = $ExpectedUrl
  } else {
    $verifyUrl = if ($Alias -match '^https?://') { $Alias } else { "https://$Alias.vercel.app" }
  }

  if ($verifyUrl -and $VerifyDeployed) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -MaximumRedirection 5 -Uri $verifyUrl -TimeoutSec 20
      Add-Check -Name 'Post-deploy probe' -Status 'PASS' -Message "HTTP $($response.StatusCode) at $verifyUrl"
    }
    catch {
      Add-Check -Name 'Post-deploy probe' -Status 'WARN' -Message "HTTP probe failed: $($_.Exception.Message)"
    }
  }

  if ($PruneAliases) {
    Remove-DeprecatedAliases -KeepAlias $CanonicalAlias -Prefix $AliasCleanupPrefix
  }

  if ($AutoOpen -and $verifyUrl) {
    Open-UrlIfRequested -Url $verifyUrl
  }
}

Write-Host "Generated file: $targetRelPath"
if (Test-Path $targetPath) {
  Add-Check -Name 'Generated HTML' -Status 'PASS' -Message 'Output file exists'
} else {
  Add-Check -Name 'Generated HTML' -Status 'WARN' -Message "Not found at expected path: $targetRelPath"
}
