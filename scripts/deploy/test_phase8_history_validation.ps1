[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'phase8_history_validation.ps1')

$Prior = @('20261026000000','20261026000100','20261026000200','20261026000210',
    '20261027000300','20261027000400','20261028000500','20261028000600','20261028000700')
$V008 = '20261029000800'
$V009 = '20261029000900'
$Allowed = @($Prior + $V008 + $V009)

function New-HistoryFixture([string[]]$Applied, [string[]]$Pending, [string[]]$RemoteOnly = @(), [string[]]$Extra = @()) {
    $Rows = @('LOCAL      | REMOTE     | TIME (UTC)', '-----------|------------|----------')
    foreach ($Version in $Applied) { $Rows += "$Version | $Version | 2026-10-29 00:00:00" }
    foreach ($Version in $Pending) { $Rows += "$Version | - | " }
    foreach ($Version in $RemoteOnly) { $Rows += "- | $Version | 2026-10-29 00:00:00" }
    foreach ($Version in $Extra) { $Rows += "$Version | $Version | 2026-10-29 00:00:00" }
    return $Rows -join "`n"
}

function New-WhitespaceHistoryFixture([string[]]$Applied, [string[]]$Pending) {
    # Regression format: whitespace-aligned LOCAL / REMOTE columns, matching
    # the header branch implicated by the live line-45 failure.
    $Rows = @('{0,-16}{1,-18}{2}' -f 'LOCAL','REMOTE','TIME (UTC)')
    foreach ($Version in $Applied) { $Rows += ('{0,-16}{1,-18}{2}' -f $Version,$Version,'2026-10-29 00:00:00') }
    foreach ($Version in $Pending) { $Rows += ('{0,-16}{1,-18}{2}' -f $Version,'','2026-10-29 00:00:00') }
    return $Rows -join "`n"
}

function Assert-Throws([scriptblock]$Action, [string]$Name) {
    try { & $Action; throw "TEST FAILED: $Name should have failed." }
    catch { if ($_.Exception.Message -like "TEST FAILED: $Name*") { throw }; Write-Output "PASS: $Name rejected" }
}

$EmptySelection = ConvertTo-Phase8TableSelection -Value $null -AllowEmpty
if ($EmptySelection.Values -isnot [string[]] -or $EmptySelection.Count -ne 0 -or $EmptySelection.Values.Length -ne 0) {
    throw 'TEST FAILED: null baseline selection was not normalized to an empty string array.'
}
Write-Output 'PASS: null baseline table selection normalizes to typed empty collection'

$ScalarSelection = ConvertTo-Phase8TableSelection -Value 'cashboxes'
if ($ScalarSelection.Values -isnot [string[]] -or $ScalarSelection.Count -ne 1 -or $ScalarSelection.Values[0] -cne 'cashboxes') {
    throw 'TEST FAILED: scalar table selection was not normalized to a one-item string array.'
}
Write-Output 'PASS: scalar table selection normalizes before counting'

$ArraySelection = ConvertTo-Phase8TableSelection -Value ([object[]]@('cashboxes','bank_accounts'))
if ($ArraySelection.Values -isnot [string[]] -or $ArraySelection.Count -ne 2) {
    throw 'TEST FAILED: object-array table selection was not validated and normalized.'
}
Write-Output 'PASS: object-array table selection validates element types before counting'
Assert-Throws { ConvertTo-Phase8TableSelection -Value @{ cashboxes = $true } } 'hashtable rejected as table selection'
Assert-Throws { ConvertTo-Phase8TableSelection -Value $null } 'unexpected null table selection rejected'

