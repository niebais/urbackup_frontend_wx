<#
.SYNOPSIS
  Builds Guardian Backup Client for Windows: the unmodified UrBackup client
  backend at a pinned upstream tag plus this (modified) frontend, packaged by
  urbackup.nsi as "Guardian Backup Client <version>.exe".

.DESCRIPTION
  This script is part of the Corresponding Source of Guardian Backup Client
  (AGPL-3.0-or-later): together with this repository at the built tag and the
  upstream backend at -BackendTag, it is everything needed to rebuild the
  installer.

  Steps
    1. Checks: -Version is "<x.y.z>-gp<n>", this repository has no
       uncommitted changes, the build tools exist.
    2. A fresh work dir: the backend (git clone of -BackendTag, or the
       -BackendSource tarball/folder), with this repository's committed tree
       (git archive HEAD) as its client\ folder.
    3. Version placeholders filled locally ($version_short$ = -Version,
       $version_full_numeric$ = x.y.z.n). Upstream's
       build\replace_versions.py is NOT used: it asks upstream's build server.
    4. Backend: build_client_backend.bat (Win32, x64, ARM64 + the service).
    5. Frontend: UrBackupClientGUI.sln (Win32, x64, ARM64), update_data.bat.
    6. NSIS: urbackup.nsi only (the tray installer; no NoTray, no MSI).
    7. Out dir: the installer, the frontend source tarball (git archive of
       HEAD), build-info.json and SHA256SUMS.

  Nothing is signed here; sign the installer with the publisher's own
  identity afterwards (upstream's SIGN switch uses upstream's certificate).

  -PrepareOnly stops after step 3 (no Windows tools needed; runs under pwsh on
  Linux too) so the source preparation can be checked anywhere.

.EXAMPLE
  pwsh branding\build_windows.ps1 -Version 2.5.32-gp1 -OutDir C:\out
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$BackendTag = '2.5.32client',
  [string]$BackendRepo = 'https://github.com/uroni/urbackup_backend.git',
  [string]$BackendSource = '',
  [string]$WorkDir = '',
  [string]$OutDir = '',
  [string]$VsVars = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsamd64_x86.bat',
  [string]$MakeNsis = 'C:\Program Files (x86)\NSIS\makensis.exe',
  [switch]$PrepareOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail([string]$msg) { throw "build_windows: $msg" }

$Repo = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) { $WorkDir = Join-Path ([IO.Path]::GetTempPath()) "gbclient-$Version" }
if (-not $OutDir) { $OutDir = Join-Path $Repo "dist\$Version" }

# 1. checks --------------------------------------------------------------
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)-gp([1-9]\d*)$') { Fail "-Version must look like 2.5.32-gp1, got '$Version'" }
$FullNumeric = "$($Matches[1]).$($Matches[2]).$($Matches[3]).$($Matches[4])"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is required' }
$dirty = & git -C $Repo status --porcelain --untracked-files=no
if ($LASTEXITCODE -ne 0) { Fail "$Repo is not a git repository" }
if ($dirty) { Fail "uncommitted changes in $Repo; the build must match a commit (it is the published source)" }
$FrontCommit = (& git -C $Repo rev-parse HEAD).Trim()
$FrontDescribe = (& git -C $Repo describe --tags --always HEAD).Trim()
if (-not $PrepareOnly) {
  foreach ($t in @($VsVars, $MakeNsis)) { if (-not (Test-Path -LiteralPath $t)) { Fail "missing build tool: $t" } }
}
if (Test-Path -LiteralPath $WorkDir) { Fail "work dir $WorkDir exists; use a fresh one" }
New-Item -ItemType Directory -Force -Path $WorkDir, $OutDir | Out-Null
$Backend = Join-Path $WorkDir 'backend'

# 2. sources -------------------------------------------------------------
if ($BackendSource) {
  if (Test-Path -LiteralPath $BackendSource -PathType Container) {
    Copy-Item -Recurse -LiteralPath $BackendSource -Destination $Backend
  } else {
    $x = Join-Path $WorkDir 'backend-src'
    New-Item -ItemType Directory -Path $x | Out-Null
    & tar -xzf $BackendSource -C $x
    if ($LASTEXITCODE -ne 0) { Fail "cannot unpack $BackendSource" }
    $top = @(Get-ChildItem -LiteralPath $x -Directory)
    if ($top.Count -ne 1) { Fail "$BackendSource must hold one top-level folder" }
    Move-Item -LiteralPath $top[0].FullName -Destination $Backend
  }
  $BackendCommit = "source:$([IO.Path]::GetFileName($BackendSource))"
} else {
  & git clone --quiet --depth 1 --branch $BackendTag $BackendRepo $Backend
  if ($LASTEXITCODE -ne 0) { Fail "cannot clone $BackendRepo at $BackendTag" }
  $BackendCommit = (& git -C $Backend rev-parse HEAD).Trim()
}
$Client = Join-Path $Backend 'client'
if (Test-Path -LiteralPath $Client) { Remove-Item -Recurse -Force -LiteralPath $Client }
New-Item -ItemType Directory -Path $Client | Out-Null
$archive = Join-Path $WorkDir 'frontend.tar'
& git -C $Repo archive --format=tar -o $archive HEAD
if ($LASTEXITCODE -ne 0) { Fail 'git archive failed' }
& tar -xf $archive -C $Client
if ($LASTEXITCODE -ne 0) { Fail 'cannot unpack the frontend' }

