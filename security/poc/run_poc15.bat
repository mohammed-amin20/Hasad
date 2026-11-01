@echo off
set PGPASSWORD=postgres
set PGUSER=postgres
createdb -U postgres hasad_v2_rpc_poc15_test 2>nul
psql -U postgres -d hasad_v2_rpc_poc15_test -c "CREATE SCHEMA IF NOT EXISTS auth; CREATE TABLE IF NOT EXISTS auth.users (id uuid PRIMARY KEY, email text);" >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261026000000_v2_foundation_schemas.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261026000100_v2_identity_tenancy_foundation.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261026000200_v2_permissions_foundation.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261026000210_v2_permission_catalogue_seed.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261027000400_v2_erp_core_master_fiscal_settings.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261028000500_v2_accounting_journals_structure.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f supabase/migrations/20261028000600_v2_inventory_structure.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f security/candidates/20261030000100_v2_candidate_hasad_api_company_product_read_v2.sql >nul
psql -U postgres -d hasad_v2_rpc_poc15_test -f security/poc/insert_and_test.sql
