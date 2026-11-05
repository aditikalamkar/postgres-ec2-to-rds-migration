#!/usr/bin/env bash
# Read-only checks against the source database inside the Docker container.
# Usage: CONTAINER=pg DB_NAME=shop DB_USER=postgres ./01-preflight.sh
set -euo pipefail
: "${CONTAINER:?set CONTAINER}" "${DB_NAME:?set DB_NAME}" "${DB_USER:?set DB_USER}"

q() { docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -At -c "$1"; }

echo "== Version";      q "SELECT version();"
echo "== Size";         q "SELECT pg_size_pretty(pg_database_size(current_database()));"
echo "== Extensions";   q "SELECT extname || ' ' || extversion FROM pg_extension ORDER BY 1;"
echo "== Roles";        q "SELECT rolname FROM pg_roles WHERE rolname !~ '^pg_' ORDER BY 1;"
echo "== Largest tables"
q "SELECT relname || '  ' || pg_size_pretty(pg_total_relation_size(relid))
   FROM pg_catalog.pg_statio_user_tables ORDER BY pg_total_relation_size(relid) DESC LIMIT 10;"
echo "== Flyway (last 5)"
q "SELECT version || '  ' || description || '  success=' || success
   FROM flyway_schema_history ORDER BY installed_rank DESC LIMIT 5;" || echo "no flyway_schema_history table"
echo "== Active connections"
q "SELECT usename || '  ' || count(*) FROM pg_stat_activity WHERE datname = current_database() GROUP BY usename;"
