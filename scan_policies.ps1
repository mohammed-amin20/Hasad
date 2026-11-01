$content = Get-Content "local_audit/DEV_INVENTORY_20261021_192155.txt" -Raw
$lines = $content -split "`r?`n"
$pol = @()
$inPol = $false
foreach ($l in $lines) {
    if ($l -match "policies" -and $l -match "53") { $inPol = $true; continue }
    if (-not $inPol) { continue }
    if ($l -match "^public\s*\|") {
        if ($l -match "trg_") { break }
        $parts = $l -split '\|'
        if ($parts.Count -ge 3) {
            $schema = $parts[0].Trim()
            $table = $parts[1].Trim()
            $polname = $parts[2].Trim()
            if ($schema -eq "public" -and $table -ne "" -and $polname -ne "" -and $polname -notmatch "^-" -and $polname -notmatch "schemaname|relname|tablename|policyname|cmd|permissive") {
                $pol += [PSCustomObject]@{Table=$table; Policy=$polname}
            }
        }
    } elseif ($l -match "trigger" -and $l -match "trg_") { break }
}
$seen = @{}
$unique = @()
foreach ($p in $pol) {
    $key = $p.Table + "|" + $p.Policy
    if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $unique += $p
    }
}
foreach ($u in $unique) {
    Write-Host "public|$($u.Table)|$($u.Policy)"
}
Write-Host "---TOTAL:$($unique.Count)---"
