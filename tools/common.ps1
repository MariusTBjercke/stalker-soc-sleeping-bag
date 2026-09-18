Set-StrictMode -Version Latest

function Get-RepoRoot {
    [CmdletBinding()]
    param()

    return [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
}

function Get-Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-Crlf {
    [CmdletBinding()]
    param([AllowEmptyString()][string] $Text)

    return [regex]::Replace($Text, "`r`n|`r|`n", "`r`n")
}

function Resolve-ConfinedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $RelativePath
    )

    if ([IO.Path]::IsPathRooted($RelativePath)) {
        throw "Relative path must not be rooted: $RelativePath"
    }

    $rootPath = [IO.Path]::GetFullPath($Root)
    $candidatePath = [IO.Path]::GetFullPath((Join-Path $rootPath $RelativePath))
    $separator = [string][IO.Path]::DirectorySeparatorChar
    $rootPrefix = if ($rootPath.EndsWith($separator)) { $rootPath } else { $rootPath + $separator }

    if ([string]::Equals($candidatePath, $rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $rootPath
    }
    if (-not $candidatePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path is outside the declared root: $RelativePath"
    }

    $traversedPath = $rootPath
    foreach ($segment in ($RelativePath -split '[\\/]')) {
        if (($segment.Length -eq 0) -or ($segment -eq '.')) {
            continue
        }
        if ($segment -eq '..') {
            $traversedPath = Split-Path -Parent $traversedPath
            continue
        }

        $traversedPath = Join-Path $traversedPath $segment
        if (Test-Path -LiteralPath $traversedPath) {
            $item = Get-Item -LiteralPath $traversedPath -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Resolved path crosses a reparse point outside the declared root: $RelativePath"
            }
        }
    }

    return $candidatePath
}

function ConvertTo-PatchLines {
    param([AllowEmptyString()][string] $Text)

    return [regex]::Split((ConvertTo-Crlf -Text $Text), "`r`n")
}

function ConvertFrom-PatchLines {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines)

    return ($Lines -join "`r`n")
}

function Get-MatchingLineIndexes {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string] $Needle,
        [Parameter(Mandatory)][int] $Start,
        [Parameter(Mandatory)][int] $EndExclusive
    )

    $matches = [Collections.Generic.List[int]]::new()
    $expected = $Needle.TrimEnd()
    for ($index = $Start; $index -lt $EndExclusive; $index++) {
        if ($Lines[$index].TrimEnd() -ceq $expected) {
            $matches.Add($index)
        }
    }

    return $matches.ToArray()
}

function Get-MarkedLineIndexes {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string] $Marker,
        [Parameter(Mandatory)][int] $Start,
        [Parameter(Mandatory)][int] $EndExclusive
    )

    $matches = [Collections.Generic.List[int]]::new()
    for ($index = $Start; $index -lt $EndExclusive; $index++) {
        if ($Lines[$index].Contains($Marker)) {
            $matches.Add($index)
        }
    }

    return $matches.ToArray()
}

function Get-UniqueLineIndex {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string] $Needle,
        [Parameter(Mandatory)][int] $Start,
        [Parameter(Mandatory)][int] $EndExclusive,
        [Parameter(Mandatory)][string] $Description
    )

    $matches = @(Get-MatchingLineIndexes -Lines $Lines -Needle $Needle -Start $Start -EndExclusive $EndExclusive)
    if ($matches.Count -ne 1) {
        throw "$Description must occur exactly once; found $($matches.Count)."
    }

    return [int]$matches[0]
}

function Get-NormalizedMarkedLine {
    param(
        [Parameter(Mandatory)][string] $Line,
        [Parameter(Mandatory)][string] $Marker
    )

    $normalized = ConvertTo-Crlf -Text $Line
    if ($normalized.Contains("`r`n")) {
        throw 'A marked line must contain exactly one logical line.'
    }
    if (-not $normalized.Contains($Marker)) {
        throw "A marked line must contain its marker: $Marker"
    }

    return $normalized.TrimEnd()
}

function Add-MarkedLineToRange {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string] $Anchor,
        [Parameter(Mandatory)][string] $Line,
        [Parameter(Mandatory)][string] $Marker,
        [Parameter(Mandatory)][int] $Start,
        [Parameter(Mandatory)][int] $EndExclusive,
        [ValidateSet('Before', 'After')][string] $Position
    )

    $anchorIndex = Get-UniqueLineIndex -Lines $Lines -Needle $Anchor -Start $Start -EndExclusive $EndExclusive -Description 'Patch anchor'
    $markedIndexes = @(Get-MarkedLineIndexes -Lines $Lines -Marker $Marker -Start $Start -EndExclusive $EndExclusive)
    if ($markedIndexes.Count -gt 1) {
        throw "Patch marker must occur at most once in scope; found $($markedIndexes.Count)."
    }

    $normalizedLine = Get-NormalizedMarkedLine -Line $Line -Marker $Marker
    $result = [Collections.Generic.List[string]]::new()
    foreach ($existingLine in $Lines) {
        $result.Add($existingLine)
    }

    if ($markedIndexes.Count -eq 1) {
        $result[$markedIndexes[0]] = $normalizedLine
    }
    else {
        $insertIndex = if ($Position -eq 'Before') { $anchorIndex } else { $anchorIndex + 1 }
        $result.Insert($insertIndex, $normalizedLine)
    }

    return $result.ToArray()
}

