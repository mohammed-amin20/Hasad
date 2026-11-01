$files = Get-ChildItem 'supabase/migrations' | Sort-Object Name
foreach ($f in $files) {
  Write-Output "== $($f.Name)"
  $content = Get-Content $f.FullName
  foreach ($l in $content) {
    if ($l -match '^\s*CREATE TABLE') {
      Write-Output $l.Trim()
    }
  }
}
