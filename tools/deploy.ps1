[CmdletBinding()]
param(
    [string] $GameDir,
    [string] $ConfigPath,
    [switch] $Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string] $Path, [Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Get-RelativeForwardPath {
    param([Parameter(Mandatory)][string] $Root, [Parameter(Mandatory)][string] $Path)

    return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

function New-UniqueBackupRoot {
    param([Parameter(Mandatory)][string] $RepoRoot)

    $parent = Join-Path $RepoRoot 'out\backups'
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $name = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
    $candidate = Join-Path $parent $name
    $suffix = 0
    while (Test-Path -LiteralPath $candidate) {
        $suffix++
        $candidate = Join-Path $parent ($name + '-' + $suffix)
    }
    New-Item -ItemType Directory -Path $candidate | Out-Null
    return $candidate
}

$repoRoot = Get-RepoRoot
$configuration = Get-LocalConfig -ConfigPath $ConfigPath
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    if (($null -eq $configuration) -or [string]::IsNullOrWhiteSpace([string]$configuration.steamGameDir)) {
        throw 'Game directory was not provided and config/local.json does not define steamGameDir.'
    }
    $GameDir = [string]$configuration.steamGameDir
}

$resolvedGameDir = [IO.Path]::GetFullPath($GameDir)
if (-not (Test-Path -LiteralPath $resolvedGameDir -PathType Container)) {
    throw "Game directory not found: $resolvedGameDir"
}
$identity = Get-GameIdentity -GameDir $resolvedGameDir
$archivePath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'resources\configs.db'
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
    throw "Game resource archive not found: $archivePath"
}
$fsgamePath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'fsgame_soc.ltx'
if (-not (Test-Path -LiteralPath $fsgamePath -PathType Leaf)) {
    throw "Game path configuration not found: $fsgamePath"
}
$fsgame = Get-GameFileText -Path $fsgamePath
if ($fsgame.Text -notmatch '(?im)^\s*\$game_data\$\s*=\s*true\s*\|') {
    throw 'The $game_data$ loose-data setting must be enabled before deployment.'
}

$registryPath = Join-Path $PSScriptRoot 'known-builds.json'
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$knownBuild = @($registry.builds | Where-Object {
        ([string]$_.executableVersion -ceq [string]$identity.executableVersion) -and
        ([string]$_.executableSha256 -ceq [string]$identity.executableSha256)
    })
if ($knownBuild.Count -gt 1) {
    throw 'Known-build registry contains duplicate executable identities.'
}
$knownBuild = if ($knownBuild.Count -eq 1) { $knownBuild[0] } else { $null }

