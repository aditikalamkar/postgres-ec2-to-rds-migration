#!/usr/bin/env bash
# Restore a dump into RDS. Run from a host inside the VPC (e.g. the app EC2 instance).
# The password comes from PGPASSWORD or ~/.pgpass, never from this file.
# Usage: RDS_HOST=<endpoint> DB_NAME=shop RDS_ADMIN=dbadmin APP_USER=shop_app DUMP=./backups/x.dump ./03-restore-to-rds.sh
set -euo pipefail
: "${RDS_HOST:?}" "${DB_NAME:?}" "${RDS_ADMIN:?}" "${APP_USER:?}" "${DUMP:?}"
JOBS="${JOBS:-4}"
export PGSSLMODE=require

sha256sum -c "$DUMP.sha256"

pg_restore -h "$RDS_HOST" -U "$RDS_ADMIN" -d "$DB_NAME" \
  --no-owner --no-privileges --jobs="$JOBS" --exit-on-error "$DUMP"

psql -h "$RDS_HOST" -U "$RDS_ADMIN" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
GRANT USAGE ON SCHEMA public TO ${APP_USER};
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ${APP_USER};
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO ${APP_USER};
ANALYZE;
SQL
echo "Restore finished. Now run 04-verify.sh"
