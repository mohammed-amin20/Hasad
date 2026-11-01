function ConvertFrom-SupabaseMigrationList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    if ($Text -match '(?i)AccessTokenRequiredError|access token not provided|authentication required|failed to authenticate|\bunauthorized\b') {
        throw 'Supabase migration history query returned an authentication failure.'
    }
    if ($Text -match '(?i)("_tag"\s*:\s*"Error"|\bERROR\b|failed to connect|connection refused|timed out)') {
        throw 'Supabase migration history query returned a CLI or connectivity error.'
    }

    $AnsiPattern = [string][char]27 + '\[[0-?]*[ -/]*[@-~]'
    $CleanText = [regex]::Replace($Text, $AnsiPattern, '')
    $ColumnSeparatorPattern = '[|' + [regex]::Escape([string][char]0x2502) + ']'
    $BorderCharacters = '-+|' + [string][char]0x2502 + ([char]0x2500) + ([char]0x250C) + ([char]0x2510) + ([char]0x2514) + ([char]0x2518) + ([char]0x251C) + ([char]0x2524) + ([char]0x252C) + ([char]0x2534) + ([char]0x253C)
    $BorderPattern = '^\s*[' + [regex]::Escape($BorderCharacters) + ']+\s*$'
    $Lines = @($CleanText -split '\r?\n')
    $HeaderIndex = -1
    $HeaderCells = @()
    $FixedColumnStarts = @()
    $HeaderMode = ''
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $Candidate = @($Lines[$i] -split $ColumnSeparatorPattern)
        $Names = @($Candidate | ForEach-Object { $_.Trim() })
        $LocalColumns = @()
        $RemoteColumns = @()
        for ($column = 0; $column -lt $Names.Count; $column++) {
            if ($Names[$column] -ieq 'LOCAL') { $LocalColumns += $column }
            if ($Names[$column] -ieq 'REMOTE') { $RemoteColumns += $column }
        }
        if ($LocalColumns.Count -gt 0 -and $RemoteColumns.Count -gt 0) {
            if ($LocalColumns.Count -ne 1 -or $RemoteColumns.Count -ne 1) {
                throw 'Malformed Supabase migration list: duplicate history column labels.'
            }
            $HeaderIndex = $i
            $HeaderCells = $Names
            $HeaderMode = 'Delimited'
            break
        }
        if ($Lines[$i] -match '(?i)LOCAL\s+.*REMOTE') {
            $ColumnMatches = [regex]::Matches($Lines[$i], '(?i)\bLOCAL\b|\bREMOTE\b|\bTIME(?:\s*\(UTC\))?\b')
            $LocalMatches = @($ColumnMatches | Where-Object { $_.Value -match '(?i)^LOCAL$' })
            $RemoteMatches = @($ColumnMatches | Where-Object { $_.Value -match '(?i)^REMOTE$' })
            $LocalMatch = if ($LocalMatches.Count -eq 1) { $LocalMatches[0] } else { $null }
            $RemoteMatch = if ($RemoteMatches.Count -eq 1) { $RemoteMatches[0] } else { $null }
            if ($null -ne $LocalMatch -and $null -ne $RemoteMatch -and $RemoteMatch.Index -gt $LocalMatch.Index) {
                $HeaderIndex = $i
                $FixedColumnStarts = @($LocalMatch.Index, $RemoteMatch.Index)
                $TimeMatch = @($ColumnMatches | Where-Object { $_.Value -match '(?i)^TIME' } | Select-Object -First 1)[0]
                if ($null -ne $TimeMatch) { $FixedColumnStarts += $TimeMatch.Index }
                $HeaderMode = 'FixedWidth'
                break
            }
            throw 'Malformed Supabase migration list: whitespace header has duplicate or invalid LOCAL/REMOTE columns.'
        }
    }
    if ($HeaderIndex -lt 0) { throw 'Malformed Supabase migration list: LOCAL and REMOTE columns were not found.' }
    if ($HeaderMode -eq 'Delimited') {
        $LocalColumn = [array]::IndexOf(@($HeaderCells | ForEach-Object { $_.ToUpperInvariant() }), 'LOCAL')
        $RemoteColumn = [array]::IndexOf(@($HeaderCells | ForEach-Object { $_.ToUpperInvariant() }), 'REMOTE')
        if ($LocalColumn -lt 0 -or $RemoteColumn -lt 0 -or $LocalColumn -eq $RemoteColumn) {
            throw 'Malformed Supabase migration list: duplicate or ambiguous history columns.'
        }
    } elseif ($HeaderMode -eq 'FixedWidth') {
        if ($FixedColumnStarts.Count -lt 2 -or $FixedColumnStarts[0] -ge $FixedColumnStarts[1]) {
            throw 'Malformed Supabase migration list: invalid fixed-width history columns.'
        }
    } else { throw 'Malformed Supabase migration list: unsupported header layout.' }

    $Rows = @{}
    for ($i = $HeaderIndex + 1; $i -lt $Lines.Count; $i++) {
        $Line = $Lines[$i]
        if ($Line -match '(?i)\bLOCAL\b.*\bREMOTE\b') { throw 'Malformed Supabase migration list: repeated history header.' }
        if ($Line -notmatch '(?<!\d)\d{14}(?!\d)') {
            if ([string]::IsNullOrWhiteSpace($Line) -or $Line -match $BorderPattern) { continue }
            if ($Line -match $ColumnSeparatorPattern) { throw 'Malformed Supabase migration list: table-like row contains no version.' }
            throw 'Malformed Supabase migration list: unexpected non-row output after the history header.'
        }
        $VersionMatches = [regex]::Matches($Line, '(?<!\d)\d{14}(?!\d)')
        $VersionValues = @($VersionMatches | ForEach-Object { $_.Value } | Sort-Object -Unique)
        if ($VersionValues.Count -ne 1) { throw 'Malformed Supabase migration list: row contains multiple version identifiers.' }
        $Version = $VersionValues[0]
        if ($HeaderMode -eq 'FixedWidth') {
            if ($Line.Length -le $FixedColumnStarts[1]) { throw "Malformed Supabase migration list row for ${Version}: required columns are missing." }
            $TrimCharacters = [char[]]@(' ', '|', [char]0x2502)
            $Local = $Line.Substring($FixedColumnStarts[0], $FixedColumnStarts[1] - $FixedColumnStarts[0]).Trim($TrimCharacters)
            $RemoteEnd = if ($FixedColumnStarts.Count -gt 2) { $FixedColumnStarts[2] } else { $Line.Length }
            $Remote = $Line.Substring($FixedColumnStarts[1], [Math]::Min($RemoteEnd, $Line.Length) - $FixedColumnStarts[1]).Trim($TrimCharacters)
        } else {
            $Cells = @($Line -split $ColumnSeparatorPattern)
            if ($Cells.Count -le [Math]::Max($LocalColumn, $RemoteColumn)) { throw "Malformed Supabase migration list row for ${Version}: required columns are missing." }
            $Local = $Cells[$LocalColumn].Trim()
            $Remote = $Cells[$RemoteColumn].Trim()
        }
        foreach ($ValueName in @('Local','Remote')) {
            $Value = if ($ValueName -eq 'Local') { $Local } else { $Remote }
            $Value = $Value.Trim()
            $Quote = [char]0x60
            $QuoteCount = @($Value.ToCharArray() | Where-Object { $_ -eq $Quote }).Count
            if ($QuoteCount -gt 0) {
                if ($QuoteCount -ne 2 -or -not $Value.StartsWith([string]$Quote) -or -not $Value.EndsWith([string]$Quote)) {
                    throw "Malformed Supabase migration list row for ${Version}: malformed $ValueName cell quoting."
                }
                $Value = $Value.Substring(1, $Value.Length - 2).Trim()
            }
            if ([string]::IsNullOrWhiteSpace($Value) -or $Value -ceq '-' -or
                $Value -ceq ([string][char]0x2014) -or $Value -ceq ([string][char]0x2013) -or
                $Value -match '(?i)^(?:NULL|<NULL>|NOT APPLIED|N/A)$') { $Value = '' }
            elseif ($Value -cne $Version) { throw "Malformed Supabase migration list row for ${Version}: unexpected $ValueName value." }
            if ($ValueName -eq 'Local') { $Local = $Value } else { $Remote = $Value }
        }
        if (-not $Local -and -not $Remote) { throw "Malformed Supabase migration list row for ${Version}: both history columns are empty." }
        if ($Rows.ContainsKey($Version)) { throw "Malformed Supabase migration list: duplicate version $Version." }
        $Rows[$Version] = [pscustomobject]@{ Local = $Local; Remote = $Remote }
    }
    if ($Rows.Count -eq 0) { throw 'Malformed Supabase migration list: no migration rows were found.' }
    return $Rows
}

