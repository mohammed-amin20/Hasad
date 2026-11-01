-- Local-only S3 concurrency step 1 of 3.
-- Session A holds the invoice row lock for five seconds so the second session
-- is forced to wait. Disposable harness only.
BEGIN;
SELECT id
FROM hasad.sales_documents
WHERE id = '50000000-0000-0000-0000-000000000018'
FOR UPDATE;
SELECT pg_sleep(5);
COMMIT;