# 3. version placeholders (byte-exact: line endings and BOMs are kept) ----
$Latin1 = [Text.Encoding]::GetEncoding(28591)
function Set-Placeholder([string]$rel, [hashtable]$map) {
  $p = Join-Path $Backend $rel
  if (-not (Test-Path -LiteralPath $p)) { return $false }
  $s = $Latin1.GetString([IO.File]::ReadAllBytes($p))
  $o = $s
  foreach ($k in $map.Keys) { $s = $s.Replace($k, $map[$k]) }
  if ($s -ne $o) { [IO.File]::WriteAllBytes($p, $Latin1.GetBytes($s)) }
  return ($s -ne $o)
}
$map = @{ '$version_short$' = $Version; '$version_full_numeric$' = $FullNumeric }
$files = @('client_version.h', 'clientctl\main.cpp', 'client\urbackup.nsi', 'client\urbackup_update.nsi',
  'client\urbackup_notray.nsi', 'client\build_msi.bat', 'client\build_client.bat', 'client\urbackup.wxs')
$changed = @($files | Where-Object { Set-Placeholder ($_ -replace '\\', [IO.Path]::DirectorySeparatorChar) $map })
foreach ($must in @('client_version.h', 'client\urbackup.nsi')) {
  if ($changed -notcontains $must) { Fail "no version placeholder replaced in $must (wrong backend or frontend tree?)" }
}
$vfile = Join-Path $Client 'version.txt'
if (Test-Path -LiteralPath $vfile) {
  $vnum = (Get-Content -LiteralPath $vfile -Raw).Trim()
  [void](Set-Placeholder ('client\data\version_info.txt' -replace '\\', [IO.Path]::DirectorySeparatorChar) @{ '$version$' = $vnum })
}
$left = Select-String -LiteralPath (Join-Path $Client 'urbackup.nsi') -Pattern '\$version_' -SimpleMatch:$false
if ($left) { Fail "urbackup.nsi still has version placeholders: $($left[0].Line)" }

$info = [ordered]@{
  product          = 'Guardian Backup Client'
  version          = $Version
  version_numeric  = $FullNumeric
  backend_repo     = $BackendRepo
  backend_tag      = $BackendTag
  backend_commit   = $BackendCommit
  frontend_commit  = $FrontCommit
  frontend_describe = $FrontDescribe
  prepared_at      = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
if ($PrepareOnly) {
  $info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'build-info.json') -Encoding utf8
  Write-Host "prepared $Backend (frontend $FrontDescribe, version $Version); -PrepareOnly: not building"
  return
}

# 4-6. build ---------------------------------------------------------------
function Invoke-Cmd([string]$dir, [string]$line) {
  & cmd.exe /d /c "call `"$VsVars`" >nul && cd /d `"$dir`" && $line"
  if ($LASTEXITCODE -ne 0) { Fail "failed in ${dir}: $line (exit $LASTEXITCODE)" }
}
Invoke-Cmd $Backend 'call build_client_backend.bat'
foreach ($plat in @('Win32', 'x64', 'ARM64')) {
  Invoke-Cmd $Client "msbuild UrBackupClientGUI.sln /m /p:Configuration=Release /p:Platform=`"$plat`""
}
Invoke-Cmd $Client 'call update_data.bat'
& $MakeNsis (Join-Path $Client 'urbackup.nsi')
if ($LASTEXITCODE -ne 0) { Fail "makensis failed (exit $LASTEXITCODE)" }

# 7. outputs -------------------------------------------------------------
$name = "Guardian Backup Client $Version.exe"
$inst = Join-Path $Client $name
if (-not (Test-Path -LiteralPath $inst)) { Fail "NSIS did not produce '$name'" }
Copy-Item -LiteralPath $inst -Destination (Join-Path $OutDir $name)
$tag = $FrontDescribe -replace '[^0-9A-Za-z._+-]', '_'
$srcName = "urbackup_frontend_wx-$tag.tar.gz"
& git -C $Repo archive --format=tar.gz --prefix="urbackup_frontend_wx-$tag/" -o (Join-Path $OutDir $srcName) HEAD
if ($LASTEXITCODE -ne 0) { Fail 'cannot write the source tarball' }
$sums = foreach ($f in @($name, $srcName)) {
  "$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $OutDir $f)).Hash.ToLowerInvariant())  $f"
}
$sums | Set-Content -LiteralPath (Join-Path $OutDir 'SHA256SUMS') -Encoding ascii
$info['installer'] = $name
$info['installer_sha256'] = ($sums[0] -split '  ')[0]
$info['source_tarball'] = $srcName
$info['source_tarball_sha256'] = ($sums[1] -split '  ')[0]
$info | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'build-info.json') -Encoding utf8
Write-Host "built $name"
Write-Host ($sums -join "`n")
Write-Host 'next: sign the installer, publish the source tarball on the fork tag, then gbrelease build --urbackup-tray guardian'
