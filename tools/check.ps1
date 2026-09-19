[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

$childHost = (Get-Process -Id $PID).Path
if ([string]::IsNullOrWhiteSpace($childHost) -or -not (Test-Path -LiteralPath $childHost -PathType Leaf)) {
    $childHost = Join-Path $PSHOME 'powershell.exe'
}

# Repository policy: machine-local and generated paths must stay untracked.
$tracked = @(git -C $repoRoot ls-files)
$policyViolations = @($tracked | Where-Object {
        $_ -eq 'config/local.json' -or
        $_ -like 'out/*' -or
        $_ -like 'dist/*' -or
        (($_ -like 'references/*') -and ($_ -ne 'references/README.md'))
    })
$policyStatus = if (@($policyViolations).Count -eq 0) { 'PASS' } else { 'FAIL' }

$suites = @(
    [pscustomobject]@{ Name = 'policy';    Status = $policyStatus; ExitCode = 0; Output = '' },
    [pscustomobject]@{ Name = 'patch';     Path = 'tools\tests\patch_engine_test.ps1' },
    [pscustomobject]@{ Name = 'deploy';    Path = 'tools\tests\deploy_test.ps1' },
    [pscustomobject]@{ Name = 'uninstall'; Path = 'tools\tests\uninstall_test.ps1' },
    [pscustomobject]@{ Name = 'gameplay';  Path = 'tools\tests\gameplay_test.ps1' },
    [pscustomobject]@{ Name = 'static';    Path = 'tools\tests\static_test.ps1' }
)

$results = [Collections.Generic.List[object]]::new()
$results.Add($suites[0])

foreach ($suite in @($suites | Where-Object { $_.PSObject.Properties['Path'] })) {
    $suitePath = Join-Path $repoRoot $suite.Path
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = (& $childHost -NoProfile -ExecutionPolicy Bypass -File $suitePath 2>&1 | Out-String).TrimEnd()
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $status = 'FAIL'
    if ($exitCode -eq 0 -and $output -match 'SKIP:') {
        $status = 'SKIP'
    }
    elseif ($exitCode -eq 0) {
        $status = 'PASS'
    }
    Write-Output $output
    $results.Add([pscustomobject]@{ Name = $suite.Name; Status = $status; ExitCode = $exitCode; Output = $output })
}

$passed = @($results | Where-Object { $_.Status -eq 'PASS' }).Count
$failed = @($results | Where-Object { $_.Status -eq 'FAIL' }).Count
$skipped = @($results | Where-Object { $_.Status -eq 'SKIP' }).Count
Write-Output ("== check summary: {0} passed, {1} failed, {2} skipped ==" -f $passed, $failed, $skipped)
foreach ($violation in $policyViolations) {
    Write-Output ("POLICY: tracked ignored path: {0}" -f $violation)
}
if ($failed -gt 0 -or $policyViolations.Count -gt 0) {
    exit 1
}
exit 0
