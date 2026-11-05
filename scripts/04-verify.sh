#!/usr/bin/env bash
# Compare exact row counts and Flyway history between source container and RDS,
# and check that no sequence is behind its table's data.
# Usage: CONTAINER=pg DB_NAME=shop DB_USER=postgres RDS_HOST=<endpoint> RDS_ADMIN=dbadmin ./04-verify.sh
set -euo pipefail
: "${CONTAINER:?}" "${DB_NAME:?}" "${DB_USER:?}" "${RDS_HOST:?}" "${RDS_ADMIN:?}"
export PGSSLMODE=require
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"

docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -At < "$DIR/sql/row_counts.sql" | sort > "$TMP/src.txt"
psql -h "$RDS_HOST" -U "$RDS_ADMIN" -d "$DB_NAME" -At < "$DIR/sql/row_counts.sql" | sort > "$TMP/rds.txt"

FLY="SELECT installed_rank||'|'||version||'|'||checksum FROM flyway_schema_history ORDER BY installed_rank;"
docker exec -i "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -At -c "$FLY" > "$TMP/src_fly.txt"
psql -h "$RDS_HOST" -U "$RDS_ADMIN" -d "$DB_NAME" -At -c "$FLY" > "$TMP/rds_fly.txt"

fail=0
if diff -u "$TMP/src.txt" "$TMP/rds.txt"; then echo "Row counts: MATCH ($(wc -l < "$TMP/src.txt") tables)"; else echo "Row counts: MISMATCH"; fail=1; fi
if diff -u "$TMP/src_fly.txt" "$TMP/rds_fly.txt"; then echo "Flyway history: MATCH"; else echo "Flyway history: MISMATCH"; fail=1; fi

behind="$(psql -h "$RDS_HOST" -U "$RDS_ADMIN" -d "$DB_NAME" -At -q -v dry_run=1 -f "$DIR/sql/fix_sequences.sql" | grep -c BEHIND || true)"
if [ "$behind" -eq 0 ]; then echo "Sequences: OK"; else echo "Sequences: $behind behind (run sql/fix_sequences.sql)"; fail=1; fi

rm -rf "$TMP"
exit "$fail"
