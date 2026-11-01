# C1/C2 real-JWT security PoC — disposable target only

**Status: PREPARED — BLOCKED.** This matrix cannot run until an approved RPC
surface and its RLS policies exist. Do not run it on DEV
`sxasnunzspkuwbxiddqd` or on production. Do not create test users, companies,
or fixtures on DEV.

The executable default-deny baseline is
`scripts/security/poc_c1_c2_default_deny.sql`; this file adds the real-JWT
cross-tenant cases required by `docs/16_DATABASE_DECISION_PACKAGE.md` §10.2.

## Prerequisites

1. A disposable Supabase project with the two foundation migrations and the
   approved permissions migration applied.
2. Test identities created through the disposable project's Auth Admin API:
   owner/member A, member A2, member B, suspended A, revoked A.
3. One company per identity through the approved company-creation path, plus
   roles and overrides created through the approved RPCs.
4. Real access tokens for each identity (no hand-forged `sub` claims).
5. The exact RPC list approved by the owner. Do not substitute a generic
   table-read RPC.

## Required cases

| # | Case | Call | Expected |
|---|---|---|---|
| 1 | Anonymous denial | Each approved RPC with no `Authorization` header | Non-2xx; no rows returned or written |
| 2 | Direct table access | `GET /rest/v1/companies` and each V2 table | 404/denied; `hasad` is not exposed |
| 3 | Same-company access | Member A calls an approved A-company RPC | Success, only A data |
| 4 | Cross-company access | Member A calls the same RPC with B's company id or B entity id | Denied; no B data leaked |
| 5 | Suspended/revoked | Suspended A and revoked A call any approved RPC | Denied on the first call |
| 6 | Owner allow | Owner calls every sampled code | Allowed |
| 7 | Deny override | Member with role grant + deny override | Denied |
| 8 | Allow override | Member with no role grant + allow override | Allowed only for delegable codes |
| 9 | Owner override immunity | Owner with a deny override on any code | Still allowed |
| 10 | Sales cash guard | Sales member with an allow override attempt for `cash.post` | Override rejected or effective denial; never allowed |
| 11 | Fiscal close guard | Admin attempts to set an allow override for `fiscal.close` | Rejected; only the owner passes |
| 12 | Inventory adjust guard | Non-admin allow override for `inventory.adjust` | Rejected; only owner/admin hold it |
| 13 | Search path | Call each RPC with a hostile `search_path`/shadow object | No shadow object is used; pinned path holds |
| 14 | Public execute | Inspect `proacl` for every approved RPC | No `PUBLIC`/`anon` EXECUTE |

## Evidence to record

For each case: project ref (disposable), migration versions, UTC timestamp,
JWT subject/company (pseudonymous ids are enough), RPC name, HTTP status,
returned row count, and whether any write occurred. Store the output outside
DEV and never include raw tokens, emails, or secrets.

A single failed case blocks all application-facing policies, grants, and RPCs.
