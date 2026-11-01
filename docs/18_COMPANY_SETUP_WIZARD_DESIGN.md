# HASAD V2 — Company Setup Wizard Design

**Status: DRAFT** | **Evidence: PROPOSED** | **Owner approval: PENDING**

## Purpose and boundary

This is a future server-side onboarding design for a newly created company. It
does not alter the existing company-creation flow, create an RPC, grant access,
or authorize deployment. It is not a substitute for the reviewed Abo Amen
review-only candidates.

The wizard must complete a selected approved setup profile atomically, or leave
no setup rows behind. Flutter must submit one setup request and must never issue
direct writes to accounts, periods, document types, counters, tax rates, roles,
or permissions.

## Required approved setup-profile inputs

The server receives identifiers/values from an owner-approved profile, never
invented defaults:

1. Existing newly-created `company_id`; verified active company and authorized
   actor.
2. Company settings: legal/display names, ILS setting where applicable, and an
   explicit VAT state. VAT configuration must be explicit: `vat_enabled=false`
   creates no tax rate; `vat_enabled=true` requires separately approved tax
   codes, rates, effective dates, and mappings.
3. Fiscal year and a complete monthly period plan, including which period(s) are
   initially open.
4. Approved baseline chart of accounts and module-account role mappings.
5. Approved document types/prefixes/padding, including SI and JE. Counters are
   initialized lazily by the reviewed allocator only; the wizard does not issue
   an official number.
6. Approved default role/permission profile using the existing safe contracts;
   no role or permission meaning is inferred by the wizard.

## Proposed server transaction

1. Derive actor from trusted JWT; verify the actor is authorized to perform
   company onboarding and that the company is active.
2. Lock/configure the company setup state using one idempotency key and one
   setup-profile version.
3. Validate every profile input before writing: tenant scope, account role/type,
   fiscal date ranges, monthly periods, document type uniqueness and VAT inputs.
4. Insert-or-verify company settings, accounts, mappings, fiscal year/periods,
   document types and approved role/permission assignments. Exact existing rows
   are idempotent; a conflicting row aborts rather than being overwritten.
5. Write a bounded audit event for the setup profile/version and actor, subject
   to an approved audit contract.
6. Commit only if every stage succeeds. No invoice, stock movement, journal
   entry, financial balance, tax rate, or official number is created unless an
   explicitly approved profile requires an eligible non-financial seed.

## Tenant and security constraints

- Every inserted row carries the selected `company_id`; cross-company inputs
  fail before write.
- FORCE RLS remains enabled. The future transaction owner needs only reviewed,
  narrow grants and policies; it must not grant its privileged role to clients.
- Company setup is a controlled server operation, not a public Data API form.
- The operation must not use `service_role` from Flutter.

## Idempotency and recovery

- Setup input includes a durable UUID idempotency key and immutable profile
  version/hash.
- Same company/profile/key replay returns the established setup result without
  new rows.
- Same company with changed profile values returns a conflict for accountant or
  owner review; it never silently mutates a live chart, period, or document type.
- Partial failures roll back the entire transaction.

## Implementation roadmap

1. **Approval:** resolve O1, VAT D-023, default role/permission scope, first
   open-period policy, document-number formats, and setup-audit contract.
2. **Specification:** promote this document and dependent feature/API/security
   contracts to APPROVED with exact RPC signature and response/error contract.
3. **Security design:** review role ownership, RLS policies and grants with a
   real-JWT matrix; do not rely on Flutter checks.
4. **Implementation:** add one transaction-scoped server RPC and isolated
   disposable PostgreSQL tests.
5. **Verification:** test first run, replay, conflicting rerun, tax-off/on,
   tenant isolation, forced-RLS access, and rollback at every stage.
6. **Deployment:** request a separate, named DEV authorization only after the
   test evidence and reviewed migration/RPC hash are available.

## Open decisions

- Statutory/company chart template requirements (O1).
- VAT rate, exemptions, legal invoice form and reporting (D-023).
- Default roles/permission assignments and company-onboarding authority.
- Which initial fiscal period(s) may be open operationally.
- Setup-profile ownership, versioning and audit retention.
