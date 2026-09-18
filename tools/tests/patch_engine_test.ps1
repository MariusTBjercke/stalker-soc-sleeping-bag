[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'testlib.ps1')
. (Join-Path $PSScriptRoot '..\common.ps1')

$fixtures = Join-Path $PSScriptRoot 'fixtures'
$systemClean = Get-Content -LiteralPath (Join-Path $fixtures 'system.clean.ltx') -Raw
$bindClean = Get-Content -LiteralPath (Join-Path $fixtures 'bind.clean.script') -Raw
$bindModified = Get-Content -LiteralPath (Join-Path $fixtures 'bind.modified.script') -Raw
$marker = 'soc_sleeping_bag'

$expectedRepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
Assert-Equal -Expected $expectedRepoRoot -Actual (Get-RepoRoot) -Message 'Get-RepoRoot must return the repository root.'
$expectedFixtureHash = (Get-FileHash -LiteralPath (Join-Path $fixtures 'system.clean.ltx') -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Equal -Expected $expectedFixtureHash -Actual (Get-Sha256 -Path (Join-Path $fixtures 'system.clean.ltx')) -Message 'Get-Sha256 must return a lowercase SHA-256 hash.'
Assert-Equal -Expected ([String]::Join("`r`n", @('one', 'two'))) -Actual (ConvertTo-Crlf -Text "one`ntwo") -Message 'ConvertTo-Crlf must normalize LF line endings.'

$after = Add-MarkedLine -Text $systemClean -Anchor '#include "misc\items.ltx"' -Line '#include "misc\soc_sleeping_bag.ltx" ; soc_sleeping_bag' -Marker $marker -Position After
$afterExpected = [String]::Join("`r`n", @(
        '; Minimal authored system.ltx fixture for patch-engine tests.',
        '#include "misc\items.ltx"',
        '#include "misc\soc_sleeping_bag.ltx" ; soc_sleeping_bag',
        '#include "misc\repair_vendor.ltx" ; unrelated edit',
        ''
    ))
Assert-Equal -Expected $afterExpected -Actual $after -Message 'A unique anchor must accept an insertion after itself.'

$beforeInput = [String]::Join("`n", @('first', 'anchor', 'last', ''))
$before = Add-MarkedLine -Text $beforeInput -Anchor 'anchor' -Line 'added ; soc_sleeping_bag' -Marker $marker -Position Before
$beforeExpected = [String]::Join("`r`n", @('first', 'added ; soc_sleeping_bag', 'anchor', 'last', ''))
Assert-Equal -Expected $beforeExpected -Actual $before -Message 'A unique anchor must accept an insertion before itself.'

$trailingWhitespace = Add-MarkedLine -Text ([String]::Join("`r`n", @('anchor   ', '')) ) -Anchor 'anchor' -Line 'owned ; soc_sleeping_bag' -Marker $marker
Assert-Equal -Expected ([String]::Join("`r`n", @('anchor   ', 'owned ; soc_sleeping_bag', ''))) -Actual $trailingWhitespace -Message 'Anchor matching must ignore only trailing whitespace.'

$scoped = Add-MarkedLineInFunction -Text $bindClean -FunctionSignature 'function actor_binder:net_spawn(data)' -Anchor 'death_manager.init_drop_settings()' -Line '    soc_sleeping_bag.on_actor_net_spawn() -- soc_sleeping_bag' -Marker $marker -Position After
Assert-Match -Text $scoped -Pattern '(?s)function actor_binder:net_spawn\(data\).*?death_manager\.init_drop_settings\(\)\r\n    soc_sleeping_bag\.on_actor_net_spawn\(\) -- soc_sleeping_bag' -Message 'A Lua function patch must add the hook inside the selected function.'
Assert-Match -Text $scoped -Pattern '(?s)function actor_binder:unrelated\(\)\r\ndeath_manager\.init_drop_settings\(\)\r\nend' -Message 'An anchor outside the selected Lua function must remain untouched.'

$updated = Add-MarkedLineInFunction -Text $bindModified -FunctionSignature 'function actor_binder:net_spawn(data)' -Anchor 'death_manager.init_drop_settings()' -Line '    soc_sleeping_bag.on_actor_net_spawn() -- soc_sleeping_bag' -Marker $marker -Position After
Assert-Match -Text $updated -Pattern 'repair_dialog\.enable\(\) -- unrelated repair mod line' -Message 'Updating a marked line must preserve an unrelated repair line.'
Assert-Match -Text $updated -Pattern 'loot_tracker\.on_spawn\(\) -- loot_tracker' -Message 'Updating a marked line must preserve an unrelated loot-tracker line.'
Assert-True -Condition ($updated -notmatch 'old_spawn_hook') -Message 'An existing marked line must be updated in place.'
Assert-Match -Text $updated -Pattern 'repair_dialog\.enable\(\) -- unrelated repair mod line\r\n    soc_sleeping_bag\.on_actor_net_spawn\(\) -- soc_sleeping_bag\r\n    loot_tracker\.on_spawn\(\) -- loot_tracker' -Message 'Updating a marked line must preserve its surrounding position.'

Assert-Match -Text $before -Pattern "`r`n" -Message 'Inserted output must use CRLF line endings.'
Assert-True -Condition ($before -notmatch '(?<!\r)\n') -Message 'Inserted output must not contain LF-only line endings.'

$secondApplication = Add-MarkedLine -Text $after -Anchor '#include "misc\items.ltx"' -Line '#include "misc\soc_sleeping_bag.ltx" ; soc_sleeping_bag' -Marker $marker -Position After
$firstBytes = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($after))
$secondBytes = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($secondApplication))
Assert-Equal -Expected $firstBytes -Actual $secondBytes -Message 'A second line-patch application must be byte-identical.'

