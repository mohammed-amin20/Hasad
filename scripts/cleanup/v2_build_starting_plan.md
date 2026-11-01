# V2 Build Starting Plan (Separate from Cleanup)

**Status:** PLANNED (not authorized to create DB objects yet)  
**Rule:** Do not create V2 schema objects during cleanup. Begin only after verified cleanup and separate authorization.

## Phase V2-0: Preparation (Local)
- [ ] Verify cleanup complete per post-cleanup checklist
- [ ] Review approved specs: `docs/05_DATABASE_SCHEMA.md`, `docs/10_API_RPC_CONTRACTS.md`, `docs/07_SECURITY_TENANCY_RLS.md`
- [ ] Ensure specs are APPROVED before any SQL
- [ ] Review D-010 (hasad private / hasad_api exposed), D-012 (Supabase CLI, forward-only migrations)

## Phase V2-1: Schema Design (Requires Authorization)
- [ ] Create private schema `hasad` (separate authorization)
- [ ] Create exposed RPC schema `hasad_api` (separate authorization)
- [ ] Follow approved design only
- [ ] No reuse of V1 objects

## Phase V2-2: Migrations (Requires Authorization)
- [ ] Use Supabase CLI
- [ ] Forward-only, timestamped migration files in `supabase/migrations/`
- [ ] Record deployment per file
- [ ] Validate on disposable target if possible

## Phase V2-3: Security (Requires Validation)
- [ ] Implement RLS
- [ ] Least-privilege grants
- [ ] RPC security per R-02 (INVOLKER/DEFINER as approved)
- [ ] Plan isolated security PoC with real JWTs
- [ ] Cross-company negative tests

## Phase V2-4: Flutter (Local)
- [ ] Build against `hasad_api` via approved contracts
- [ ] Repository root layout maintained
- [ ] Follow domain rules (Arabic RTL default, accounting semantics unchanged)

## Phase V2-5: Verification
- [ ] Tests pass
- [ ] RLS/tenancy isolation verified
- [ ] Meet Definition of Done before considering complete
