[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $sourceRoot 'tools\common.ps1')

$uninstallSource = Join-Path $sourceRoot 'tools\uninstall.ps1'
if (-not (Test-Path -LiteralPath $uninstallSource -PathType Leaf)) {
    throw 'RED: tools/uninstall.ps1 does not exist.'
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('soc-sleeping-bag-uninstall-tests-' + [guid]::NewGuid().ToString('N'))
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

function New-UninstallFixture {
    param(
        [Parameter(Mandatory)][string] $Name,
        [bool] $LooseSystem = $true,
        [bool] $LooseBind = $true
    )

    $caseRoot = Join-Path $testRoot ($Name + '-' + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $caseRoot 'repo'
    $game = Join-Path $caseRoot 'game'
    New-Item -ItemType Directory -Path (Join-Path $repo 'tools\tests'), (Join-Path $repo 'patches'), (Join-Path $repo 'gamedata\config\misc'), (Join-Path $game 'resources') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'tools\deploy.ps1') -Destination (Join-Path $repo 'tools\deploy.ps1')
    if (Test-Path -LiteralPath $uninstallSource -PathType Leaf) {
        Copy-Item -LiteralPath $uninstallSource -Destination (Join-Path $repo 'tools\uninstall.ps1')
    }
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

    # Initial deploy so the fixture is in an installed state
    $deployArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $repo 'tools\deploy.ps1'), '-GameDir', $game, '-Apply')
    & $powershellExe @deployArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Initial deploy failed for test fixture $Name."
    }

    return [pscustomobject]@{
        Root = $caseRoot
        Repo = $repo
        Game = $game
        Uninstall = Join-Path $repo 'tools\uninstall.ps1'
    }
}