$removed = Remove-MarkedLines -Text $updated -Marker $marker
Assert-True -Condition ($removed -notmatch 'soc_sleeping_bag') -Message 'Marker removal must remove the owned line.'
Assert-Match -Text $removed -Pattern 'repair_dialog\.enable\(\) -- unrelated repair mod line' -Message 'Marker removal must preserve unrelated repair changes.'
Assert-Match -Text $removed -Pattern 'loot_tracker\.on_spawn\(\) -- loot_tracker' -Message 'Marker removal must preserve unrelated loot-tracker changes.'

$missingAnchorText = [String]::Join("`r`n", @('one', 'two', ''))
Assert-Throws -Action { Add-MarkedLine -Text $missingAnchorText -Anchor 'missing' -Line 'owned ; soc_sleeping_bag' -Marker $marker } -Pattern 'exactly once' -Message 'A missing anchor must throw.'
$duplicateAnchorText = [String]::Join("`r`n", @('anchor', 'anchor', ''))
Assert-Throws -Action { Add-MarkedLine -Text $duplicateAnchorText -Anchor 'anchor' -Line 'owned ; soc_sleeping_bag' -Marker $marker } -Pattern 'exactly once' -Message 'A duplicate anchor must throw.'
Assert-Throws -Action { Add-MarkedLineInFunction -Text $bindClean -FunctionSignature 'function actor_binder:missing()' -Anchor 'anything' -Line 'owned ; soc_sleeping_bag' -Marker $marker } -Pattern 'function signature.*exactly once' -Message 'A missing Lua function signature must throw.'
$duplicateFunction = [String]::Join("`r`n", @('function actor_binder:net_spawn(data)', 'end', 'function actor_binder:net_spawn(data)', 'end', ''))
Assert-Throws -Action { Add-MarkedLineInFunction -Text $duplicateFunction -FunctionSignature 'function actor_binder:net_spawn(data)' -Anchor 'anything' -Line 'owned ; soc_sleeping_bag' -Marker $marker } -Pattern 'function signature.*exactly once' -Message 'A duplicate Lua function signature must throw.'

$declaredRoot = Join-Path $PSScriptRoot 'fixtures\declared-root'
Assert-Throws -Action { Resolve-ConfinedPath -Root $declaredRoot -RelativePath '..\escaped.txt' } -Pattern 'outside' -Message 'A path resolved outside its declared root must throw.'

