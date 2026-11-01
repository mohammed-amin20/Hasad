# HASAD V2 — Domain Glossary
**Status: DRAFT**

| Term | Proposed meaning / open decision |
|---|---|
| Tenant / Company | Isolated business ownership boundary; confirm legal entity semantics. |
| Membership | User-role link scoped to tenant; never use a global role for tenant permissions. |
| Business document | Sale/purchase/payment/expense; immutable reference after posting subject to policy. |
| Journal entry | Balanced financial posting, grouped debit/credit lines. |
| Fiscal period | Date range where posting may be opened/locked/closed. |
| Idempotency key | Stable client request identifier for safe retries. |
| Sync outbox | SQLite log of pending local changes and dependencies. |
| Reversal | Auditable correcting entry, not deletion of posted history. |

Define every business word with one owner-approved meaning before build.
