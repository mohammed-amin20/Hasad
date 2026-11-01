# LOCAL DISPOSABLE POC - NOT FOR DEPLOYMENT
param(
  [string]$DbName = "hasad_v2_rpc_poc_$(Get-Date -Format 'yyyyMMddHHmmss')",
  [string]$SuperUser = $env:PGUSER,
  [string]$Host = "localhost",
  [int]$Port = 5432
)
if (-not $SuperUser) { $SuperUser = "postgres" }
$ErrorActionPreference = "Stop"
Write-Host "Creating DB $DbName"
createdb -h $Host -p $Port -U $SuperUser $DbName 2>&1 | Out-Null
$env:PGPASSWORD = $env:PGPASSWORD
$files = @(
  "supabase/migrations/20261026000000_v2_foundation_schemas.sql",
  "supabase/migrations/20261026000100_v2_identity_tenancy_foundation.sql",
  "supabase/migrations/20261026000200_v2_permissions_foundation.sql",
  "supabase/migrations/20261026000210_v2_permission_catalogue_seed.sql"
)
foreach ($f in $files) {
  Write-Host "Applying $f"
  psql -h $Host -p $Port -U $SuperUser -d $DbName -v ON_ERROR_STOP=1 -f $f | Out-Null
}
Write-Host "Applying candidate SQL"
psql -h $Host -p $Port -U $SuperUser -d $DbName -v ON_ERROR_STOP=1 -f "security/candidates/20261030000100_v2_candidate_hasad_api_company_product_read.sql" | Out-Null
Write-Host "Running tests"
psql -h $Host -p $Port -U $SuperUser -d $DbName -v ON_ERROR_STOP=1 -f "security/poc/test_rpc_poc.sql" | Tee-Object -FilePath "local_audit/RPC_POC_$(Get-Date -Format 'yyyyMMddHHmmss').log"
Write-Host "Done"