function Add-MarkedLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Anchor,
        [Parameter(Mandatory)][string] $Line,
        [Parameter(Mandatory)][string] $Marker,
        [ValidateSet('Before', 'After')][string] $Position = 'After'
    )

    $lines = @(ConvertTo-PatchLines -Text $Text)
    $patchedLines = @(Add-MarkedLineToRange -Lines $lines -Anchor $Anchor -Line $Line -Marker $Marker -Start 0 -EndExclusive $lines.Count -Position $Position)
    return ConvertFrom-PatchLines -Lines $patchedLines
}

function Add-MarkedLineInFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $FunctionSignature,
        [Parameter(Mandatory)][string] $Anchor,
        [Parameter(Mandatory)][string] $Line,
        [Parameter(Mandatory)][string] $Marker,
        [ValidateSet('Before', 'After')][string] $Position = 'After'
    )

    $lines = @(ConvertTo-PatchLines -Text $Text)
    $functionIndex = Get-UniqueLineIndex -Lines $lines -Needle $FunctionSignature -Start 0 -EndExclusive $lines.Count -Description 'Lua function signature'
    $scopeEnd = $lines.Count
    for ($index = $functionIndex + 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -cmatch '^function ') {
            $scopeEnd = $index
            break
        }
    }

    $patchedLines = @(Add-MarkedLineToRange -Lines $lines -Anchor $Anchor -Line $Line -Marker $Marker -Start ($functionIndex + 1) -EndExclusive $scopeEnd -Position $Position)
    return ConvertFrom-PatchLines -Lines $patchedLines
}

function Remove-MarkedLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Marker
    )

    $retainedLines = [Collections.Generic.List[string]]::new()
    foreach ($line in @(ConvertTo-PatchLines -Text $Text)) {
        if (-not $line.Contains($Marker)) {
            $retainedLines.Add($line)
        }
    }

    return ConvertFrom-PatchLines -Lines $retainedLines.ToArray()
}

function Add-MarkedBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Anchor,
        [Parameter(Mandatory)][string[]] $Lines,
        [Parameter(Mandatory)][string] $BeginMarker,
        [Parameter(Mandatory)][string] $EndMarker,
        [ValidateSet('Before', 'After')][string] $Position = 'Before'
    )

    $sourceLines = @(ConvertTo-PatchLines -Text $Text)
    $beginIndexes = @(Get-MarkedLineIndexes -Lines $sourceLines -Marker $BeginMarker -Start 0 -EndExclusive $sourceLines.Count)
    $endIndexes = @(Get-MarkedLineIndexes -Lines $sourceLines -Marker $EndMarker -Start 0 -EndExclusive $sourceLines.Count)

    if (($beginIndexes.Count -eq 0) -and ($endIndexes.Count -eq 0)) {
        $baseLines = $sourceLines
    }
    elseif (($beginIndexes.Count -ne 1) -or ($endIndexes.Count -ne 1) -or ($beginIndexes[0] -ge $endIndexes[0])) {
        throw 'Marked block requires exactly one ordered begin and end marker pair.'
    }
    else {
        $base = [Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $sourceLines.Count; $index++) {
            if (($index -lt $beginIndexes[0]) -or ($index -gt $endIndexes[0])) {
                $base.Add($sourceLines[$index])
            }
        }
        $baseLines = $base.ToArray()
    }

    $anchorIndex = Get-UniqueLineIndex -Lines $baseLines -Needle $Anchor -Start 0 -EndExclusive $baseLines.Count -Description 'Patch anchor'
    $block = [Collections.Generic.List[string]]::new()
    $block.Add((Get-NormalizedMarkedLine -Line $BeginMarker -Marker $BeginMarker))
    foreach ($line in $Lines) {
        $normalizedLine = ConvertTo-Crlf -Text $line
        if ($normalizedLine.Contains("`r`n")) {
            throw 'A marked block line must contain exactly one logical line.'
        }
        $block.Add($normalizedLine.TrimEnd())
    }
    $block.Add((Get-NormalizedMarkedLine -Line $EndMarker -Marker $EndMarker))

    $result = [Collections.Generic.List[string]]::new()
    foreach ($line in $baseLines) {
        $result.Add($line)
    }
    $insertIndex = if ($Position -eq 'Before') { $anchorIndex } else { $anchorIndex + 1 }
    for ($index = 0; $index -lt $block.Count; $index++) {
        $result.Insert($insertIndex + $index, $block[$index])
    }

    return ConvertFrom-PatchLines -Lines $result.ToArray()
}

