CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_ok boolean,p_label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAIL: %',p_label; END IF; END $$;

-- First candidate execution was expected to fail on the deliberate type conflict.
SELECT pg_temp.assert_true((SELECT count(*)=0 FROM hasad.fiscal_years WHERE company_id='91000000-0000-0000-0000-000000000001'),'conflicting type rolls back fiscal-year insert');
SELECT pg_temp.assert_true((SELECT count(*)=1 FROM hasad.document_types WHERE company_id='91000000-0000-0000-0000-000000000001' AND code='SI' AND name_ar='اسم متعارض'),'candidate does not overwrite conflicting type');
DELETE FROM hasad.document_types WHERE id='92000000-0000-0000-0000-000000000001';
