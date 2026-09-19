[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$layoutPath = Join-Path $repoRoot 'gamedata\config\ui\ui_soc_sleeping_bag.xml'
$uiScriptPath = Join-Path $repoRoot 'gamedata\scripts\soc_sleeping_bag_ui.script'
$textRoot = Join-Path $repoRoot 'gamedata\config\text'

$requiredIds = @(
    'st_soc_sleeping_bag_name',
    'st_soc_sleeping_bag_description',
    'st_soc_sleeping_bag_title',
    'st_soc_sleeping_bag_sleep_1',
    'st_soc_sleeping_bag_sleep_3',
    'st_soc_sleeping_bag_sleep_9',
    'st_soc_sleeping_bag_sleep_heal',
    'st_soc_sleeping_bag_cancel',
    'st_soc_sleeping_bag_no_level',
    'st_soc_sleeping_bag_no_actor',
    'st_soc_sleeping_bag_dead',
    'st_soc_sleeping_bag_talking',
    'st_soc_sleeping_bag_bleeding',
    'st_soc_sleeping_bag_radiation',
    'st_soc_sleeping_bag_recent_hit',
    'st_soc_sleeping_bag_interrupted'
)

$expectedLocales = @('cze', 'eng', 'fra', 'ger', 'hg', 'ita', 'jpn', 'kor', 'pol', 'rus', 'spa', 'ukr', 'zh_cn', 'zh_tw', 'zho')

$buttonIds = @('btn_sleep_1', 'btn_sleep_3', 'btn_sleep_9', 'btn_sleep_heal', 'btn_cancel')

Assert-True -Condition (Test-Path -LiteralPath $layoutPath -PathType Leaf) -Message 'RED: gamedata/config/ui/ui_soc_sleeping_bag.xml does not exist.'
Assert-True -Condition (Test-Path -LiteralPath $uiScriptPath -PathType Leaf) -Message 'RED: gamedata/scripts/soc_sleeping_bag_ui.script does not exist.'

# The layout must parse and map each button exactly once to the verified EE
# button texture, and must provide a controller focus chain over all buttons.
$layout = [xml](Get-Content -LiteralPath $layoutPath -Raw)
foreach ($buttonId in $buttonIds) {
    $nodes = @($layout.SelectNodes("//*[local-name()='$buttonId']"))
    Assert-Equal -Expected 1 -Actual @($nodes).Count -Message "The layout must define button $buttonId exactly once."
    $texture = @($nodes[0].SelectNodes(".//*[local-name()='texture']"))
    Assert-True -Condition (@($texture).Count -ge 1 -and $texture[0].InnerText -eq 'ui_button_main01') -Message "Button $buttonId must use the verified EE button texture ui_button_main01."
}

$navi = @($layout.SelectNodes("//*[local-name()='wnd_selector_info']"))
$naviIds = @($navi | ForEach-Object { $_.GetAttribute('wnd') } | Sort-Object)
Assert-Equal -Expected (($buttonIds | Sort-Object) -join '|') -Actual ($naviIds -join '|') -Message 'The controller navigation must chain every button exactly once.'

# Every locale folder must carry the complete string set.
foreach ($locale in $expectedLocales) {
    $localePath = Join-Path $textRoot ($locale + '\st_soc_sleeping_bag.xml')
    Assert-True -Condition (Test-Path -LiteralPath $localePath -PathType Leaf) -Message "RED: the $locale locale is missing st_soc_sleeping_bag.xml."
    $doc = [xml](Get-Content -LiteralPath $localePath -Raw)
    $ids = @($doc.SelectNodes("//*[local-name()='string']") | ForEach-Object { $_.GetAttribute('id') })
    $uniqueIds = @($ids | Sort-Object -Unique)
    Assert-Equal -Expected (($requiredIds | Sort-Object) -join '|') -Actual ($uniqueIds -join '|') -Message "The $locale locale must contain exactly the required string set."
    foreach ($entry in $doc.SelectNodes("//*[local-name()='string']")) {
        $textNode = @($entry.SelectNodes(".//*[local-name()='text']"))
        Assert-True -Condition (@($textNode).Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($textNode[0].InnerText)) -Message "The $locale locale string $($entry.GetAttribute('id')) must carry non-empty text."
    }
}

# The UI module behavior is checked offline with a mocked class system.
$luaScript = Join-Path $repoRoot 'tools\tests\lua\ui_module_test.lua'
Assert-True -Condition (Test-Path -LiteralPath $luaScript -PathType Leaf) -Message 'RED: tools/tests/lua/ui_module_test.lua does not exist.'

$configPath = Join-Path $repoRoot 'config\local.json'
$luaExe = $null
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    $configured = [string]((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).lua51Path)
    if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path -LiteralPath $configured -PathType Leaf)) {
        $luaExe = $configured
    }
}
if ($null -eq $luaExe) {
    foreach ($name in @('lua5.1', 'lua')) {
        $resolved = Get-Command -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $resolved) {
            $previousPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $version = (& $resolved.Source -v 2>&1 | Out-String).Trim()
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            if ($version -match 'Lua 5\.1') {
                $luaExe = $resolved.Source
                break
            }
        }
    }
}

if ($null -eq $luaExe) {
    Write-Output 'SKIP: Lua 5.1 interpreter not configured'
    exit 0
}

$previousPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $output = (& $luaExe $luaScript $repoRoot 2>&1 | Out-String).TrimEnd()
    $exitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $previousPreference
}
if (-not [string]::IsNullOrWhiteSpace($output)) {
    Write-Output $output
}
if ($exitCode -ne 0) {
    throw "UI module tests failed under '$luaExe' (exit code $exitCode)."
}

Write-Output 'PASS: sleep menu and localization'
