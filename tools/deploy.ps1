[CmdletBinding()]
param(
    [string] $GameDir,
    [string] $ConfigPath,
    [string] $SevenZipPath,
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
if ([string]::IsNullOrWhiteSpace($SevenZipPath)) {
    if (($null -eq $configuration) -or [string]::IsNullOrWhiteSpace([string]$configuration.sevenZipPath)) {
        throw '7-Zip path was not provided and config/local.json does not define sevenZipPath.'
    }
    $SevenZipPath = [string]$configuration.sevenZipPath
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
$fsgameText = [IO.File]::ReadAllText($fsgamePath)
if ($fsgameText -notmatch '(?im)^\s*\$game_data\$\s*=\s*true\s*\|') {
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
        $extractionRoot = Join-Path $stagingRoot ('extract-' + [guid]::NewGuid().ToString('N'))
        $effective = Get-EffectiveGameFile -GameDir $resolvedGameDir -LooseRelativePath $relativePath -ArchiveRelativePath $fileDefinition.archivePath -SevenZipPath $SevenZipPath -StageDir $extractionRoot
        if ($null -eq $fileDefinition.PSObject.Properties['marker']) {
            $fileDefinition | Add-Member -NotePropertyName marker -NotePropertyValue $patchManifest.marker
        }
        $patchedText = Invoke-PatchManifest -Text $effective.Text -FileDefinition $fileDefinition
        $stagedPath = Resolve-ConfinedPath -Root $payloadRoot -RelativePath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagedPath) -Force | Out-Null
        Write-Utf8NoBom -Path $stagedPath -Text $patchedText
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

    $temporaryFiles = [Collections.Generic.List[object]]::new()
    $committedFiles = [Collections.Generic.List[object]]::new()
    try {
        foreach ($file in $installedFiles) {
            $destinationDirectory = Split-Path -Parent $file.destinationPath
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            $temporaryPath = $file.destinationPath + '.soc_sleeping_bag.tmp.' + [guid]::NewGuid().ToString('N')
            Copy-Item -LiteralPath $file.stagedPath -Destination $temporaryPath
            $temporaryFiles.Add([pscustomobject]@{ path = $temporaryPath; file = $file })
        }

        foreach ($temporary in $temporaryFiles) {
            if ($temporary.file.existed) {
                $replacementBackupPath = $temporary.file.destinationPath + '.soc_sleeping_bag.replace.' + [guid]::NewGuid().ToString('N')
                [IO.File]::Replace($temporary.path, $temporary.file.destinationPath, $replacementBackupPath)
                Remove-Item -LiteralPath $replacementBackupPath -Force
            }
            else {
                [IO.File]::Move($temporary.path, $temporary.file.destinationPath)
            }
            $committedFiles.Add($temporary.file)
        }

        $deploymentManifest = [ordered]@{
            modVersion = ([IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION'))).Trim()
            gameIdentity = [ordered]@{
                executableName = $identity.executableName
                executableVersion = $knownBuild.executableVersion
                executableSha256 = $knownBuild.executableSha256
                steamBuild = $knownBuild.steamBuild
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
        $deploymentPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'gamedata\soc_sleeping_bag_deployed.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $deploymentPath) -Force | Out-Null
        $deploymentTemporaryPath = $deploymentPath + '.soc_sleeping_bag.tmp.' + [guid]::NewGuid().ToString('N')
        Write-Utf8NoBom -Path $deploymentTemporaryPath -Text ($deploymentManifest | ConvertTo-Json -Depth 8)
        if (Test-Path -LiteralPath $deploymentPath -PathType Leaf) {
            $deploymentReplacementBackupPath = $deploymentPath + '.soc_sleeping_bag.replace.' + [guid]::NewGuid().ToString('N')
            [IO.File]::Replace($deploymentTemporaryPath, $deploymentPath, $deploymentReplacementBackupPath)
            Remove-Item -LiteralPath $deploymentReplacementBackupPath -Force
        }
        else {
            [IO.File]::Move($deploymentTemporaryPath, $deploymentPath)
        }
    }
    catch {
        foreach ($file in @($committedFiles | Select-Object -Last 1000)) {
            if ($file.existed) {
                $backupPath = Resolve-ConfinedPath -Root $backupRoot -RelativePath $file.relativePath
                Copy-Item -LiteralPath $backupPath -Destination $file.destinationPath -Force
            }
            elseif (Test-Path -LiteralPath $file.destinationPath -PathType Leaf) {
                Remove-Item -LiteralPath $file.destinationPath -Force
            }
        }
        foreach ($temporary in $temporaryFiles) {
            if (Test-Path -LiteralPath $temporary.path -PathType Leaf) {
                Remove-Item -LiteralPath $temporary.path -Force
            }
        }
        throw
    }

    Write-Output "Deployment applied. Backup: $backupRoot"
}
finally {
    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
}
