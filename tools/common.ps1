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

    if (-not $candidatePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path is outside the declared root: $RelativePath"
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