function Assert-SupabaseMigrationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string[]]$ExpectedApplied,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedPending,
        [Parameter(Mandatory)][string[]]$AllowedVersions
    )
    $AppliedSet = @($ExpectedApplied | Sort-Object -Unique)
    $PendingSet = @($ExpectedPending | Sort-Object -Unique)
    if (@($AppliedSet | Where-Object { $_ -in $PendingSet }).Count -gt 0) { throw 'Invalid expected history: a migration cannot be both applied and pending.' }
    $AllowedSet = @($AllowedVersions | Sort-Object -Unique)
    if (@(($AppliedSet + $PendingSet) | Where-Object { $_ -notin $AllowedSet }).Count -gt 0) { throw 'Invalid expected history: an expected version is outside the allowlist.' }

    $Rows = ConvertFrom-SupabaseMigrationList -Text $Text
    foreach ($Version in $Rows.Keys) {
        if ($Version -notin $AllowedSet) { throw "Unexpected migration version $Version appears in linked history." }
    }
    foreach ($Version in $AppliedSet) {
        if (-not $Rows.ContainsKey($Version)) { throw "Expected applied migration $Version is missing from history." }
        $Row = $Rows[$Version]
        if ($Row.Local -cne $Version -or $Row.Remote -cne $Version) { throw "Migration $Version is not applied in both local and remote history." }
    }
    foreach ($Version in $PendingSet) {
        if (-not $Rows.ContainsKey($Version)) { throw "Expected pending migration $Version is missing from local history." }
        $Row = $Rows[$Version]
        if ($Row.Local -cne $Version -or $Row.Remote) { throw "Expected migration $Version to be local-only and pending remotely." }
    }
    foreach ($Version in $AllowedSet) {
        if ($Version -notin $AppliedSet -and $Version -notin $PendingSet -and $Rows.ContainsKey($Version)) {
            throw "Unexpected local or remote history state for migration $Version."
        }
    }
    return $Rows
}

