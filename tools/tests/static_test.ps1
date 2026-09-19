[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$itemPath = Join-Path $repoRoot 'gamedata\config\misc\soc_sleeping_bag.ltx'
$checkerPath = Join-Path $repoRoot 'tools\check.ps1'
$modulePath = Join-Path $repoRoot 'gamedata\scripts\soc_sleeping_bag.script'
$manifestPath = Join-Path $repoRoot 'patches\manifest.json'
$architecturePath = Join-Path $repoRoot 'docs\ARCHITECTURE.md'

function Get-LtxSectionValues {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $Lines,
        [Parameter(Mandatory)][string] $SectionName
    )

    $values = @{}
    $inSection = $false
    foreach ($line in $Lines) {
        if ($line -match '^\[([^\]]+)\]') {
            $inSection = ($matches[1] -ceq $SectionName)
            continue
        }
        if (-not $inSection) {
            continue
        }
        if ($line -match '^\s*([\w$]+)\s*=\s*(.*?)\s*(?:;.*)?$') {
            $values[$matches[1]] = $matches[2]
        }
    }
    return $values
}

function Assert-LtxNumber {
    param(
        [Parameter(Mandatory)] $Values,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][double] $Expected,
        [Parameter(Mandatory)][string] $Message
    )

    if (-not $Values.ContainsKey($Key)) {
        throw "$Message Missing key '$Key'."
    }
    $parsed = 0.0
    if (-not [double]::TryParse($Values[$Key], [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        throw "$Message Key '$Key' is not numeric: $($Values[$Key])."
    }
    Assert-Equal -Expected $Expected -Actual $parsed -Message $Message
}

# Task 6 deliverables: the owned item definition and the aggregate checker.
Assert-True -Condition (Test-Path -LiteralPath $itemPath -PathType Leaf) -Message 'RED: gamedata/config/misc/soc_sleeping_bag.ltx does not exist.'
Assert-True -Condition (Test-Path -LiteralPath $checkerPath -PathType Leaf) -Message 'RED: tools/check.ps1 does not exist.'

$itemLines = @(Get-Content -LiteralPath $itemPath)
Assert-True -Condition (@($itemLines | Where-Object { $_ -match '^\[soc_sleeping_bag\]' }).Count -eq 1) -Message 'The item file must define exactly the [soc_sleeping_bag] section.'

$item = Get-LtxSectionValues -Lines $itemLines -SectionName 'soc_sleeping_bag'
Assert-Equal -Expected 'II_ANTIR' -Actual $item['class'] -Message 'The item must use the usable II_ANTIR class.'
Assert-Equal -Expected 'true' -Actual $item['quest_item'] -Message 'The item must be a quest item so it cannot be traded away.'
Assert-LtxNumber -Values $item -Key 'eat_health' -Expected 0 -Message 'The item must have zero health effect.'
Assert-LtxNumber -Values $item -Key 'eat_satiety' -Expected 0 -Message 'The item must have zero satiety effect.'
Assert-LtxNumber -Values $item -Key 'eat_power' -Expected 0 -Message 'The item must have zero power effect.'
Assert-LtxNumber -Values $item -Key 'eat_radiation' -Expected 0 -Message 'The item must have zero radiation effect.'
Assert-LtxNumber -Values $item -Key 'eat_alcohol' -Expected 0 -Message 'The item must have zero alcohol effect.'
Assert-LtxNumber -Values $item -Key 'wounds_heal_perc' -Expected 0 -Message 'The item must have zero wound healing effect.'
Assert-LtxNumber -Values $item -Key 'eat_portions_num' -Expected 1 -Message 'The item must be consumed in exactly one use.'
Assert-LtxNumber -Values $item -Key 'inv_weight' -Expected 1.2 -Message 'The item must weigh 1.2.'
Assert-LtxNumber -Values $item -Key 'cost' -Expected 0 -Message 'The item must cost 0.'

$architectureText = Get-Content -LiteralPath $architecturePath -Raw
Assert-True -Condition ($architectureText.Contains('item_merger.ogf') -and $architectureText.Contains('[device_atifact_merger]')) -Message 'ARCHITECTURE.md must record the merger visual provenance.'
Assert-True -Condition ($architectureText.Contains('[antirad]')) -Message 'ARCHITECTURE.md must record the antirad icon provenance.'
foreach ($pair in @(@('inv_grid_x', '18'), @('inv_grid_y', '12'), @('inv_grid_width', '1'), @('inv_grid_height', '1'))) {
    Assert-True -Condition ($architectureText.Contains("$($pair[0]) = $($pair[1])")) -Message "ARCHITECTURE.md must record $($pair[0]) = $($pair[1]) as the reused icon coordinate."
    Assert-Equal -Expected $pair[1] -Actual $item[$pair[0]] -Message "The item's $($pair[0]) must equal the architecture-documented value."
}
Assert-Equal -Expected 'equipments\item_merger.ogf' -Actual $item['visual'] -Message "The item's visual must be the documented EE-owned merger model."

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$marker = [string]$manifest.marker
Assert-Equal -Expected 'soc_sleeping_bag' -Actual $marker -Message 'The manifest marker must be soc_sleeping_bag.'

$systemDefinition = @($manifest.sharedFiles | Where-Object { $_.path -eq 'gamedata/config/system.ltx' })
Assert-Equal -Expected 1 -Actual @($systemDefinition).Count -Message 'The manifest must patch system.ltx exactly once.'
$includePatch = @($systemDefinition[0].patches | Where-Object { $_.line -like '*soc_sleeping_bag.ltx*' })
Assert-Equal -Expected 1 -Actual @($includePatch).Count -Message 'The system include patch must be declared once.'
$expectedInclude = '#include "misc\soc_sleeping_bag.ltx" ; soc_sleeping_bag'
Assert-Equal -Expected $expectedInclude -Actual $includePatch[0].line -Message 'The system include must use the exact owned LTX path.'
Assert-True -Condition (Test-Path -LiteralPath (Join-Path $repoRoot 'gamedata\config\misc\soc_sleeping_bag.ltx') -PathType Leaf) -Message 'The included LTX path must exist as an owned file.'

$bindDefinition = @($manifest.sharedFiles | Where-Object { $_.path -eq 'gamedata/scripts/bind_stalker.script' })
Assert-Equal -Expected 1 -Actual @($bindDefinition).Count -Message 'The manifest must patch bind_stalker.script exactly once.'

$moduleText = Get-Content -LiteralPath $modulePath -Raw
$publicFunctions = @('on_actor_net_spawn', 'on_actor_net_destroy', 'on_item_use', 'on_actor_hit', 'update')
foreach ($name in $publicFunctions) {
    Assert-True -Condition ($moduleText -match "(?m)^function $name\(") -Message "The gameplay module must expose the public function $name."
}

$binderCalls = @()
foreach ($patch in @($bindDefinition[0].patches)) {
    Assert-True -Condition ($patch.line.Contains($marker)) -Message "Every binder patch line must contain the marker: $($patch.line)"
    $call = [regex]::Match($patch.line, 'soc_sleeping_bag\.(\w+)\(')
    Assert-True -Condition $call.Success -Message "Every binder patch line must call soc_sleeping_bag.<function>: $($patch.line)"
    $binderCalls += $call.Groups[1].Value
}
Assert-True -Condition ((@($binderCalls | Sort-Object -Unique)).Count -eq $binderCalls.Count) -Message 'Binder hooks must not call the same gameplay function twice.'
foreach ($call in $binderCalls) {
    Assert-True -Condition ($publicFunctions -contains $call) -Message "Binder call must name a public gameplay function: $call"
}
Assert-Equal -Expected (($publicFunctions | Sort-Object) -join '|') -Actual (($binderCalls | Sort-Object) -join '|') -Message 'The binder must integrate every public gameplay hook exactly once.'

foreach ($definition in @($manifest.sharedFiles)) {
    foreach ($patch in @($definition.patches)) {
        if ($null -ne $patch.PSObject.Properties['line']) {
            Assert-True -Condition (([string]$patch.line).Contains($marker)) -Message "Every patch line must contain the marker: $($patch.line)"
        }
    }
}

$trackedFiles = @(git -C $repoRoot ls-files)
$trackedReferences = @($trackedFiles | Where-Object { $_ -like 'references/*' })
Assert-Equal -Expected 'references/README.md' -Actual (($trackedReferences | Sort-Object) -join '|') -Message 'No tracked path may exist under references/ except references/README.md.'

$atlasFiles = @($trackedFiles | Where-Object { $_ -like '*.dds' })
Assert-Equal -Expected 0 -Actual @($atlasFiles).Count -Message 'The mod must not ship any texture atlas (.dds) files.'

foreach ($tracked in $trackedFiles) {
    if ($tracked -like 'tools/tests/fixtures/*') {
        continue
    }
    $fullPath = Join-Path $repoRoot ($tracked -replace '/', '\')
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        continue
    }
    Assert-True -Condition ($content -notmatch 'class\s+"actor_binder"') -Message "No file outside fixtures may define a complete actor_binder: $tracked"
}

foreach ($jsonPath in @($trackedFiles | Where-Object { $_ -like '*.json' })) {
    $fullPath = Join-Path $repoRoot ($jsonPath -replace '/', '\')
    try {
        Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        throw "Tracked JSON file must parse: $jsonPath ($($_.Exception.Message))"
    }
}

foreach ($xmlPath in @($trackedFiles | Where-Object { $_ -like 'gamedata/*.xml' -or $_ -like 'gamedata/**/*.xml' })) {
    $fullPath = Join-Path $repoRoot ($xmlPath -replace '/', '\')
    try {
        [xml](Get-Content -LiteralPath $fullPath -Raw) | Out-Null
    }
    catch {
        throw "Shipped XML file must parse: $xmlPath ($($_.Exception.Message))"
    }
}

Write-Output 'PASS: static integration checks'
