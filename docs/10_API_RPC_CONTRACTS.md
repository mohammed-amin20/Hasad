# HASAD V2 — API and RPC Contracts
**Status: DRAFT**

For every server transaction, specify:
- Name/version, auth and active tenant derivation, role decision, input/output JSON schema.
- Validation and domain error names; atomic writes; idempotency and collision semantics.
- Explicit allowed table grants, RPC execution grants, search_path and SECURITY mode.
- Expected offline queue behavior and retry semantics.
- SQL integration tests proving no direct write bypass, tenant isolation, concurrency and journal balancing.

**Rule:** do not infer that a function is deployed from the presence of a migration file.

## Owner-approved DEV application exception (2026-10-30)

For this private DEV training application, the owner approved Flutter's existing
authenticated direct Data API integration with the exposed `hasad` schema for
company-scoped data operations. Preserve that integration; do not migrate these
flows back to `whoami`/`products_list` or require `hasad_api` for the DEV client.
This exception does not grant direct client writes to authoritative stock rows.
Inventory balance changes remain server-transaction-only. The broader V2 API
contract and security PoC remain pending; no remote movement-posting deployment
is authorized by this local implementation decision.

## Unit D inventory posting contract (O12 approved 2026-10-30; candidate only)

`hasad.post_stock_receipt(movement_id, company_id, warehouse_id, product_id,
qty, unit_cost)`, `hasad.post_stock_issue(movement_id, company_id, warehouse_id,
product_id, qty)`, and `hasad.post_stock_transfer(out_movement_id,
in_movement_id, company_id, source_warehouse_id, destination_warehouse_id,
product_id, qty)` are the review-only candidate signatures. The authenticated
actor is taken from the verified PostgREST JWT claims; each call checks active
company membership and `inventory.post` (company owner, deny override, explicit
allow, then role grant). Idempotency IDs are stable across retries; same ID and
same payload returns the committed movement(s), while changed payload is
rejected. A transaction-scoped per-product lock and row locks serialize balance
and sequence updates. An issue/transfer that exceeds source on-hand is rejected.

O12 selects a separate moving weighted average per product and warehouse.
Receipt cost must be explicit. Quantities and costs accept at most four decimal
places (`numeric(19,4)`); excess precision is rejected. Weighted averages use
four decimal HALF_UP rounding, and movement values use two decimal HALF_UP
rounding. An empty warehouse starts at the explicit receipt cost; a transfer
into an empty destination starts at the source average. Posting updates levels,
appends movement rows, and records `stock.posted` audit data in one transaction.
Authenticated clients receive no direct stock-level or movement-posting table
writes. The candidate has not been installed on hosted DEV; the current DEV
executor's catalog privileges, function ownership compatibility, RLS policies,
and PostgREST schema exposure remain unverified. No deployment is authorized.

## Permission catalogue decision relevant to product reads

**APPROVED (D-030, catalogue code only):** `products.read` is an explicit,
read-only permission code in module `products`. No role mapping or user override
is approved or added automatically. The original 37 permission codes retain
their meanings; the deployed DEV catalogue remains 37 until the candidate
changes are separately approved and deployed, after which the proposed total
would be 38.

The review-only candidate proposes `hasad_api.products_list()` as a consumer of
`products.read`; that RPC, its grants and security design are **not approved or
deployed by D-030**. This API document remains DRAFT until the complete contract,
real-JWT/PostgREST behavior and deployment receive separate review/approval.