if ((Get-Phase8PsqlFailureCategory -DiagnosticText 'FATAL: password authentication failed for user [redacted]' -ExitCode 2 -PassMarkerFound $false) -cne 'POSTGRES_AUTHENTICATION') { throw 'TEST FAILED: PSQL auth diagnostic classification.' }
if ((Get-Phase8PsqlFailureCategory -DiagnosticText 'psql: could not connect to server: Connection timed out' -ExitCode 2 -PassMarkerFound $false) -cne 'POSTGRES_CONNECTIVITY') { throw 'TEST FAILED: PSQL connectivity diagnostic classification.' }
if ((Get-Phase8PsqlFailureCategory -DiagnosticText 'ERROR: relation hasad.expected_table does not exist' -ExitCode 3 -PassMarkerFound $false) -cne 'SQL_EXECUTION') { throw 'TEST FAILED: PSQL SQL diagnostic classification.' }
if ((Get-Phase8PsqlFailureCategory -DiagnosticText '' -ExitCode 0 -PassMarkerFound $true) -cne 'PASS') { throw 'TEST FAILED: PSQL verification marker classification.' }
Write-Output 'PASS: PSQL preflight diagnostics classify auth, connectivity, SQL and pass outcomes without echoing raw diagnostics'
if ((Get-Phase8CliFailureCategory -DiagnosticText 'CreateProcessWithLogonW failed' -ExitCode -1 -InvocationFailed) -cne 'CLI_INITIALIZATION') { throw 'TEST FAILED: CLI initialization classification.' }
if ((Get-Phase8CliFailureCategory -DiagnosticText 'AccessTokenRequiredError: access token not provided' -ExitCode 1) -cne 'CONNECTION_OR_AUTHENTICATION') { throw 'TEST FAILED: CLI authentication classification.' }
if ((Get-Phase8CliFailureCategory -DiagnosticText 'failed to connect: connection refused' -ExitCode 1) -cne 'CONNECTION_OR_AUTHENTICATION') { throw 'TEST FAILED: CLI connectivity classification.' }
if ((Get-Phase8CliFailureCategory -DiagnosticText 'remote migration history conflict: version already applied' -ExitCode 1) -cne 'MIGRATION_HISTORY_CONFLICT') { throw 'TEST FAILED: CLI migration history conflict classification.' }
if ((Get-Phase8CliFailureCategory -DiagnosticText 'ERROR: migration failed SQLSTATE 23503' -ExitCode 1) -cne 'MIGRATION_SQL_EXECUTION') { throw 'TEST FAILED: CLI migration SQL classification.' }
if ((Get-Phase8CliFailureCategory -DiagnosticText 'opaque failure detail' -ExitCode 1) -cne 'UNKNOWN_FAILURE') { throw 'TEST FAILED: CLI fallback classification.' }
Write-Output 'PASS: CLI failure categorization emits only safe categories'

$Initial = New-HistoryFixture -Applied $Prior -Pending @($V008,$V009)
$InitialRows = Assert-SupabaseMigrationState -Text $Initial -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed
if ($InitialRows.Count -ne 11) { throw "TEST FAILED: initial two-pending row count was $($InitialRows.Count)." }
Write-Output 'PASS: two expected pending migrations accepted'
$RealSamplePath = Join-Path $PSScriptRoot '..\..\phase8_cli_history_sample.txt'
if (-not (Test-Path -LiteralPath $RealSamplePath -PathType Leaf)) { throw 'Captured CLI history regression fixture is missing.' }
$RealSample = Get-Content -LiteralPath $RealSamplePath -Raw -Encoding UTF8
$RealRows = Assert-SupabaseMigrationState -Text $RealSample -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed
if ($RealRows.Count -ne 11) { throw 'Captured CLI history fixture did not produce eleven exact migration rows.' }
Write-Output 'PASS: captured Supabase CLI history sample accepted'
$WhitespaceInitial = New-WhitespaceHistoryFixture -Applied $Prior -Pending @($V008,$V009)
$null = Assert-SupabaseMigrationState -Text $WhitespaceInitial -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed
Write-Output 'PASS: whitespace-header regression fixture accepted'
$UnicodeSeparator = [string][char]0x2502
$UnicodeHistory = $Initial.Replace('|', $UnicodeSeparator)
$null = Assert-SupabaseMigrationState -Text $UnicodeHistory -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed
Write-Output 'PASS: Unicode table separators and whitespace accepted'

