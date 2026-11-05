-- Sequences owned by a table column whose next value would collide with existing rows.
-- Report only:   psql ... -v dry_run=1 -f fix_sequences.sql   (prints "BEHIND ..." lines)
-- Report + fix:  psql ... -f fix_sequences.sql
\if :{?dry_run}
\else
  \set dry_run 0
\endif

CREATE OR REPLACE FUNCTION pg_temp.col_max(s text, t text, c text) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  EXECUTE format('SELECT coalesce(max(%I), 0) FROM %I.%I', c, s, t) INTO n;
  RETURN n;
END $$;

CREATE TEMP TABLE seq_check AS
SELECT n.nspname AS sch, s.relname AS seq,
       ps.last_value AS last_val,
       pg_temp.col_max(n.nspname, t.relname, a.attname) AS max_id
FROM pg_class s
JOIN pg_namespace n ON n.oid = s.relnamespace
JOIN pg_sequences ps ON ps.schemaname = n.nspname AND ps.sequencename = s.relname
JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
JOIN pg_class t ON t.oid = d.refobjid
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
WHERE s.relkind = 'S';

-- last_value is NULL for a sequence never used; treat that as 0.
SELECT 'BEHIND ' || sch || '.' || seq || ' last=' || coalesce(last_val, 0) || ' max=' || max_id
FROM seq_check WHERE coalesce(last_val, 0) < max_id;

\if :dry_run
\else
SELECT format('SELECT setval(%L, %s)', sch || '.' || seq, max_id)
FROM seq_check WHERE coalesce(last_val, 0) < max_id \gexec
\endif