function Assert-Phase8DryRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$ExpectedFilename)
    if ($Text -notmatch '(?i)dry.run|would push|would apply|following migrations|migrations to push') {
        throw 'Dry-run output lacks a recognizable dry-run/migration announcement.'
    }
    $ExpectedVersion = $ExpectedFilename.Substring(0, 14)
    $Found = @([regex]::Matches($Text, '(?<![\w.])\d{14}_[A-Za-z0-9_.-]+\.sql(?![\w.])') | ForEach-Object { $_.Value })
    if ($Found.Count -ne 1 -or $Found[0] -cne $ExpectedFilename) {
        throw "Dry-run must list exactly approved migration filename $ExpectedFilename."
    }
    if ($Text -match '(?i)No migrations to (push|apply)|Remote database is up to date') {
        throw 'Dry-run did not announce a pending migration.'
    }
    if ($Found[0].Substring(0,14) -cne $ExpectedVersion) { throw 'Dry-run migration filename/version mismatch.' }
}

function ConvertTo-Phase8TableSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Value,
        [switch]$AllowEmpty
    )

    if ($null -eq $Value) {
        if (-not $AllowEmpty) { throw 'Expected table collection is null.' }
        $Values = [string[]]::new(0)
    } elseif ($Value -is [string]) {
        $Values = [string[]]@($Value)
    } elseif ($Value -is [string[]]) {
        $Values = $Value
    } elseif ($Value -is [System.Collections.IList]) {
        $Builder = [System.Collections.Generic.List[string]]::new()
        foreach ($Item in $Value) {
            if ($Item -isnot [string]) { throw 'Expected table collection contains a non-string item.' }
            $Builder.Add($Item)
        }
        $Values = $Builder.ToArray()
    } else {
        throw 'Expected table selection must be a string or a string collection.'
    }

    if ($Values.Length -eq 0 -and -not $AllowEmpty) { throw 'Expected table collection is empty.' }
    foreach ($TableName in $Values) {
        if ([string]::IsNullOrWhiteSpace($TableName) -or $TableName -notmatch '^[a-z][a-z0-9_]*$') {
            throw 'Expected table collection contains an invalid table name.'
        }
    }
    return [pscustomobject]@{ Values = $Values; Count = $Values.Length }
}

