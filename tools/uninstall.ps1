[CmdletBinding()]
param(
    [string] $GameDir,
    [string] $ConfigPath,
    [switch] $Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'common.ps1')

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

$manifestPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'gamedata\soc_sleeping_bag_deployed.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Output 'soc_sleeping_bag is not installed: deployment manifest not found (gamedata/soc_sleeping_bag_deployed.json).'
    return
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}
catch {
    throw "Deployment manifest is corrupted or unreadable: $($_.Exception.Message)"
}

if ($null -eq $manifest.files) {
    throw 'Deployment manifest does not contain a valid files array.'
}

$plan = [Collections.Generic.List[object]]::new()
foreach ($fileRecord in @($manifest.files)) {
    $relativePath = [string]$fileRecord.relativePath
    $ownership = [string]$fileRecord.ownership
    $sourceOrigin = [string]$fileRecord.sourceOrigin
    $baseHash = [string]$fileRecord.baseHash
    $installedHash = [string]$fileRecord.installedHash

    $destinationPath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $relativePath

    if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
        $plan.Add([pscustomobject]@{
            action = 'already absent'
            relativePath = $relativePath
            destinationPath = $destinationPath
            ownership = $ownership
            sourceOrigin = $sourceOrigin
            currentHash = $null
            unpatchedText = $null
            encoding = $null
        })
        continue
    }

    $currentHash = Get-Sha256 -Path $destinationPath

    if ($ownership -eq 'owned') {
        if ($currentHash -ceq $installedHash) {
            $plan.Add([pscustomobject]@{
                action = 'remove'
                relativePath = $relativePath
                destinationPath = $destinationPath
                ownership = $ownership
                sourceOrigin = $sourceOrigin
                currentHash = $currentHash
                unpatchedText = $null
                encoding = $null
            })
        }
        else {
            $plan.Add([pscustomobject]@{
                action = 'retain changed'
                relativePath = $relativePath
                destinationPath = $destinationPath
                ownership = $ownership
                sourceOrigin = $sourceOrigin
                currentHash = $currentHash
                unpatchedText = $null
                encoding = $null
            })
        }
    }
    elseif ($ownership -eq 'shared') {
        $fileData = Get-GameFileText -Path $destinationPath
        $unpatchedText = Remove-MarkedLines -Text $fileData.Text -Marker 'soc_sleeping_bag'

        $unpatchedBytes = $fileData.Encoding.GetBytes($unpatchedText)
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($unpatchedBytes)
            $unpatchedHash = -join ($hashBytes | ForEach-Object { '{0:x2}' -f $_ })
        }
        finally {
            $sha.Dispose()
        }

        if (($sourceOrigin -eq 'archive') -and ($unpatchedHash -ceq $baseHash)) {
            $plan.Add([pscustomobject]@{
                action = 'remove'
                relativePath = $relativePath
                destinationPath = $destinationPath
                ownership = $ownership
                sourceOrigin = $sourceOrigin
                currentHash = $currentHash
                unpatchedText = $null
                encoding = $null
            })
        }
        else {
            $plan.Add([pscustomobject]@{
                action = 'unpatch'
                relativePath = $relativePath
                destinationPath = $destinationPath
                ownership = $ownership
                sourceOrigin = $sourceOrigin
                currentHash = $currentHash
                unpatchedText = $unpatchedText
                encoding = $fileData.Encoding
            })
        }
    }
    else {
        throw "Unknown ownership type in manifest: $ownership"
    }
}

Write-Output ($(if ($Apply) { 'UNINSTALL PLAN' } else { 'DRY RUN PLAN' }))
foreach ($item in $plan) {
    Write-Output ("{0} {1} ({2})" -f $item.action, $item.relativePath, $item.destinationPath)
}

if (-not $Apply) {
    Write-Output 'DRY RUN: no game files were changed.'
    return
}

# 1. Execute unpatch actions first
$unpatchItems = @($plan | Where-Object { $_.action -eq 'unpatch' })
foreach ($item in $unpatchItems) {
    $tempPath = $item.destinationPath + '.soc_sleeping_bag.tmp.' + [guid]::NewGuid().ToString('N')
    Set-GameFileText -Path $tempPath -Text $item.unpatchedText -Encoding $item.encoding
    $replacementBackup = $item.destinationPath + '.soc_sleeping_bag.replace.' + [guid]::NewGuid().ToString('N')
    [IO.File]::Replace($tempPath, $item.destinationPath, $replacementBackup)
    if (Test-Path -LiteralPath $replacementBackup -PathType Leaf) {
        Remove-Item -LiteralPath $replacementBackup -Force
    }
}

# 2. Execute remove actions
$removeItems = @($plan | Where-Object { $_.action -eq 'remove' })
foreach ($item in $removeItems) {
    Remove-Item -LiteralPath $item.destinationPath -Force
}

# 3. Remove deployment manifest last
Remove-Item -LiteralPath $manifestPath -Force

Write-Output 'Uninstall complete.'