function Invoke-Uninstall {
    param([Parameter(Mandatory)] $Fixture, [switch] $Apply)

    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Fixture.Uninstall, '-GameDir', $Fixture.Game)
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

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    # 1. Dry-run writes nothing
    $fixture = New-UninstallFixture -Name 'dry-run'
    $before = Get-TreeSnapshot -Root $fixture.Game
    $result = Invoke-Uninstall -Fixture $fixture
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Dry-run failed. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'DRY RUN' -Message 'Dry-run must report DRY RUN.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Dry-run must not modify any game files.'

    # 2. An unchanged owned file is removed
    $fixture = New-UninstallFixture -Name 'remove-owned'
    $ownedPath = Join-Path $fixture.Game 'gamedata\config\misc\owned-fixture.ltx'
    Assert-True -Condition (Test-Path -LiteralPath $ownedPath -PathType Leaf) -Message 'Owned file must exist before uninstall.'
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Apply uninstall failed. Output: $($result.Output)"
    Assert-True -Condition (-not (Test-Path -LiteralPath $ownedPath -PathType Leaf)) -Message 'Unchanged owned file must be removed.'

    # 3. A changed owned file is reported and retained
    $fixture = New-UninstallFixture -Name 'retain-changed-owned'
    $ownedPath = Join-Path $fixture.Game 'gamedata\config\misc\owned-fixture.ltx'
    Add-Content -LiteralPath $ownedPath -Value '; user modification'
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Uninstall with changed owned file failed. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'retain changed' -Message 'Changed owned file must be reported as retain changed.'
    Assert-True -Condition (Test-Path -LiteralPath $ownedPath -PathType Leaf) -Message 'Changed owned file must be retained.'
    Assert-Match -Text (Get-Content -LiteralPath $ownedPath -Raw) -Pattern 'user modification' -Message 'User modifications must survive.'

    # 4. A shared file that originated loose loses only marked lines
    $fixture = New-UninstallFixture -Name 'unpatch-loose' -LooseSystem $true -LooseBind $true
    $systemPath = Join-Path $fixture.Game 'gamedata\config\system.ltx'
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Uninstall unpatch loose failed. Output: $($result.Output)"
    Assert-True -Condition (Test-Path -LiteralPath $systemPath -PathType Leaf) -Message 'Loose shared file must remain.'
    $systemContent = Get-Content -LiteralPath $systemPath -Raw
    Assert-True -Condition (-not $systemContent.Contains('soc_sleeping_bag')) -Message 'Markers must be removed from loose shared file.'
    Assert-Match -Text $systemContent -Pattern 'unrelated_weight_mod' -Message 'Unrelated edits must survive marker removal.'

    # 5. A shared file that originated in the archive is deleted when marker removal produces its recorded base hash
    $fixture = New-UninstallFixture -Name 'delete-archive-origin' -LooseSystem $true -LooseBind $false
    $bindPath = Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script'
    Assert-True -Condition (Test-Path -LiteralPath $bindPath -PathType Leaf) -Message 'Archive-origin file must exist after deploy.'
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Uninstall archive origin failed. Output: $($result.Output)"
    Assert-True -Condition (-not (Test-Path -LiteralPath $bindPath -PathType Leaf)) -Message 'Archive-origin file matching clean base hash must be deleted.'

    # 6. An archive-origin shared file with later unrelated edits loses only marked lines and remains loose
    $fixture = New-UninstallFixture -Name 'retain-edited-archive-origin' -LooseSystem $true -LooseBind $false
    $bindPath = Join-Path $fixture.Game 'gamedata\scripts\bind_stalker.script'
    Add-Content -LiteralPath $bindPath -Value "`r`n-- user added hook`r`n"
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Uninstall edited archive origin failed. Output: $($result.Output)"
    Assert-True -Condition (Test-Path -LiteralPath $bindPath -PathType Leaf) -Message 'Archive-origin file with later edits must remain loose.'
    $bindContent = Get-Content -LiteralPath $bindPath -Raw
    Assert-True -Condition (-not $bindContent.Contains('soc_sleeping_bag')) -Message 'Markers must be removed.'
    Assert-Match -Text $bindContent -Pattern 'user added hook' -Message 'Later unrelated edit must be preserved.'

    # 7. A missing deployment manifest is a clean refusal
    $fixture = New-UninstallFixture -Name 'missing-manifest'
    $manifestPath = Join-Path $fixture.Game 'gamedata\soc_sleeping_bag_deployed.json'
    Remove-Item -LiteralPath $manifestPath -Force
    $before = Get-TreeSnapshot -Root $fixture.Game
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result.ExitCode -Message "Missing manifest must exit cleanly. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'not installed|absent' -Message 'Missing manifest must report mod is absent or not installed.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Missing manifest must write nothing.'

    # 8. A manifest path escaping the game root is rejected
    $fixture = New-UninstallFixture -Name 'escaping-manifest'
    $manifestPath = Join-Path $fixture.Game 'gamedata\soc_sleeping_bag_deployed.json'
    $manifestData = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestData.files += [pscustomobject]@{
        relativePath = '../../escaped_file.txt'
        ownership = 'owned'
        sourceOrigin = 'repository'
        baseHash = 'dummy'
        installedHash = 'dummy'
    }
    Write-Utf8Text -Path $manifestPath -Text ($manifestData | ConvertTo-Json -Depth 8)
    $before = Get-TreeSnapshot -Root $fixture.Game
    $result = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-True -Condition ($result.ExitCode -ne 0) -Message "Escaping manifest path must fail. Output: $($result.Output)"
    Assert-Match -Text $result.Output -Pattern 'escap|confined|root' -Message 'Escaping manifest path failure must be reported.'
    Assert-SnapshotEqual -Expected $before -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Escaping manifest failure must not modify game files.'

    # 9. Repeated uninstall after successful removal reports that the mod is absent and writes nothing
    $fixture = New-UninstallFixture -Name 'repeated-uninstall'
    $result1 = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result1.ExitCode -Message "First uninstall failed. Output: $($result1.Output)"
    $beforeSecond = Get-TreeSnapshot -Root $fixture.Game
    $result2 = Invoke-Uninstall -Fixture $fixture -Apply
    Assert-Equal -Expected 0 -Actual $result2.ExitCode -Message "Repeated uninstall failed. Output: $($result2.Output)"
    Assert-Match -Text $result2.Output -Pattern 'not installed|absent' -Message 'Repeated uninstall must report mod absent.'
    Assert-SnapshotEqual -Expected $beforeSecond -Actual (Get-TreeSnapshot -Root $fixture.Game) -Message 'Repeated uninstall must write nothing.'

    Write-Output 'PASS: ownership-aware uninstall contracts'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
