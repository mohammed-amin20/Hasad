-- Hasad ERP V2 foundation: schema boundary only
-- Target: Supabase DEV sxasnunzspkuwbxiddqd
-- Source: D-010 (APPROVED schema-organization decision)
-- Scope: create the approved empty schemas only. This migration deliberately
-- contains no tables, RLS policies, grants, functions, triggers, seed data,
-- PostgREST exposure configuration, or changes to managed Supabase objects.
--
-- `hasad` is the private V2 data schema.
-- `hasad_api` is reserved for the future V2 RPC interface schema.
-- Deployment must be separately authorized and recorded with actual evidence.

BEGIN;

CREATE SCHEMA hasad;
CREATE SCHEMA hasad_api;

COMMIT;