$manifestPath = Join-Path $repoRoot 'patches\manifest.json'
$patchManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$stagingRoot = Join-Path $repoRoot ('out\staging\' + [guid]::NewGuid().ToString('N'))
$payloadRoot = Join-Path $stagingRoot 'payload'
$installedFiles = [Collections.Generic.List[object]]::new()

try {
    New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

    foreach ($fileDefinition in @($patchManifest.sharedFiles)) {
        $relativePath = [string]$fileDefinition.path
        $destinationPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $relativePath
        $archiveEntry = $null
        if (($null -ne $knownBuild) -and ($null -ne $knownBuild.PSObject.Properties['archiveFiles'])) {
            $entryProperty = $knownBuild.archiveFiles.PSObject.Properties[[string]$fileDefinition.archivePath]
            if ($null -ne $entryProperty) { $archiveEntry = $entryProperty.Value }
        }
        $effective = Get-EffectiveGameFile -GameDir $resolvedGameDir -LooseRelativePath $relativePath -ArchiveRelativePath $fileDefinition.archivePath -ArchiveEntry $archiveEntry
        if ($null -eq $fileDefinition.PSObject.Properties['marker']) {
            $fileDefinition | Add-Member -NotePropertyName marker -NotePropertyValue $patchManifest.marker
        }
        $patchedText = Invoke-PatchManifest -Text $effective.Text -FileDefinition $fileDefinition
        $stagedPath = Resolve-ConfinedPath -Root $payloadRoot -RelativePath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagedPath) -Force | Out-Null
        Set-GameFileText -Path $stagedPath -Text $patchedText -Encoding $effective.Encoding
        $installedFiles.Add([pscustomobject]@{
                relativePath = $relativePath.Replace('\', '/')
                ownership = 'shared'
                sourceOrigin = $effective.Origin
                sourcePath = $effective.SourcePath
                baseHash = $effective.BaseHash
                installedHash = Get-Sha256 -Path $stagedPath
                stagedPath = $stagedPath
                destinationPath = $destinationPath
                existed = Test-Path -LiteralPath $destinationPath -PathType Leaf
                action = 'PATCH'
            })
    }

    $ownedRoot = Join-Path $repoRoot 'gamedata'
    if (Test-Path -LiteralPath $ownedRoot -PathType Container) {
        foreach ($sourceFile in @(Get-ChildItem -LiteralPath $ownedRoot -Recurse -File | Sort-Object FullName)) {
            $relativeWithinOwned = Get-RelativeForwardPath -Root $ownedRoot -Path $sourceFile.FullName
            $relativePath = 'gamedata/' + $relativeWithinOwned
            if (@($installedFiles | Where-Object { $_.relativePath -ceq $relativePath }).Count -gt 0) {
                throw "Mod-owned file conflicts with shared-file declaration: $relativePath"
            }
            $destinationPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $relativePath
            $stagedPath = Resolve-ConfinedPath -Root $payloadRoot -RelativePath $relativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $stagedPath) -Force | Out-Null
            Copy-Item -LiteralPath $sourceFile.FullName -Destination $stagedPath
            $sourceHash = Get-Sha256 -Path $sourceFile.FullName
            $installedFiles.Add([pscustomobject]@{
                    relativePath = $relativePath
                    ownership = 'owned'
                    sourceOrigin = 'repository'
                    sourcePath = $sourceFile.FullName
                    baseHash = $sourceHash
                    installedHash = Get-Sha256 -Path $stagedPath
                    stagedPath = $stagedPath
                    destinationPath = $destinationPath
                    existed = Test-Path -LiteralPath $destinationPath -PathType Leaf
                    action = 'COPY'
                })
        }
    }

    # The inventory icon lives inside EE's shared icon atlas. The atlas is built
    # from the game's own copy (read from its archive and verified by hash) with
    # only the icon's blocks replaced, then installed as a mod-owned loose file.
    $atlasProperty = $patchManifest.PSObject.Properties['atlas']
    if ($null -ne $atlasProperty) {
        $atlasDefinition = $atlasProperty.Value
        $knownAtlas = if (($null -ne $knownBuild) -and ($null -ne $knownBuild.PSObject.Properties['atlas'])) { $knownBuild.atlas } else { $null }
        if ($null -eq $knownAtlas) {
            Write-Warning 'No verified icon atlas is known for this build; the sleeping bag will keep no custom icon.'
        }
        else {
            $blocksPath = Resolve-ConfinedPath -Root $repoRoot -RelativePath ([string]$atlasDefinition.blocks)
            if (-not (Test-Path -LiteralPath $blocksPath -PathType Leaf)) {
                throw "Icon block data not found: $blocksPath"
            }
            $vanillaAtlas = Get-ArchiveAtlas -GameDir $resolvedGameDir -AtlasInfo $knownAtlas
            $patchedAtlas = Merge-AtlasBlocks -Atlas $vanillaAtlas -Blocks ([IO.File]::ReadAllBytes($blocksPath)) `
                -CellX ([int]$atlasDefinition.cell[0]) -CellY ([int]$atlasDefinition.cell[1]) -CellSize ([int]$atlasDefinition.cellSize) `
                -IconWidth ([int]$atlasDefinition.iconWidth) -IconHeight ([int]$atlasDefinition.iconHeight)
            $patchedHash = Get-BytesSha256 -Bytes $patchedAtlas

            $atlasRelativePath = [string]$atlasDefinition.path
            $atlasDestination = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $atlasRelativePath
            $atlasExisted = Test-Path -LiteralPath $atlasDestination -PathType Leaf
            if ($atlasExisted) {
                # Only overwrite a loose atlas that is the vanilla one or our own
                # earlier output; anything else belongs to another mod.
                $existingHash = Get-Sha256 -Path $atlasDestination
                $ours = ($existingHash -ceq [string]$knownAtlas.sha256) -or ($existingHash -ceq $patchedHash)
                $priorManifestPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'gamedata\soc_sleeping_bag_deployed.json'
                if ((-not $ours) -and (Test-Path -LiteralPath $priorManifestPath -PathType Leaf)) {
                    $prior = Get-Content -LiteralPath $priorManifestPath -Raw | ConvertFrom-Json
                    $ours = @($prior.files | Where-Object { ([string]$_.relativePath -ceq $atlasRelativePath) -and ([string]$_.installedHash -ceq $existingHash) }).Count -gt 0
                }
                if (-not $ours) {
                    throw "Another mod already provides $atlasRelativePath. Refusing to replace it; remove that mod's atlas or install this mod without the custom icon."
                }
            }
            $stagedAtlasPath = Resolve-ConfinedPath -Root $payloadRoot -RelativePath $atlasRelativePath
            New-Item -ItemType Directory -Path (Split-Path -Parent $stagedAtlasPath) -Force | Out-Null
            [IO.File]::WriteAllBytes($stagedAtlasPath, $patchedAtlas)
            $installedFiles.Add([pscustomobject]@{
                    relativePath = $atlasRelativePath.Replace('\', '/')
                    ownership = 'owned'
                    sourceOrigin = 'archive'
                    sourcePath = $blocksPath
                    baseHash = [string]$knownAtlas.sha256
                    installedHash = $patchedHash
                    stagedPath = $stagedAtlasPath
                    destinationPath = $atlasDestination
                    existed = $atlasExisted
                    action = 'ATLAS'
                })
        }
    }

    $versionPath = Join-Path $repoRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Mod VERSION file not found: $versionPath"
    }
    $modVersion = ([IO.File]::ReadAllText($versionPath)).Trim()
    if ([string]::IsNullOrWhiteSpace($modVersion)) {
        throw 'Mod VERSION file is empty.'
    }

    $deploymentManifestDestination = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'gamedata\soc_sleeping_bag_deployed.json'
    $deploymentManifest = [ordered]@{
        modVersion = $modVersion
        gameIdentity = [ordered]@{
            executableName = $identity.executableName
            executableVersion = if ($null -ne $knownBuild) { $knownBuild.executableVersion } else { $identity.executableVersion }
            executableSha256 = if ($null -ne $knownBuild) { $knownBuild.executableSha256 } else { $identity.executableSha256 }
            steamBuild = if ($null -ne $knownBuild) { $knownBuild.steamBuild } else { 'unknown' }
        }
        deployedAtUtc = [DateTime]::UtcNow.ToString('o')
        files = @($installedFiles | ForEach-Object {
                [ordered]@{
                    relativePath = $_.relativePath
                    ownership = $_.ownership
                    sourceOrigin = $_.sourceOrigin
                    baseHash = $_.baseHash
                    installedHash = $_.installedHash
                }
            })
    }
    $stagedManifestPath = Resolve-ConfinedPath -Root $stagingRoot -RelativePath 'manifest\soc_sleeping_bag_deployed.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $stagedManifestPath) -Force | Out-Null
    Write-Utf8NoBom -Path $stagedManifestPath -Text ($deploymentManifest | ConvertTo-Json -Depth 8)

    if ($null -eq $knownBuild) {
        Write-Warning "UNKNOWN BUILD: executable version '$($identity.executableVersion)', SHA-256 $($identity.executableSha256)."
    }
    else {
        Write-Output "Known build: executable=$($knownBuild.executableVersion) steamBuild=$($knownBuild.steamBuild) sha256=$($knownBuild.executableSha256)"
    }
    Write-Output ($(if ($Apply) { 'APPLY PLAN' } else { 'DRY RUN PLAN' }))
    foreach ($file in $installedFiles) {
        Write-Output ("{0} {1} origin={2} baseHash={3} source={4} destination={5}" -f $file.action, $file.relativePath, $file.sourceOrigin, $file.baseHash, $file.sourcePath, $file.destinationPath)
    }

    if (-not $Apply) {
        Write-Output 'DRY RUN: no game files were changed.'
        return
    }
    if ($null -eq $knownBuild) {
        throw 'Unknown executable build cannot be applied.'
    }

    $backupRoot = New-UniqueBackupRoot -RepoRoot $repoRoot
    foreach ($file in @($installedFiles | Where-Object { $_.existed })) {
        $backupPath = Resolve-ConfinedPath -Root $backupRoot -RelativePath $file.relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
        Copy-Item -LiteralPath $file.destinationPath -Destination $backupPath
    }
    $manifestExisted = Test-Path -LiteralPath $deploymentManifestDestination -PathType Leaf
    if ($manifestExisted) {
        $manifestBackupPath = Resolve-ConfinedPath -Root $backupRoot -RelativePath 'gamedata\soc_sleeping_bag_deployed.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestBackupPath) -Force | Out-Null
        Copy-Item -LiteralPath $deploymentManifestDestination -Destination $manifestBackupPath
    }

    $temporaryFiles = [Collections.Generic.List[object]]::new()
    $committedFiles = [Collections.Generic.List[object]]::new()
    $replacementBackups = [Collections.Generic.List[string]]::new()
    $manifestTemporary = $null

    try {
        foreach ($file in $installedFiles) {
            $destinationDirectory = Split-Path -Parent $file.destinationPath
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            $temporaryPath = $file.destinationPath + '.soc_sleeping_bag.tmp.' + [guid]::NewGuid().ToString('N')
            Copy-Item -LiteralPath $file.stagedPath -Destination $temporaryPath
            $temporaryFiles.Add([pscustomobject]@{ path = $temporaryPath; file = $file })
        }

        $manifestDirectory = Split-Path -Parent $deploymentManifestDestination
        New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
        $manifestTempPath = $deploymentManifestDestination + '.soc_sleeping_bag.tmp.' + [guid]::NewGuid().ToString('N')
        Copy-Item -LiteralPath $stagedManifestPath -Destination $manifestTempPath
        $manifestRecord = [pscustomobject]@{
            destinationPath = $deploymentManifestDestination
            relativePath = 'gamedata/soc_sleeping_bag_deployed.json'
            existed = $manifestExisted
        }
        $manifestTemporary = [pscustomobject]@{ path = $manifestTempPath; file = $manifestRecord }

        foreach ($temporary in $temporaryFiles) {
            if ($temporary.file.existed) {
                $replacementBackupPath = $temporary.file.destinationPath + '.soc_sleeping_bag.replace.' + [guid]::NewGuid().ToString('N')
                [IO.File]::Replace($temporary.path, $temporary.file.destinationPath, $replacementBackupPath)
                $committedFiles.Add($temporary.file)
                $replacementBackups.Add($replacementBackupPath)
            }
            else {
                [IO.File]::Move($temporary.path, $temporary.file.destinationPath)
                $committedFiles.Add($temporary.file)
            }
        }

        if ($manifestTemporary.file.existed) {
            $manifestReplacementBackupPath = $deploymentManifestDestination + '.soc_sleeping_bag.replace.' + [guid]::NewGuid().ToString('N')
            [IO.File]::Replace($manifestTemporary.path, $deploymentManifestDestination, $manifestReplacementBackupPath)
            $committedFiles.Add($manifestTemporary.file)
            $replacementBackups.Add($manifestReplacementBackupPath)
        }
        else {
            [IO.File]::Move($manifestTemporary.path, $deploymentManifestDestination)
            $committedFiles.Add($manifestTemporary.file)
        }
    }
    catch {
        for ($i = $committedFiles.Count - 1; $i -ge 0; $i--) {
            $file = $committedFiles[$i]
            try {
                if ($file.existed) {
                    $backupPath = Resolve-ConfinedPath -Root $backupRoot -RelativePath $file.relativePath
                    Copy-Item -LiteralPath $backupPath -Destination $file.destinationPath -Force
                }
                elseif (Test-Path -LiteralPath $file.destinationPath -PathType Leaf) {
                    Remove-Item -LiteralPath $file.destinationPath -Force
                }
            }
            catch {
                Write-Warning "Failed to roll back $($file.destinationPath): $($_.Exception.Message)"
            }
        }
        throw
    }
    finally {
        foreach ($backupPath in $replacementBackups) {
            if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
                try { Remove-Item -LiteralPath $backupPath -Force } catch { }
            }
        }
        foreach ($temporary in $temporaryFiles) {
            if (Test-Path -LiteralPath $temporary.path -PathType Leaf) {
                try { Remove-Item -LiteralPath $temporary.path -Force } catch { }
            }
        }
        if (($null -ne $manifestTemporary) -and (Test-Path -LiteralPath $manifestTemporary.path -PathType Leaf)) {
            try { Remove-Item -LiteralPath $manifestTemporary.path -Force } catch { }
        }
    }

    Write-Output "Deployment applied. Backup: $backupRoot"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