function Get-Phase8PsqlFailureCategory {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$DiagnosticText,
        [int]$ExitCode,
        [bool]$PassMarkerFound
    )

    if ($ExitCode -eq 0 -and $PassMarkerFound) { return 'PASS' }
    if ($DiagnosticText -match '(?i)password authentication failed|authentication failed|no password supplied|\bSCRAM\b|pg_hba\.conf') {
        return 'POSTGRES_AUTHENTICATION'
    }
    if ($DiagnosticText -match '(?i)could not translate host name|name or service not known|unknown host|connection refused|ECONNREFUSED|timeout expired|timed out|could not connect to server|SSL error|certificate verification failed|connection reset|ECONNRESET|server closed the connection unexpectedly') {
        return 'POSTGRES_CONNECTIVITY'
    }
    if ($DiagnosticText -match '(?i)\bERROR\b|SQLSTATE|permission denied|FAIL-CLOSED|canceling statement due to statement timeout') {
        return 'SQL_EXECUTION'
    }
    if ($ExitCode -ne 0) { return 'PSQL_EXIT_FAILURE_UNCLASSIFIED' }
    if (-not $PassMarkerFound) { return 'READ_ONLY_PASS_MARKER_MISSING' }
    return 'PSQL_RESULT_UNCLASSIFIED'
}

function Get-Phase8CliFailureCategory {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$DiagnosticText,
        [int]$ExitCode,
        [switch]$InvocationFailed
    )

    if ($InvocationFailed -or $DiagnosticText -match '(?i)CreateProcess|failed to start process|could not start|failed to initialize|unable to load executable|executable.*not found|access is denied') {
        return 'CLI_INITIALIZATION'
    }
    if ($ExitCode -eq 0) { return 'CLI_SUCCESS' }
    if ($DiagnosticText -match '(?i)AccessTokenRequiredError|access token not provided|authentication required|failed to authenticate|\bunauthorized\b|invalid.*token') {
        return 'CONNECTION_OR_AUTHENTICATION'
    }
    if ($DiagnosticText -match '(?i)connection refused|connection reset|could not connect|failed to connect|timed out|timeout expired|DNS|resolve host|network is unreachable|no such host|dial tcp|TLS handshake') {
        return 'CONNECTION_OR_AUTHENTICATION'
    }
    if ($DiagnosticText -match '(?i)already applied|already exists in migration history|migration history conflict|version conflict|remote migration.*(missing|diverg)|local migration.*(missing|diverg)|duplicate migration|migration.*history.*conflict') {
        return 'MIGRATION_HISTORY_CONFLICT'
    }
    if ($DiagnosticText -match '(?i)\bSQLSTATE\b|\bERROR:\s|migration.*(failed|error)|\bpostgres\b.*(error|failed)|failed to execute.*migration') {
        return 'MIGRATION_SQL_EXECUTION'
    }
    return 'UNKNOWN_FAILURE'
}
