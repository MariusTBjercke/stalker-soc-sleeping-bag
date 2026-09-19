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

function Get-GameFileText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    return ConvertFrom-GameFileBytes -Bytes ([IO.File]::ReadAllBytes($Path))
}

function ConvertFrom-GameFileBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes)

    $rawBytes = $Bytes
    if (($rawBytes.Length -ge 3) -and ($rawBytes[0] -eq 0xEF) -and ($rawBytes[1] -eq 0xBB) -and ($rawBytes[2] -eq 0xBF)) {
        return [pscustomobject]@{
            Text = [Text.Encoding]::UTF8.GetString($rawBytes, 3, $rawBytes.Length - 3)
            Encoding = [Text.UTF8Encoding]::new($true)
        }
    }
    if (($rawBytes.Length -ge 2) -and ($rawBytes[0] -eq 0xFF) -and ($rawBytes[1] -eq 0xFE)) {
        return [pscustomobject]@{
            Text = [Text.Encoding]::Unicode.GetString($rawBytes, 2, $rawBytes.Length - 2)
            Encoding = [Text.UnicodeEncoding]::new($false, $true)
        }
    }

    if ([Type]::GetType('System.Text.CodePagesEncodingProvider, System.Text.Encoding.CodePages')) {
        [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
    }

    try {
        $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
        return [pscustomobject]@{
            Text = $strictUtf8.GetString($rawBytes)
            Encoding = [Text.UTF8Encoding]::new($false)
        }
    }
    catch [System.Text.DecoderFallbackException] {
        $legacyEncoding = [Text.Encoding]::GetEncoding(1251)
        return [pscustomobject]@{
            Text = $legacyEncoding.GetString($rawBytes)
            Encoding = $legacyEncoding
        }
    }
}

function Set-GameFileText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [Text.Encoding] $Encoding = ([Text.UTF8Encoding]::new($false))
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function Get-EffectiveGameFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GameDir,
        [Parameter(Mandatory)][string] $LooseRelativePath,
        [Parameter(Mandatory)][string] $ArchiveRelativePath,
        $ArchiveEntry
    )

    $resolvedGameDir = [IO.Path]::GetFullPath($GameDir)
    $loosePath = Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath $LooseRelativePath
    if (Test-Path -LiteralPath $loosePath -PathType Leaf) {
        $decoded = Get-GameFileText -Path $loosePath
        return [pscustomobject]@{
            Text = $decoded.Text
            Encoding = $decoded.Encoding
            Origin = 'loose'
            BaseHash = Get-Sha256 -Path $loosePath
            SourcePath = $loosePath
        }
    }

    # No loose copy: use the game's own file from its archive. Only the known,
    # hash-pinned build can be read this way.
    if ($null -eq $ArchiveEntry) {
        throw "There is no loose copy of $LooseRelativePath and this game build has no verified archive entry for '$ArchiveRelativePath'."
    }
    $bytes = Read-ArchiveBytes -GameDir $resolvedGameDir -ArchiveEntry $ArchiveEntry -Description "The archive member '$ArchiveRelativePath'"
    $decoded = ConvertFrom-GameFileBytes -Bytes $bytes
    return [pscustomobject]@{
        Text = $decoded.Text
        Encoding = $decoded.Encoding
        Origin = 'archive'
        BaseHash = Get-BytesSha256 -Bytes $bytes
        SourcePath = (Resolve-ConfinedPath -Root $resolvedGameDir -RelativePath ([string]$ArchiveEntry.archive)) + '::' + $ArchiveRelativePath
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

function Get-BytesSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]] $Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (-join ($sha.ComputeHash($Bytes) | ForEach-Object { '{0:x2}' -f $_ }))
    }
    finally {
        $sha.Dispose()
    }
}