$reparseTestRoot = Join-Path ([IO.Path]::GetTempPath()) ('soc-sleeping-bag-path-test-' + [guid]::NewGuid().ToString('N'))
$reparseDeclaredRoot = Join-Path $reparseTestRoot 'root'
$reparseOutsideRoot = Join-Path $reparseTestRoot 'outside'
try {
    New-Item -ItemType Directory -Path $reparseDeclaredRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $reparseOutsideRoot -Force | Out-Null
    $escapeJunction = Join-Path $reparseDeclaredRoot 'escape'
    New-Item -ItemType Junction -Path $escapeJunction -Target $reparseOutsideRoot | Out-Null

    Assert-Throws -Action { Resolve-ConfinedPath -Root $reparseDeclaredRoot -RelativePath 'escape\child.txt' } -Pattern 'outside' -Message 'A child path through an existing junction must throw.'
    Assert-Equal -Expected ([IO.Path]::GetFullPath($reparseDeclaredRoot)) -Actual (Resolve-ConfinedPath -Root $reparseDeclaredRoot -RelativePath '.') -Message 'The declared root itself must be a valid confined path.'
}
finally {
    if (Test-Path -LiteralPath $reparseTestRoot) {
        Remove-Item -LiteralPath $reparseTestRoot -Recurse -Force
    }
}

$blockSource = [String]::Join("`r`n", @('<root>', '</root>', ''))
$block = Add-MarkedBlock -Text $blockSource -Anchor '</root>' -Lines @('  <transition />') -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' -Position Before
$replacedBlock = Add-MarkedBlock -Text $block -Anchor '</root>' -Lines @('  <replacement />') -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' -Position Before
Assert-True -Condition ($replacedBlock -notmatch '<transition />') -Message 'Reapplying a marked block must replace its complete prior block.'
Assert-Match -Text $replacedBlock -Pattern '<replacement />' -Message 'Reapplying a marked block must retain the replacement content.'
Assert-Equal -Expected $blockSource -Actual (Remove-MarkedBlock -Text $replacedBlock -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->') -Message 'Marked-block removal must restore unrelated surrounding content.'
Assert-Throws -Action { Remove-MarkedBlock -Text '<root />' -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' } -Pattern 'exactly one' -Message 'Missing block markers must throw.'
$duplicateBegin = [String]::Join("`r`n", @('<!-- soc_sleeping_bag begin -->', '<!-- soc_sleeping_bag begin -->', '<!-- soc_sleeping_bag end -->', ''))
Assert-Throws -Action { Remove-MarkedBlock -Text $duplicateBegin -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' } -Pattern 'exactly one' -Message 'Duplicate block markers must throw.'

$orphanBegin = [String]::Join("`r`n", @('<root>', '<!-- soc_sleeping_bag begin -->', '</root>', ''))
$orphanEnd = [String]::Join("`r`n", @('<root>', '<!-- soc_sleeping_bag end -->', '</root>', ''))
$reversedMarkers = [String]::Join("`r`n", @('<root>', '<!-- soc_sleeping_bag end -->', '<!-- soc_sleeping_bag begin -->', '</root>', ''))
$duplicateEnd = [String]::Join("`r`n", @('<root>', '<!-- soc_sleeping_bag begin -->', '<!-- soc_sleeping_bag end -->', '<!-- soc_sleeping_bag end -->', '</root>', ''))
foreach ($malformedBlock in @($orphanBegin, $orphanEnd, $reversedMarkers, $duplicateEnd)) {
    Assert-Throws -Action { Remove-MarkedBlock -Text $malformedBlock -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' } -Pattern 'ordered begin and end marker pair' -Message 'Malformed block markers must prevent removal.'
    Assert-Throws -Action { Add-MarkedBlock -Text $malformedBlock -Anchor '</root>' -Lines @('  <replacement />') -BeginMarker '<!-- soc_sleeping_bag begin -->' -EndMarker '<!-- soc_sleeping_bag end -->' -Position Before } -Pattern 'ordered begin and end marker pair' -Message 'Malformed block markers must prevent replacement.'
}

Write-Output 'PASS: semantic patch primitives'
