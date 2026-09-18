[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$deploySource = Join-Path $sourceRoot 'tools\deploy.ps1'
if (-not (Test-Path -LiteralPath $deploySource -PathType Leaf)) {
    throw 'RED: tools/deploy.ps1 does not exist.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('soc-sleeping-bag-deploy-tests-' + [guid]::NewGuid().ToString('N'))
$powershellExe = Join-Path $PSHOME 'powershell.exe'

$systemFixture = [String]::Join("`r`n", @(
        '; Independently authored deployment fixture.',
        '#include "misc\items.ltx"',
        '#include "misc\unrelated_weight_mod.ltx" ; unrelated edit',
        ''
    ))
$bindFixture = [String]::Join("`r`n", @(
        '-- Independently authored deployment fixture.',
        'function actor_binder:net_spawn(data)',
        'death_manager.init_drop_settings()',
        '    repair_dialog.keep_this() -- unrelated edit',
        'end',
        '',
        'function actor_binder:net_destroy()',
        'self.bCheckStart = false',
        'end',
        '',
        'function actor_binder:use_inventory_item(obj)',
        'local obj_section = obj:section()',
        'end',
        '',
        'function actor_binder:hit_callback(obj, amount, local_direction, who, bone_index)',
        'local hitted_by = who and who:id()',
        'end',
        '',
        'function actor_binder:update(delta)',
        'object_binder.update(self, delta)',
        'end',
        ''
    ))

function Write-Utf8Text {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-TreeSnapshot {
    param([Parameter(Mandatory)][string] $Root)

    $entries = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\')
        $entries[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $entries
}

function Assert-SnapshotEqual {
    param([Parameter(Mandatory)] $Expected, [Parameter(Mandatory)] $Actual, [string] $Message)

    Assert-Equal -Expected (($Expected.Keys | Sort-Object) -join '|') -Actual (($Actual.Keys | Sort-Object) -join '|') -Message $Message
    foreach ($key in $Expected.Keys) {
        Assert-Equal -Expected $Expected[$key] -Actual $Actual[$key] -Message "$Message File changed: $key."
    }
}

function New-DeploymentFixture {
    param(
        [Parameter(Mandatory)][string] $Name,
        [bool] $LooseSystem = $true,
        [bool] $LooseBind = $true
    )

    $caseRoot = Join-Path $testRoot ($Name + '-' + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $caseRoot 'repo'
    $game = Join-Path $caseRoot 'game'
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools\tests'), (Join-Path $repo 'patches'), (Join-Path $repo 'gamedata\config\misc'), (Join-Path $game 'resources') -Force | Out-Null
    Copy-Item -LiteralPath $deploySource -Destination (Join-Path $repo 'tools\deploy.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\common.ps1') -Destination (Join-Path $repo 'tools\common.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\tests\fake_7z.ps1') -Destination (Join-Path $repo 'tools\tests\fake_7z.ps1')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'patches\manifest.json') -Destination (Join-Path $repo 'patches\manifest.json')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'VERSION') -Destination (Join-Path $repo 'VERSION')

    Write-Utf8Text -Path (Join-Path $repo 'gamedata\config\misc\owned-fixture.ltx') -Text "[owned_fixture]`r`nvalue = authored`r`n"
    Copy-Item -LiteralPath $powershellExe -Destination (Join-Path $game 'XR_3DA.exe')
    Write-Utf8Text -Path (Join-Path $game 'fsgame_soc.ltx') -Text "`$game_data`$ = true| true| `$fs_root`$| gamedata\`r`n"
    Write-Utf8Text -Path (Join-Path $game 'resources\configs.db') -Text 'fixture archive'
    Write-Utf8Text -Path (Join-Path $game 'resources\configs.db.contents\config\system.ltx') -Text $systemFixture
    Write-Utf8Text -Path (Join-Path $game 'resources\configs.db.contents\scripts\bind_stalker.script') -Text $bindFixture
    if ($LooseSystem) {
        Write-Utf8Text -Path (Join-Path $game 'gamedata\config\system.ltx') -Text $systemFixture
    }
    if ($LooseBind) {
        Write-Utf8Text -Path (Join-Path $game 'gamedata\scripts\bind_stalker.script') -Text $bindFixture
    }

    $executable = Get-Item -LiteralPath (Join-Path $game 'XR_3DA.exe')
    $registry = [ordered]@{
        builds = @(
            [ordered]@{
                executableVersion = $executable.VersionInfo.FileVersion
                steamBuild = 'fixture-build'
                executableSha256 = (Get-FileHash -LiteralPath $executable.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                files = [ordered]@{
                    'config/system.ltx' = (Get-FileHash -LiteralPath (Join-Path $game 'resources\configs.db.contents\config\system.ltx') -Algorithm SHA256).Hash.ToLowerInvariant()
                    'scripts/bind_stalker.script' = (Get-FileHash -LiteralPath (Join-Path $game 'resources\configs.db.contents\scripts\bind_stalker.script') -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
        )
    }
    Write-Utf8Text -Path (Join-Path $repo 'tools\known-builds.json') -Text ($registry | ConvertTo-Json -Depth 8)

    return [pscustomobject]@{
        Root = $caseRoot
        Repo = $repo
        Game = $game
        Deploy = Join-Path $repo 'tools\deploy.ps1'
        SevenZip = Join-Path $repo 'tools\tests\fake_7z.ps1'
    }
}

function Invoke-Deploy {
    param([Parameter(Mandatory)] $Fixture, [switch] $Apply)

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Fixture.Deploy, '-GameDir', $Fixture.Game, '-SevenZipPath', $Fixture.SevenZip)
    if ($Apply) {
        $arguments += '-Apply'
    }
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $text = (& $powershellExe @arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $text }
}

function Assert-DeployFailedWithoutWrites {
    param([Parameter(Mandatory)] $Fixture, [Parameter(Mandatory)][string] $Pattern)

    $before = Get-TreeSnapshot -Root $Fixture.Game
    $result = Invoke-Deploy -Fixture $Fixture -Apply
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Deployment unexpectedly succeeded. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern $Pattern -Message 'Deployment failure did not describe the rejected condition.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $Fixture.Game) -Message 'A rejected deployment must not change the game fixture.'
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $fixture = New-DeploymentFixture -Name 'dry-run'
    $before = Get-TreeSnapshot -Root $fixture.Game
    $result = Invoke-Deploy -Fixture $fixture
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Dry-run failed. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'DRY RUN' -Message 'Dry-run must identify itself.'
    Assert-Match -Text $result.Output -Pattern 'PATCH.*gamedata[\\/]config[\\/]system\.ltx' -Message 'Dry-run must report shared patches.'
    Assert-Match -Text $result.Output -Pattern 'COPY.*gamedata[\\/]config[\\/]misc[\\/]owned-fixture\.ltx' -Message 'Dry-run must report owned copies.'
    Assert-Match -Text $result.Output -Pattern 'destination=.*gamedata[\\/]config[\\/]system\.ltx' -Message 'The plan must show the resolved destination.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Dry-run must not write to the game fixture.'

    $fixture = New-DeploymentFixture -Name 'apply'
    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Apply failed. Output: $($result.Output)"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $fixture.Game 'gamedata\config\misc\owned-fixture.ltx')) -Message 'Apply must copy every mod-owned file.'
    $installedSystem = Get-Content -LiteralPath (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Raw
    $installedBind = Get-Content -LiteralPath (Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script') -Raw
    Assert-Match -Text $installedSystem -Pattern 'soc_sleeping_bag\.ltx.*soc_sleeping_bag' -Message 'Apply must patch system.ltx.'
    Assert-Match -Text $installedBind -Pattern 'soc_sleeping_bag\.on_actor_net_spawn' -Message 'Apply must patch bind_stalker.script.'
    Assert-Match -Text $installedSystem -Pattern 'unrelated_weight_mod' -Message 'Loose-file unrelated edits must survive.'
    Assert-Match -Text $installedBind -Pattern 'repair_dialog\.keep_this' -Message 'Loose binder unrelated edits must survive.'

    $fixture = New-DeploymentFixture -Name 'archive' -LooseSystem $false -LooseBind $false
    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Archive materialization failed. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'origin=archive' -Message 'The plan must identify archive-derived shared files.'
    Assert-Match -Text (Get-Content -LiteralPath (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Raw) -Pattern 'soc_sleeping_bag' -Message 'A missing loose file must be materialized and patched.'

    $fixture = New-DeploymentFixture -Name 'missing-archive-member' -LooseSystem $false -LooseBind $false
    Remove-Item -LiteralPath (Join-Path $fixture.Game 'resources\configs.db.contents\config\system.ltx') -Force
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'Archive member not found|7-Zip failed'

    $fixture = New-DeploymentFixture -Name 'multiple-archive-candidates' -LooseSystem $false -LooseBind $false
    Write-Utf8Text -Path (Join-Path $fixture.Game 'resources\configs.db') -Text 'multiple candidates'
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'exactly one file'

    $fixture = New-DeploymentFixture -Name 'idempotent'
    $first = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $first.ExitCode -Message "Initial apply failed. Output: $($first.Output)"
    $contentPaths = @('gamedata\config\system.ltx', 'gamedata\scripts\bind_stalker.script', 'gamedata\config\misc\owned-fixture.ltx')
    $firstHashes = @{}
    foreach ($relativePath in $contentPaths) {
        $firstHashes[$relativePath] = (Get-FileHash -LiteralPath (Join-Path $fixture.Game $relativePath) -Algorithm SHA256).Hash
    }
    $second = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $second.ExitCode -Message "Repeated apply failed. Output: $($second.Output)"
    foreach ($relativePath in $contentPaths) {
        Assert-Equal -Expected $firstHashes[$relativePath] -Actual (Get-FileHash -LiteralPath (Join-Path $fixture.Game $relativePath) -Algorithm SHA256).Hash -Message "Repeated apply must be byte-identical for $relativePath."
    }
    $markerCount = ([regex]::Matches((Get-Content -LiteralPath (Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script') -Raw), 'soc_sleeping_bag')).Count
    Assert-Equal -Expected 10 -Actual $markerCount -Message 'Repeated apply must not duplicate the five binder marker lines.'

    $fixture = New-DeploymentFixture -Name 'missing-executable'
    Remove-Item -LiteralPath (Join-Path $fixture.Game 'XR_3DA.exe') -Force
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'executable'

    $fixture = New-DeploymentFixture -Name 'missing-archive'
    Remove-Item -LiteralPath (Join-Path $fixture.Game 'resources\configs.db') -Force
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'configs\.db'

    $fixture = New-DeploymentFixture -Name 'disabled-gamedata'
    Write-Utf8Text -Path (Join-Path $fixture.Game 'fsgame_soc.ltx') -Text "`$game_data`$ = false| true| `$fs_root`$| gamedata\`r`n"
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'loose-data|game_data'

    $fixture = New-DeploymentFixture -Name 'missing-anchor'
    Write-Utf8Text -Path (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Text "no include anchor`r`n"
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'exactly once'

    $fixture = New-DeploymentFixture -Name 'duplicate-anchor'
    Write-Utf8Text -Path (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Text ($systemFixture.Replace('#include "misc\items.ltx"', "#include `"misc\items.ltx`"`r`n#include `"misc\items.ltx`""))
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'exactly once'

    $fixture = New-DeploymentFixture -Name 'late-stage-failure'
    $originalSystemHash = (Get-FileHash -LiteralPath (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Algorithm SHA256).Hash
    Write-Utf8Text -Path (Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script') -Text "function actor_binder:net_spawn(data)`r`nend`r`n"
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'exactly once'
    Assert-Equal -Expected $originalSystemHash -Actual (Get-FileHash -LiteralPath (Join-Path $fixture.Game 'gamedata\config\system.ltx') -Algorithm SHA256).Hash -Message 'A later staged patch failure must not install an earlier staged patch.'

    $fixture = New-DeploymentFixture -Name 'unknown-build'
    Add-Content -LiteralPath (Join-Path $fixture.Game 'XR_3DA.exe') -Value 'unknown build'
    $dryRun = Invoke-Deploy -Fixture $fixture
    Assert-Equal -Expected 0 -Actual $dryRun.ExitCode -Message "Unknown-build dry-run should report a plan. Output: $($dryRun.Output)"
    Assert-Match -Text $dryRun.Output -Pattern 'UNKNOWN BUILD' -Message 'An unknown executable must be reported.'
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'Unknown executable|UNKNOWN BUILD'

    $fixture = New-DeploymentFixture -Name 'backups' -LooseSystem $true -LooseBind $false
    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Backup apply failed. Output: $($result.Output)"
    $backupRoots = @(Get-ChildItem -LiteralPath (Join-Path $fixture.Repo 'out\backups') -Directory)
    Assert-Equal -Expected 1 -Actual $backupRoots.Count -Message 'Apply must create one timestamped backup root.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $backupRoots[0].FullName 'gamedata\config\system.ltx')) -Message 'A pre-existing loose target must be backed up.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $backupRoots[0].FullName 'gamedata\scripts\bind_stalker.script'))) -Message 'An archive-materialized target must not receive a backup.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $backupRoots[0].FullName 'gamedata\config\misc\owned-fixture.ltx'))) -Message 'A newly copied owned target must not receive a backup.'

    $deploymentManifestPath = Join-Path $fixture.Game 'gamedata\soc_sleeping_bag_deployed.json'
    $deploymentManifest = Get-Content -LiteralPath $deploymentManifestPath -Raw | ConvertFrom-Json
    Assert-Equal -Expected 'fixture-build' -Actual $deploymentManifest.gameIdentity.steamBuild -Message 'Deployment manifest must record game identity.'
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($deploymentManifest.modVersion)) -Message 'Deployment manifest must record the mod version.'
    Assert-Match -Text $deploymentManifest.deployedAtUtc -Pattern '^\d{4}-\d{2}-\d{2}T' -Message 'Deployment manifest must record UTC time.'
    Assert-Equal -Expected 3 -Actual @($deploymentManifest.files).Count -Message 'Deployment manifest must record every installed file.'
    $systemRecord = @($deploymentManifest.files | Where-Object { $_.relativePath -eq 'gamedata/config/system.ltx' })
    $bindRecord = @($deploymentManifest.files | Where-Object { $_.relativePath -eq 'gamedata/scripts/bind_stalker.script' })
    $ownedRecord = @($deploymentManifest.files | Where-Object { $_.relativePath -eq 'gamedata/config/misc/owned-fixture.ltx' })
    Assert-Equal -Expected 'shared' -Actual $systemRecord[0].ownership -Message 'Shared ownership must be recorded.'
    Assert-Equal -Expected 'loose' -Actual $systemRecord[0].sourceOrigin -Message 'Loose source origin must be recorded.'
    Assert-Equal -Expected 'archive' -Actual $bindRecord[0].sourceOrigin -Message 'Archive source origin must be recorded.'
    Assert-Equal -Expected 'owned' -Actual $ownedRecord[0].ownership -Message 'Owned ownership must be recorded.'
    Assert-Match -Text $systemRecord[0].baseHash -Pattern '^[0-9a-f]{64}$' -Message 'Base hashes must be recorded.'
    Assert-Match -Text $systemRecord[0].installedHash -Pattern '^[0-9a-f]{64}$' -Message 'Installed hashes must be recorded.'

    Write-Output 'PASS: merge-aware deployment contracts'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
