[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $sourceRoot 'tools\common.ps1')
$deploySource = Join-Path $sourceRoot 'tools\deploy.ps1'
if (-not (Test-Path -LiteralPath $deploySource -PathType Leaf)) {
    throw 'RED: tools/deploy.ps1 does not exist.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('soc-sleeping-bag-deploy-tests-' + [guid]::NewGuid().ToString('N'))
$powershellExe = if (Test-Path -LiteralPath (Join-Path $PSHOME 'pwsh.exe')) {
    Join-Path $PSHOME 'pwsh.exe'
} elseif (Test-Path -LiteralPath (Join-Path $PSHOME 'powershell.exe')) {
    Join-Path $PSHOME 'powershell.exe'
} else {
    (Get-Process -Id $PID).Path
}

$systemFixture = [String]::Join("`r`n", @(
        '; Independently authored deployment fixture.',
        '#include "misc\items.ltx"',
        '#include "misc\unrelated_weight_mod.ltx" ; unrelated edit',
        ''
    ))
$bindFixture = [String]::Join("`r`n", @(
        '-- Independently authored deployment fixture.',
        'function actor_binder:net_spawn(data)',
        "`tdeath_manager.init_drop_settings()",
        '    repair_dialog.keep_this() -- unrelated edit',
        'end',
        '',
        'function actor_binder:net_destroy()',
        "`tobject_binder.net_destroy(self)",
        'end',
        '',
        'function actor_binder:use_inventory_item(obj)',
        "`tif(obj) then",
        "`tend",
        'end',
        '',
        'function actor_binder:hit_callback(obj, amount, local_direction, who, bone_index)',
        "`t-- MTB-Damian.Romanik [JUD-1117] Start: Make sure who is present",
        "`tif who == nil then",
        "`t`treturn",
        "`tend",
        'end',
        '',
        'function actor_binder:update(delta)',
        "`tobject_binder.update(self, delta)",
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
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'patches\manifest.json') -Destination (Join-Path $repo 'patches\manifest.json')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'VERSION') -Destination (Join-Path $repo 'VERSION')

    Write-Utf8Text -Path (Join-Path $repo 'gamedata\config\misc\owned-fixture.ltx') -Text "[owned_fixture]`r`nvalue = authored`r`n"
    Copy-Item -LiteralPath $powershellExe -Destination (Join-Path $game 'XR_3DA.exe')
    Write-Utf8Text -Path (Join-Path $game 'fsgame_soc.ltx') -Text "`$game_data`$ = true| true| `$fs_root`$| gamedata\`r`n"
    # A small binary stand-in for configs.db: the two shared files are stored
    # uncompressed at pinned offsets, exactly like the real archive.
    $systemBytes = [Text.UTF8Encoding]::new($false).GetBytes($systemFixture)
    $bindBytes = [Text.UTF8Encoding]::new($false).GetBytes($bindFixture)
    $systemOffset = 100
    $bindOffset = $systemOffset + $systemBytes.Length + 50
    $archiveBytes = New-Object byte[] ($bindOffset + $bindBytes.Length + 20)
    [Array]::Copy($systemBytes, 0, $archiveBytes, $systemOffset, $systemBytes.Length)
    [Array]::Copy($bindBytes, 0, $archiveBytes, $bindOffset, $bindBytes.Length)
    [IO.File]::WriteAllBytes((Join-Path $game 'resources\configs.db'), $archiveBytes)
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
                archiveFiles = [ordered]@{
                    'config/system.ltx' = [ordered]@{ archive = 'resources/configs.db'; offset = $systemOffset; size = $systemBytes.Length; sha256 = (Get-BytesSha256 -Bytes $systemBytes) }
                    'scripts/bind_stalker.script' = [ordered]@{ archive = 'resources/configs.db'; offset = $bindOffset; size = $bindBytes.Length; sha256 = (Get-BytesSha256 -Bytes $bindBytes) }
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
    }
}

