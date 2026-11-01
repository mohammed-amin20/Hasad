-- Local-only S3 concurrency step 2 of 3.
-- Runs while session A holds the invoice row lock. PostgreSQL must cancel this
-- second call with 57014 (statement_timeout); the runner treats that exit as
-- the expected result and verifies it before allowing the retry step.
\set VERBOSITY verbose
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002"}', true);
SET LOCAL statement_timeout = '900ms';
SELECT hasad.post_sales_invoice(
  '20000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000018',
  '51000000-0000-0000-0000-000000000018');
