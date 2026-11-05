-- Exact row count for every user table, one "schema.table|count" per line.
-- Uses count(*) on purpose: pg_stat estimates are not good enough for sign-off.
CREATE OR REPLACE FUNCTION pg_temp.exact_count(s text, t text) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM %I.%I', s, t) INTO n;
  RETURN n;
END $$;

SELECT table_schema || '.' || table_name || '|' || pg_temp.exact_count(table_schema, table_name)
FROM information_schema.tables
WHERE table_type = 'BASE TABLE'
  AND table_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY 1;