function Invoke-Deploy {
    param([Parameter(Mandatory)] $Fixture, [switch] $Apply)

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Fixture.Deploy, '-GameDir', $Fixture.Game)
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

    $fixture = New-DeploymentFixture -Name 'tampered-archive-member' -LooseSystem $false -LooseBind $false
    $archiveFile = Join-Path $fixture.Game 'resources\configs.db'
    $archiveContent = [IO.File]::ReadAllBytes($archiveFile)
    $archiveContent[120] = [byte]($archiveContent[120] -bxor 0xFF)
    [IO.File]::WriteAllBytes($archiveFile, $archiveContent)
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'does not match the known build'

    $fixture = New-DeploymentFixture -Name 'unpinned-archive-entry' -LooseSystem $false -LooseBind $false
    $registryFile = Join-Path $fixture.Repo 'tools\known-builds.json'
    $registryJson = Get-Content -LiteralPath $registryFile -Raw | ConvertFrom-Json
    $registryJson.builds[0].PSObject.Properties.Remove('archiveFiles')
    Write-Utf8Text -Path $registryFile -Text ($registryJson | ConvertTo-Json -Depth 8)
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'There is no loose copy'

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

    $fixture = New-DeploymentFixture -Name 'missing-version'
    Remove-Item -LiteralPath (Join-Path $fixture.Repo 'VERSION') -Force
    Assert-DeployFailedWithoutWrites -Fixture $fixture -Pattern 'VERSION file not found'

    $fixture = New-DeploymentFixture -Name 'non-ascii-preservation'
    $legacyBytes = [byte[]]@(
        0x3b, 0x20, 0xe9, 0x0d, 0x0a,
        0x23, 0x69, 0x6e, 0x63, 0x6c, 0x75, 0x64, 0x65, 0x20, 0x22, 0x6d, 0x69, 0x73, 0x63, 0x5c, 0x69, 0x74, 0x65, 0x6d, 0x73, 0x2e, 0x6c, 0x74, 0x78, 0x22, 0x0d, 0x0a
    )
    [IO.File]::WriteAllBytes((Join-Path $fixture.Game 'gamedata\config\system.ltx'), $legacyBytes)
    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Non-ASCII apply failed. Output: $($result.Output)"
    $installedBytes = [IO.File]::ReadAllBytes((Join-Path $fixture.Game 'gamedata\config\system.ltx'))
    Assert-True -Condition ($installedBytes -contains 0xe9) -Message 'Non-ASCII legacy byte 0xE9 must be preserved in patched file.'
    $decodedText = (Get-GameFileText -Path (Join-Path $fixture.Game 'gamedata\config\system.ltx')).Text
    Assert-True -Condition (-not $decodedText.Contains([string][char]0xfffd)) -Message 'Non-ASCII text must not decode to replacement characters.'
    Assert-True -Condition ($decodedText.Contains([string][char]0x0439)) -Message 'Non-ASCII text must decode to expected character.'
    Assert-Match -Text $decodedText -Pattern 'soc_sleeping_bag\.ltx.*soc_sleeping_bag' -Message 'Non-ASCII file must be properly patched.'

    $fixture = New-DeploymentFixture -Name 'rollback-locked-file'
    $before = Get-TreeSnapshot -Root $fixture.Game
    $targetToLock = Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script'
    $lockStream = [IO.File]::Open($targetToLock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $result = Invoke-Deploy -Fixture $fixture -Apply
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "Apply should have failed when a target file is locked. Output: $($result.Output)"
    }
    finally {
        $lockStream.Dispose()
    }
    $after = Get-TreeSnapshot -Root $fixture.Game
    Assert-SnapshotEqual -Expected $before -Actual $after -Message 'Rolled-back deployment must restore all files to pre-apply state when a file is locked.'

    $fixture = New-DeploymentFixture -Name 'rollback-locked-manifest'
    $manifestPath = Join-Path $fixture.Game 'gamedata\soc_sleeping_bag_deployed.json'
    Write-Utf8Text -Path $manifestPath -Text '{"preExisting": true}'
    $before = Get-TreeSnapshot -Root $fixture.Game
    $lockStream = [IO.File]::Open($manifestPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $result = Invoke-Deploy -Fixture $fixture -Apply
        Assert-True -Condition ($result.ExitCode -ne 0) -Message "Apply should have failed when deployment manifest is locked. Output: $($result.Output)"
    }
    finally {
        $lockStream.Dispose()
    }
    $after = Get-TreeSnapshot -Root $fixture.Game
    Assert-SnapshotEqual -Expected $before -Actual $after -Message 'Rolled-back deployment must restore all files to pre-apply state when manifest is locked.'


    # ---- icon atlas: built from the game's archive copy, verified, spliced ----
    function New-AtlasFixture {
        param([Parameter(Mandatory)][string] $Name)

        $fixture = New-DeploymentFixture -Name $Name
        # Synthetic 32x16 DXT5 atlas (8x4 blocks) stored inside a fake archive.
        $atlas = New-Object byte[] (128 + 8 * 4 * 16)
        [Text.Encoding]::ASCII.GetBytes('DDS ').CopyTo($atlas, 0)
        [BitConverter]::GetBytes([uint32]16).CopyTo($atlas, 12)
        [BitConverter]::GetBytes([uint32]32).CopyTo($atlas, 16)
        [BitConverter]::GetBytes([uint32]1).CopyTo($atlas, 28)
        [Text.Encoding]::ASCII.GetBytes('DXT5').CopyTo($atlas, 84)
        for ($i = 128; $i -lt $atlas.Length; $i++) { $atlas[$i] = 0x11 }
        $archive = New-Object byte[] (300 + $atlas.Length + 50)
        [Array]::Copy($atlas, 0, $archive, 300, $atlas.Length)
        [IO.File]::WriteAllBytes((Join-Path $fixture.Game 'resources\resources.db10'), $archive)

        # A 2x2-block (8x8 px) icon placed at cell (1,1) of a 4 px grid.
        $blocks = New-Object byte[] (2 * 2 * 16)
        for ($i = 0; $i -lt $blocks.Length; $i++) { $blocks[$i] = 0xEE }
        New-Item -ItemType Directory -Path (Join-Path $fixture.Repo 'art') -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $fixture.Repo 'art\icon.dxt5'), $blocks)

        $manifestFile = Join-Path $fixture.Repo 'patches\manifest.json'
        $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
        $manifest.atlas = [pscustomobject]@{ path = 'gamedata/textures/ui/ui_icon_equipment.dds'; blocks = 'art/icon.dxt5'; cell = @(1, 1); cellSize = 4; iconWidth = 8; iconHeight = 8 }
        Write-Utf8Text -Path $manifestFile -Text ($manifest | ConvertTo-Json -Depth 8)

        $registryFile = Join-Path $fixture.Repo 'tools\known-builds.json'
        $registry = Get-Content -LiteralPath $registryFile -Raw | ConvertFrom-Json
        $registry.builds[0] | Add-Member -NotePropertyName atlas -NotePropertyValue ([pscustomobject]@{ archive = 'resources/resources.db10'; offset = 300; size = $atlas.Length; sha256 = (Get-BytesSha256 -Bytes $atlas) })
        Write-Utf8Text -Path $registryFile -Text ($registry | ConvertTo-Json -Depth 8)

        return [pscustomobject]@{ Fixture = $fixture; Atlas = $atlas; Blocks = $blocks }
    }

    $case = New-AtlasFixture -Name 'atlas'
    $fixture = $case.Fixture
    $before = Get-TreeSnapshot -Root $fixture.Game
    $result = Invoke-Deploy -Fixture $fixture
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Atlas dry-run failed. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'ATLAS gamedata/textures/ui/ui_icon_equipment\.dds' -Message 'The plan must report the atlas.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Atlas dry-run must not write.'

    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Atlas apply failed. Output: $($result.Output)"
    $installedAtlasPath = Join-Path $fixture.Game 'gamedata\textures\ui\ui_icon_equipment.dds'
    $installedAtlas = [IO.File]::ReadAllBytes($installedAtlasPath)
    Assert-Equal -Expected $case.Atlas.Length -Actual $installedAtlas.Length -Message 'The patched atlas must keep the vanilla size.'
    $changed = @(0..($installedAtlas.Length - 1) | Where-Object { $installedAtlas[$_] -ne $case.Atlas[$_] })
    Assert-Equal -Expected 64 -Actual $changed.Count -Message 'Only the icon blocks may differ from the vanilla atlas.'
    # Cell (1,1) at 4 px is block column 1, block rows 1-2 of an 8-block-wide atlas.
    Assert-Equal -Expected (128 + (1 * 8 + 1) * 16) -Actual $changed[0] -Message 'The icon must land at its cell.'
    $deployedManifest = Get-Content -LiteralPath (Join-Path $fixture.Game 'gamedata\soc_sleeping_bag_deployed.json') -Raw | ConvertFrom-Json
    $atlasRecord = @($deployedManifest.files | Where-Object { $_.relativePath -ceq 'gamedata/textures/ui/ui_icon_equipment.dds' })
    Assert-Equal -Expected 1 -Actual $atlasRecord.Count -Message 'The deployment manifest must record the atlas.'
    Assert-Equal -Expected 'owned' -Actual $atlasRecord[0].ownership -Message 'The atlas is mod-owned.'

    # Redeploy over our own output is idempotent.
    $hashBefore = (Get-FileHash -LiteralPath $installedAtlasPath -Algorithm SHA256).Hash
    $result = Invoke-Deploy -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Atlas redeploy failed. Output: $($result.Output)"
    Assert-Equal -Expected $hashBefore -Actual (Get-FileHash -LiteralPath $installedAtlasPath -Algorithm SHA256).Hash -Message 'Redeploy must be idempotent.'

    # Uninstall removes the unchanged atlas, restoring the engine's archive copy.
    $uninstall = Join-Path $sourceRoot 'tools\uninstall.ps1'
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $uninstallText = (& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $uninstall -GameDir $fixture.Game -Apply 2>&1 | Out-String)
        $uninstallExit = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-Equal -Expected 0 -Actual $uninstallExit -Message "Atlas uninstall failed. Output: $uninstallText"
    Assert-True -Condition (-not (Test-Path -LiteralPath $installedAtlasPath)) -Message 'Uninstall must remove the unchanged atlas.'

    # A loose atlas from another mod is never overwritten.
    $case = New-AtlasFixture -Name 'atlas-foreign'
    $foreignPath = Join-Path $case.Fixture.Game 'gamedata\textures\ui\ui_icon_equipment.dds'
    New-Item -ItemType Directory -Path (Split-Path -Parent $foreignPath) -Force | Out-Null
    [IO.File]::WriteAllBytes($foreignPath, [byte[]](1, 2, 3, 4))
    Assert-DeployFailedWithoutWrites -Fixture $case.Fixture -Pattern 'Another mod already provides'

    # A vanilla atlas that does not match the pinned hash is rejected.
    $case = New-AtlasFixture -Name 'atlas-mismatch'
    $archiveFile = Join-Path $case.Fixture.Game 'resources\resources.db10'
    $archiveBytes = [IO.File]::ReadAllBytes($archiveFile)
    $archiveBytes[400] = 0x77
    [IO.File]::WriteAllBytes($archiveFile, $archiveBytes)
    Assert-DeployFailedWithoutWrites -Fixture $case.Fixture -Pattern 'does not match the known build'

    Write-Output 'PASS: merge-aware deployment contracts'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
