[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testScript = Join-Path $repoRoot 'tools\tests\lua\sleeping_bag_test.lua'
$moduleScript = Join-Path $repoRoot 'gamedata\scripts\soc_sleeping_bag.script'
if (-not (Test-Path -LiteralPath $moduleScript -PathType Leaf)) {
    throw 'RED: gamedata/scripts/soc_sleeping_bag.script does not exist.'
}

function Find-Lua51 {
    $candidates = @()

    $configPath = Join-Path $repoRoot 'config\local.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        $configured = [string]$config.lua51Path
        if (-not [string]::IsNullOrWhiteSpace($configured)) {
            $candidates += $configured
        }
    }
    foreach ($name in @('lua5.1', 'lua')) {
        $resolved = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            $candidates += $resolved.Source
        }
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $version = (& $candidate -v 2>&1 | Out-String).Trim()
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($version -match 'Lua 5\.1') {
            return $candidate
        }
        Write-Warning "Ignoring interpreter '$candidate' because it is not Lua 5.1: $version"
    }
    return $null
}

$luaExe = Find-Lua51
if ($null -eq $luaExe) {
    Write-Output 'SKIP: Lua 5.1 interpreter not configured'
    exit 0
}

$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $output = (& $luaExe $testScript $repoRoot 2>&1 | Out-String).TrimEnd()
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
if (-not [string]::IsNullOrWhiteSpace($output)) {
    Write-Output $output
}
if ($exitCode -ne 0) {
    throw "Gameplay tests failed under '$luaExe' (exit code $exitCode)."
}

Write-Output 'PASS: sleeping bag gameplay rules'
