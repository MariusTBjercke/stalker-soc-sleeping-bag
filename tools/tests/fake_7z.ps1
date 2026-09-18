[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Arguments)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (($Arguments.Count -lt 4) -or ($Arguments[0] -ne 'x')) {
    throw 'fake_7z.ps1 expects: x <archive> <member> -o<directory> [-y]'
}

$archivePath = [IO.Path]::GetFullPath($Arguments[1])
$member = $Arguments[2]
$outputArgument = @($Arguments | Where-Object { $_.StartsWith('-o', [StringComparison]::Ordinal) })
if ($outputArgument.Count -ne 1) {
    throw 'fake_7z.ps1 requires exactly one -o output argument.'
}

$outputRoot = $outputArgument[0].Substring(2)
$sourceRoot = $archivePath + '.contents'
$sourcePath = [IO.Path]::GetFullPath((Join-Path $sourceRoot $member))
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    Write-Error "Archive member not found: $member"
    exit 2
}

$destinationPath = [IO.Path]::GetFullPath((Join-Path $outputRoot $member))
$destinationDirectory = Split-Path -Parent $destinationPath
New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force

if ((Get-Content -LiteralPath $archivePath -Raw) -match 'multiple') {
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $outputRoot 'unexpected-candidate.txt') -Force
}

exit 0
