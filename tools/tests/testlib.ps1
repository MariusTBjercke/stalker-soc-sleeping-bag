Set-StrictMode -Version Latest

function Assert-Equal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] $Actual,
        [string] $Message = 'Values differ.'
    )

    if (-not [object]::Equals($Expected, $Actual)) {
        throw "$Message Expected: <$Expected>. Actual: <$Actual>."
    }
}

function Assert-True {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [string] $Message = 'Expected condition to be true.'
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Match {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Text,
        [Parameter(Mandatory)][string] $Pattern,
        [string] $Message = 'Text did not match the pattern.'
    )

    if ($Text -notmatch $Pattern) {
        throw "$Message Pattern: <$Pattern>. Text: <$Text>."
    }
}

function Assert-Throws {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $Action,
        [string] $Pattern = '.',
        [string] $Message = 'Expected the action to throw.'
    )

    try {
        & $Action
    }
    catch {
        Assert-Match -Text $_.Exception.Message -Pattern $Pattern -Message $Message
        return
    }

    throw $Message
}