# Reads one file straight out of a game resource archive. The archives store
# these files uncompressed, so a pinned offset and size are enough; the offset
# is trusted only when the bytes match the pinned SHA-256 for the known build.
function Read-ArchiveBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GameDir,
        [Parameter(Mandatory)] $ArchiveEntry,
        [Parameter(Mandatory)][string] $Description
    )

    $archivePath = Resolve-ConfinedPath -Root $GameDir -RelativePath ([string]$ArchiveEntry.archive)
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Game resource archive not found: $archivePath"
    }
    $length = [int]$ArchiveEntry.size
    $bytes = New-Object byte[] $length
    $stream = [IO.File]::OpenRead($archivePath)
    try {
        $stream.Seek([long]$ArchiveEntry.offset, [IO.SeekOrigin]::Begin) | Out-Null
        $read = 0
        while ($read -lt $length) {
            $count = $stream.Read($bytes, $read, $length - $read)
            if ($count -le 0) {
                throw "$Description is beyond the end of $archivePath."
            }
            $read += $count
        }
    }
    finally {
        $stream.Dispose()
    }
    if ((Get-BytesSha256 -Bytes $bytes) -cne [string]$ArchiveEntry.sha256) {
        throw "$Description inside $archivePath does not match the known build (expected SHA-256 $($ArchiveEntry.sha256))."
    }
    return , $bytes
}

function Get-ArchiveAtlas {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GameDir,
        [Parameter(Mandatory)] $AtlasInfo
    )

    return , (Read-ArchiveBytes -GameDir $GameDir -ArchiveEntry $AtlasInfo -Description 'The icon atlas')
}

# Copies the icon's pre-encoded DXT5 blocks into a copy of the DXT5 atlas at
# the given grid cell. Every other byte of the atlas is left untouched.
function Merge-AtlasBlocks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]] $Atlas,
        [Parameter(Mandatory)][byte[]] $Blocks,
        [Parameter(Mandatory)][int] $CellX,
        [Parameter(Mandatory)][int] $CellY,
        [Parameter(Mandatory)][int] $CellSize,
        [Parameter(Mandatory)][int] $IconWidth,
        [Parameter(Mandatory)][int] $IconHeight
    )

    $headerSize = 128
    $blockSize = 4
    $blockBytes = 16
    if (($Atlas.Length -lt $headerSize) -or ([Text.Encoding]::ASCII.GetString($Atlas, 0, 4) -cne 'DDS ') -or ([Text.Encoding]::ASCII.GetString($Atlas, 84, 4) -cne 'DXT5')) {
        throw 'The icon atlas is not a DXT5 DDS file.'
    }
    $atlasHeight = [BitConverter]::ToUInt32($Atlas, 12)
    $atlasWidth = [BitConverter]::ToUInt32($Atlas, 16)
    $x = $CellX * $CellSize
    $y = $CellY * $CellSize
    if (($x % $blockSize) -or ($y % $blockSize) -or ($IconWidth % $blockSize) -or ($IconHeight % $blockSize)) {
        throw 'The icon and its cell must be aligned to the 4 px DXT block grid.'
    }
    if ((($x + $IconWidth) -gt $atlasWidth) -or (($y + $IconHeight) -gt $atlasHeight)) {
        throw 'The icon does not fit inside the atlas.'
    }
    $blocksPerRow = [int]($IconWidth / $blockSize)
    $blockRows = [int]($IconHeight / $blockSize)
    $rowBytes = $blocksPerRow * $blockBytes
    if ($Blocks.Length -ne ($rowBytes * $blockRows)) {
        throw "The icon block data has $($Blocks.Length) bytes; expected $($rowBytes * $blockRows)."
    }
    $atlasBlocksX = [int]($atlasWidth / $blockSize)
    $result = [byte[]]$Atlas.Clone()
    for ($row = 0; $row -lt $blockRows; $row++) {
        $offset = $headerSize + ((([int]($y / $blockSize) + $row) * $atlasBlocksX) + [int]($x / $blockSize)) * $blockBytes
        [Array]::Copy($Blocks, $row * $rowBytes, $result, $offset, $rowBytes)
    }
    return , $result
}