function Remove-MarkedBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $BeginMarker,
        [Parameter(Mandatory)][string] $EndMarker
    )

    $lines = @(ConvertTo-PatchLines -Text $Text)
    $beginIndexes = @(Get-MarkedLineIndexes -Lines $lines -Marker $BeginMarker -Start 0 -EndExclusive $lines.Count)
    $endIndexes = @(Get-MarkedLineIndexes -Lines $lines -Marker $EndMarker -Start 0 -EndExclusive $lines.Count)
    if (($beginIndexes.Count -ne 1) -or ($endIndexes.Count -ne 1) -or ($beginIndexes[0] -ge $endIndexes[0])) {
        throw 'Marked block removal requires exactly one ordered begin and end marker pair.'
    }

    $retainedLines = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if (($index -lt $beginIndexes[0]) -or ($index -gt $endIndexes[0])) {
            $retainedLines.Add($lines[$index])
        }
    }

    return ConvertFrom-PatchLines -Lines $retainedLines.ToArray()
}

function Get-LocalConfig {
    [CmdletBinding()]
    param([string] $ConfigPath)

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path (Get-RepoRoot) 'config\local.json'
    }
    $resolvedPath = [IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json)
    }
    catch {
        throw "Local configuration is not valid JSON: $resolvedPath. $($_.Exception.Message)"
    }
}

function Get-GameIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $GameDir)

    $resolvedGameDir = [IO.Path]::GetFullPath($GameDir)
    $executablePath = $null
    foreach ($name in @('XR_3DA.exe', 'xrEngine.exe')) {
        $candidate = Join-Path $resolvedGameDir $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $executablePath = $candidate
            break
        }
    }
    if ($null -eq $executablePath) {
        throw "Game executable not found. Expected XR_3DA.exe or xrEngine.exe under: $resolvedGameDir"
    }

    $executable = Get-Item -LiteralPath $executablePath
    return [pscustomobject]@{
        executablePath = $executable.FullName
        executableName = $executable.Name
        executableVersion = $executable.VersionInfo.FileVersion
        executableSha256 = Get-Sha256 -Path $executable.FullName
    }
}

function Get-EffectiveGameFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GameDir,
        [Parameter(Mandatory)][string] $LooseRelativePath,
        [Parameter(Mandatory)][string] $ArchiveRelativePath,
        [Parameter(Mandatory)][string] $SevenZipPath,
        [Parameter(Mandatory)][string] $StageDir
    )

    $resolvedGameDir = [IO.Path]::GetFullPath($GameDir)
    $loosePath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $LooseRelativePath
    if (Test-Path -LiteralPath $loosePath -PathType Leaf) {
        return [pscustomobject]@{
            Text = [IO.File]::ReadAllText($loosePath)
            Origin = 'loose'
            BaseHash = Get-Sha256 -Path $loosePath
            SourcePath = $loosePath
        }
    }

    if (-not (Test-Path -LiteralPath $SevenZipPath -PathType Leaf)) {
        throw "7-Zip executable or script not found: $SevenZipPath"
    }
    $archivePath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath 'resources\configs.db'
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Game resource archive not found: $archivePath"
    }

    $resolvedStageDir = [IO.Path]::GetFullPath($StageDir)
    New-Item -ItemType Directory -Path $resolvedStageDir -Force | Out-Null
    $arguments = @('x', $archivePath, $ArchiveRelativePath, ('-o' + $resolvedStageDir), '-y')
    & $SevenZipPath @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip failed to extract archive member '$ArchiveRelativePath' (exit code $LASTEXITCODE)."
    }

    $candidates = @(Get-ChildItem -LiteralPath $resolvedStageDir -Recurse -File)
    if ($candidates.Count -ne 1) {
        throw "Archive extraction for '$ArchiveRelativePath' must produce exactly one file; found $($candidates.Count)."
    }

    return [pscustomobject]@{
        Text = [IO.File]::ReadAllText($candidates[0].FullName)
        Origin = 'archive'
        BaseHash = Get-Sha256 -Path $candidates[0].FullName
        SourcePath = $archivePath + '::' + $ArchiveRelativePath
    }
}

function Invoke-PatchManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)] $FileDefinition
    )

    $markerProperty = $FileDefinition.PSObject.Properties['marker']
    $marker = if ($null -ne $markerProperty) { [string]$markerProperty.Value } else { 'soc_sleeping_bag' }
    $result = $Text
    foreach ($patch in @($FileDefinition.patches)) {
        switch ([string]$patch.kind) {
            'line' {
                $result = Add-MarkedLine -Text $result -Anchor $patch.anchor -Line $patch.line -Marker $marker -Position $patch.position
            }
            'luaFunction' {
                $result = Add-MarkedLineInFunction -Text $result -FunctionSignature $patch.function -Anchor $patch.anchor -Line $patch.line -Marker $marker -Position $patch.position
            }
            'block' {
                $result = Add-MarkedBlock -Text $result -Anchor $patch.anchor -Lines @($patch.lines) -BeginMarker $patch.beginMarker -EndMarker $patch.endMarker -Position $patch.position
            }
            default {
                throw "Unsupported patch kind: $($patch.kind)"
            }
        }
    }

    return $result
}