$OnePending = New-HistoryFixture -Applied $Prior -Pending @($V008)
$null = Assert-SupabaseMigrationState -Text $OnePending -ExpectedApplied $Prior -ExpectedPending @($V008) -AllowedVersions $Allowed
Write-Output 'PASS: one expected pending migration accepted'

$IsolatedAfter008 = New-HistoryFixture -Applied @($Prior + $V008) -Pending @()
$null = Assert-SupabaseMigrationState -Text $IsolatedAfter008 -ExpectedApplied @($Prior + $V008) -ExpectedPending @() -AllowedVersions $Allowed
Write-Output 'PASS: no pending migrations while 00900 is isolated after 00800'

$Unexpected = New-HistoryFixture -Applied $Prior -Pending @($V008,$V009) -Extra @('20261029001000')
Assert-Throws { Assert-SupabaseMigrationState -Text $Unexpected -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'unexpected extra migration'

$UnexpectedPending = New-HistoryFixture -Applied $Prior -Pending @($V008,$V009,'20261030000000')
Assert-Throws { Assert-SupabaseMigrationState -Text $UnexpectedPending -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'unexpected pending migration'

$Quote = [string][char]0x60
$MalformedQuote = $Initial.Replace("$($Prior[0]) | $($Prior[0])", "$Quote$($Prior[0]) | $($Prior[0])")
Assert-Throws { Assert-SupabaseMigrationState -Text $MalformedQuote -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'malformed cell quoting'

$RemoteOnly = New-HistoryFixture -Applied $Prior -Pending @($V008) -RemoteOnly @($V009)
Assert-Throws { Assert-SupabaseMigrationState -Text $RemoteOnly -ExpectedApplied $Prior -ExpectedPending @($V008) -AllowedVersions $Allowed } 'remote-only migration'

Assert-Throws { Assert-SupabaseMigrationState -Text 'no migration table was returned' -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'malformed CLI output'
Assert-Throws { Assert-SupabaseMigrationState -Text '{"_tag":"Error","error":{"code":"AccessTokenRequiredError"}}' -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'authentication failure output'
Assert-Throws { Assert-SupabaseMigrationState -Text 'ERROR: failed to connect: connection refused' -ExpectedApplied $Prior -ExpectedPending @($V008,$V009) -AllowedVersions $Allowed } 'connection failure output'

$StageAComplete = New-HistoryFixture -Applied @($Prior + $V008) -Pending @($V009)
$StageACompleteRows = Assert-SupabaseMigrationState -Text $StageAComplete -ExpectedApplied @($Prior + $V008) -ExpectedPending @($V009) -AllowedVersions $Allowed
if ($StageACompleteRows.Count -ne 11) { throw 'TEST FAILED: Stage B start state did not contain ten applied rows and one pending row.' }
Write-Output 'PASS: only 00900 pending after restoration'

$Final = New-HistoryFixture -Applied @($Prior + $V008 + $V009) -Pending @()
$FinalRows = Assert-SupabaseMigrationState -Text $Final -ExpectedApplied @($Prior + $V008 + $V009) -ExpectedPending @() -AllowedVersions $Allowed
if ($FinalRows.Count -ne 11) { throw "TEST FAILED: final row count was $($FinalRows.Count)." }
Write-Output 'PASS: final eleven applied and zero pending accepted'

Assert-Throws { Assert-Phase8DryRun -Text 'Would push: 20261029000800_wrong_name.sql' -ExpectedFilename '20261029000800_v2_cash_banking_payments_recon_structure.sql' } 'wrong dry-run filename'
Assert-Throws { Assert-Phase8DryRun -Text "Would push: 20261029000800_v2_cash_banking_payments_recon_structure.sql`n20261029000900_v2_expenses_structure.sql" -ExpectedFilename '20261029000800_v2_cash_banking_payments_recon_structure.sql' } 'multiple dry-run filenames'
Assert-Phase8DryRun -Text 'Would push: 20261029000800_v2_cash_banking_payments_recon_structure.sql' -ExpectedFilename '20261029000800_v2_cash_banking_payments_recon_structure.sql'
Write-Output 'PASS: exact dry-run filename accepted'

$DeploymentScript = Join-Path $PSScriptRoot 'deploy_phase8_dev_fixed.ps1'
$Tokens = $null; $ParseErrors = $null
$DeploymentAst = [System.Management.Automation.Language.Parser]::ParseFile($DeploymentScript, [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count -gt 0) { throw 'Deployment script AST contains parse errors.' }
$RestorationTry = @($DeploymentAst.FindAll({
    param($Node)
    $Node -is [System.Management.Automation.Language.TryStatementAst] -and
        $null -ne $Node.Finally -and
        $Node.Finally.Extent.Text -match 'Restore-009Migration' -and
        $Node.Body.Extent.Text -match '00800 deployment' -and
        $Node.Body.Extent.Text -match '00900 deployment'
}, $true))
if ($RestorationTry.Count -eq 0) { throw 'Deployment script lacks an outer finally restoration path covering failures in either stage.' }
Write-Output 'PASS: AST confirms finally restoration covers failures in either stage'

$DeploymentText = Get-Content -LiteralPath $DeploymentScript -Raw
$HistoryGate = $DeploymentText.IndexOf('if ($HistoryOnly)')
$PsqlSetup = $DeploymentText.IndexOf('$PsqlCandidates =')
$Isolation = $DeploymentText.IndexOf('Move-Item -LiteralPath $Original009')
$DryRun = $DeploymentText.IndexOf("'00800 dry-run'")
if ($HistoryGate -lt 0 -or $PsqlSetup -lt 0 -or $HistoryGate -gt $PsqlSetup -or
    $HistoryGate -gt $Isolation -or $HistoryGate -gt $DryRun) {
    throw 'HistoryOnly must return before psql setup, migration isolation, dry-run, or push.'
}
$HistoryBranchEnd = $DeploymentText.IndexOf('    }', $HistoryGate)
if ($DeploymentText.Substring($HistoryGate, $HistoryBranchEnd - $HistoryGate) -notmatch '\breturn\b') {
    throw 'HistoryOnly branch must exit immediately after history validation.'
}
Write-Output 'PASS: AST/source guard confirms HistoryOnly exits before database and migration operations'

$StageBClause = @($DeploymentAst.FindAll({
    param($Node)
    $Node -is [System.Management.Automation.Language.IfStatementAst] -and
        $Node.Clauses.Count -gt 0 -and
        $Node.Clauses[0].Item1.Extent.Text -match '\$StageBOnly'
}, $true) | Select-Object -First 1)
if ($StageBClause.Count -ne 1) { throw 'Dedicated StageBOnly branch is missing.' }
$StageBBody = $StageBClause[0].Clauses[0].Item2.Extent.Text
foreach ($RequiredStageBCheck in @("New-CatalogSql '008'", "-ExpectedApplied @(`$PriorVersions + `$V008) -ExpectedPending @(`$V009)",
    "-ExpectedFilename `$File009", "'00900 deployment'", "New-CatalogSql 'all'", "`$V008 + `$V009")) {
    if ($StageBBody -notlike "*$RequiredStageBCheck*") { throw "StageBOnly is missing required gate: $RequiredStageBCheck" }
}
if ($StageBBody -match '00800 deployment|00800 dry-run|Move-Item') { throw 'StageBOnly contains a Stage A push, dry-run, or migration isolation.' }
$StageBIndex = $DeploymentText.IndexOf('    if ($StageBOnly) {')
$StageAIsolationIndex = $DeploymentText.IndexOf('Move-Item -LiteralPath $Original009')
if ($StageBIndex -lt 0 -or $StageAIsolationIndex -lt 0 -or $StageBIndex -gt $StageAIsolationIndex) {
    throw 'StageBOnly branch must return before the Stage A isolation path.'
}
Write-Output 'PASS: AST/source guard confirms StageBOnly validates Stage A, selects only 00900, and cannot enter Stage A'
