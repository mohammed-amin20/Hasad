# Hasad ERP V2 — Documentation Index

This directory is the **single source of truth** for Hasad ERP V2 design and planning. 
See `../AGENTS.md` for OpenCode working rules.

## Status flow
`DRAFT` → `APPROVED` → `IMPLEMENTED` → `VERIFIED`

## Evidence labels (for every claim)
`OBSERVED` / `PROPOSED` / `APPROVED` / `VERIFIED`

## Naming convention
- Core specs: `NN_TOPIC_NAME.md` (two digits, uppercase/underscore).
- Feature specs: `features/NN_snake_case.md` (numbered 01–14). Follow `FEATURE_SPEC_TEMPLATE.md`.
- ADRs: `adrs/ADR-NNN_title.md` (numbered).
- Legacy audit: `legacy_audit/*` — **REFERENCE ONLY — NOT V2 DESIGN**.

## Numbering notes
- `01_CURRENT_STATE_INVENTORY.md` is **retired from docs/ root** and preserved in `legacy_audit/` (legacy DEV evidence).
- Duplicate numbering (`11_*`) was resolved by moving the legacy reset-safety gate to `legacy_audit/`.

## Documentation tree (current)
```text
docs/
├── README.md                        # This index
├── 00_MASTER_PLAN.md
├── 02_REQUIREMENTS_AND_SCOPE.md
├── 03_DOMAIN_GLOSSARY.md
├── 04_ARCHITECTURE.md
├── 05_DATABASE_SCHEMA.md
├── 06_ENTITY_RELATIONSHIPS.md
├── 07_SECURITY_TENANCY_RLS.md
├── 08_OFFLINE_SYNC.md
├── 09_ACCOUNTING_INVARIANTS.md
├── 10_API_RPC_CONTRACTS.md
├── 11_MIGRATION_AND_RESET_PLAN.md
├── 12_BACKUP_AND_RECOVERY.md
├── 13_TEST_STRATEGY.md
├── 14_UI_ARABIC_RTL_STANDARDS.md
├── 15_DECISION_LOG.md
├── 16_DATABASE_DECISION_PACKAGE.md  # Consolidated remaining V2 DB decisions
├── 17_ERP_STRUCTURAL_READINESS_PACKAGE.md # ERP migration readiness / decision bundles
├── 18_COMPANY_SETUP_WIZARD_DESIGN.md # DRAFT future company onboarding design
├── FEATURE_SPEC_TEMPLATE.md
├── adrs/
├── features/
│   ├── 01_tenants_and_users.md
│   ├── 02_roles_and_permissions.md
│   ├── 03_chart_of_accounts.md
│   ├── 04_journals_and_fiscal_periods.md
│   ├── 05_customers_and_suppliers.md
│   ├── 06_sales_and_invoicing.md
│   ├── 07_purchases.md
│   ├── 08_inventory_and_warehouses.md
│   ├── 09_cash_and_bank.md
│   ├── 10_expenses.md
│   ├── 11_employees_and_payroll.md
│   ├── 12_reports.md
│   ├── 13_settings_and_sequences.md
│   └── 14_sync_and_conflicts.md
└── legacy_audit/
    ├── 01_CURRENT_STATE_INVENTORY.md        # REFERENCE ONLY — NOT V2 DESIGN
    ├── DEV_RESET_SAFETY_GATE.md             # REFERENCE ONLY — NOT V2 DESIGN
    ├── LEGACY_BACKUP_OBSERVATIONS.md        # REFERENCE ONLY — NOT V2 DESIGN
    └── README.md                           # Legacy audit guidance
```

## Single source of truth map
| Topic | Authoritative document |
|---|---|
| Master plan & working agreement | `00_MASTER_PLAN.md` |
| Requirements & scope | `02_REQUIREMENTS_AND_SCOPE.md` |
| Domain glossary | `03_DOMAIN_GLOSSARY.md` |
| Architecture | `04_ARCHITECTURE.md` (+ `adrs/`) |
| Schema / ERD | `05_DATABASE_SCHEMA.md`, `06_ENTITY_RELATIONSHIPS.md` |
| Security / tenancy / RLS | `07_SECURITY_TENANCY_RLS.md` |
| Offline sync / conflicts | `08_OFFLINE_SYNC.md` |
| Accounting invariants | `09_ACCOUNTING_INVARIANTS.md` |
| API / RPC contracts | `10_API_RPC_CONTRACTS.md` |
| Migration / reset plan | `11_MIGRATION_AND_RESET_PLAN.md` |
| Backup / recovery | `12_BACKUP_AND_RECOVERY.md` |
| Test strategy / gates | `13_TEST_STRATEGY.md` |
| UI / Arabic RTL | `14_UI_ARABIC_RTL_STANDARDS.md` |
| Decisions | `15_DECISION_LOG.md` |
| ERP structural readiness | `17_ERP_STRUCTURAL_READINESS_PACKAGE.md` |
| Future company setup wizard | `18_COMPANY_SETUP_WIZARD_DESIGN.md` |
| Feature specs | `FEATURE_SPEC_TEMPLATE.md` + `features/*` |
| Legacy DEV/V1 observations | `legacy_audit/*` (**REFERENCE ONLY — NOT V2 DESIGN**) |

## Approval workflow
1. Draft in relevant spec.
2. Resolve all `OPEN DECISION`s or move to `15_DECISION_LOG.md` with owner approval.
3. Mark document `APPROVED` only when owner accepts it.
4. Implementation only after `APPROVED`. Update to `IMPLEMENTED` → `VERIFIED`.
5. No DB changes without explicit separate authorization.
6. Future DEV reset requires separate explicit authorization per `11_MIGRATION_AND_RESET_PLAN.md`.
