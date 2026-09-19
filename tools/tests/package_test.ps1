[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$packageScript = Join-Path $repoRoot 'tools\package.ps1'

Assert-True -Condition (Test-Path -LiteralPath $packageScript -PathType Leaf) -Message 'RED: tools/package.ps1 does not exist.'

$version = ([IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION'))).Trim()
$distZip = Join-Path $repoRoot ('dist\soc-sleeping-bag-' + $version + '.zip')

if ($version -match '-dev') {
    # While the repository is a dev build, packaging must refuse and must not
    # leave a release archive behind.
    Assert-True -Condition (-not (Test-Path -LiteralPath $distZip -PathType Leaf)) -Message 'A dev version must not have a release archive.'
    Write-Output 'SKIP: packaging checked only for the -dev refusal (VERSION is a dev build)'
    exit 0
}

# Full packaging run: the checker, a clean tracked worktree, and the archive
# content contract are all exercised through tools/package.ps1.
$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $output = (& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $packageScript 2>&1 | Out-String).TrimEnd()
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
if (-not [string]::IsNullOrWhiteSpace($output)) {
    Write-Output $output
}
Assert-Equal -Expected 0 -Actual $exitCode -Message 'Packaging must succeed for a clean release worktree.'
Assert-True -Condition (Test-Path -LiteralPath $distZip -PathType Leaf) -Message 'The release archive must exist after packaging.'

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($distZip)
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })

    $required = @(
        'gamedata/', 'patches/manifest.json', 'tools/deploy.ps1', 'tools/uninstall.ps1',
        'tools/common.ps1', 'tools/known-builds.json', 'config/local.example.json',
        'README.md', 'LICENSE', 'VERSION', 'CHANGELOG.md', 'docs/COMPATIBILITY.md', 'docs/DEVELOPMENT.md'
    )
    foreach ($requiredEntry in $required) {
        $match = @($entries | Where-Object { $_ -eq $requiredEntry -or $_ -like ($requiredEntry + '/*') })
        Assert-True -Condition (@($match).Count -gt 0) -Message "The archive must contain $requiredEntry."
    }

    $forbiddenPatterns = @(
        '^config/local\.json$',
        '^references/',
        'out/backups',
        '^tools/tests/',
        '\.git/',
        'abc',
        'string_table_abc'
    )
    foreach ($entry in $entries) {
        foreach ($pattern in $forbiddenPatterns) {
            Assert-True -Condition ($entry -notmatch $pattern) -Message "The archive must not contain $entry (pattern $pattern)."
        }
        if ($entry -like 'gamedata/*') {
            Assert-True -Condition ($entry -notmatch 'abc') -Message "ABC filenames must not ship: $entry"
        }
    }

    # The archive must never carry machine-local or generated state.
    foreach ($entry in $entries) {
        Assert-True -Condition ($entry -notmatch '^out/') -Message "Generated output must not ship: $entry"
        Assert-True -Condition ($entry -notmatch 'backups') -Message "Backups must not ship: $entry"
    }

    # The shipped gameplay module and layout must be the tracked ones.
    foreach ($owned in @('gamedata/scripts/soc_sleeping_bag.script', 'gamedata/scripts/soc_sleeping_bag_ui.script', 'gamedata/config/ui/ui_soc_sleeping_bag.xml')) {
        Assert-True -Condition (@($entries | Where-Object { $_ -eq $owned }).Count -eq 1) -Message "The archive must ship $entry"
    }
}
finally {
    $zip.Dispose()
}

Write-Output 'PASS: release packaging contract'
