[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = ([IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION'))).Trim()

if ($version -match '-dev') {
    throw "Refusing to package a development version ($version). Set VERSION to a release version first."
}

# The release gate is the full repository checker.
$check = Join-Path $repoRoot 'tools\check.ps1'
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $checkOutput = (& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $check 2>&1 | Out-String).TrimEnd()
    $checkExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
Write-Output $checkOutput
if ($checkExit -ne 0) {
    throw 'Packaging refused: repository checks failed.'
}

$trackedChanges = @(git -C $repoRoot status --porcelain --untracked-files=no)
if (@($trackedChanges).Count -gt 0) {
    throw 'Packaging refused: the tracked worktree is not clean.'
}

# Allowlisted release files, staged under out/package/.
$staging = Join-Path $repoRoot ('out\package\soc-sleeping-bag-' + $version)
$distDir = Join-Path $repoRoot 'dist'
$zipPath = Join-Path $distDir ('soc-sleeping-bag-' + $version + '.zip')

if (Test-Path -LiteralPath (Join-Path $repoRoot 'out\package')) {
    Remove-Item -LiteralPath (Join-Path $repoRoot 'out\package') -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$allowlist = @(
    'gamedata',
    'patches\manifest.json',
    'config\local.example.json',
    'README.md',
    'LICENSE',
    'VERSION',
    'CHANGELOG.md',
    'CONTRIBUTING.md',
    'docs\COMPATIBILITY.md',
    'docs\DEVELOPMENT.md',
    'docs\ARCHITECTURE.md',
    'docs\RUNTIME-TESTS.md',
    'tools\common.ps1',
    'tools\deploy.ps1',
    'tools\uninstall.ps1',
    'tools\known-builds.json'
)

foreach ($entry in $allowlist) {
    $source = Join-Path $repoRoot $entry
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Packaging refused: allowlisted path missing: $entry"
    }
    $destination = Join-Path $staging $entry
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Recurse
}

# Guard rails: nothing machine-local, generated, or third-party may have
# been staged.
$forbiddenNames = @('local.json', 'references', 'backups')
foreach ($name in $forbiddenNames) {
    $hit = @(Get-ChildItem -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $name })
    if (@($hit).Count -gt 0) {
        throw "Packaging refused: forbidden content staged ($name)."
    }
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath

Write-Output "Package staged: $staging"
Write-Output "Archive created: $zipPath"
