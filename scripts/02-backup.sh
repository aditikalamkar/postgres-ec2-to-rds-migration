#!/usr/bin/env bash
# Custom-format dump from the container, with a checksum.
# Usage: CONTAINER=pg DB_NAME=shop DB_USER=postgres OUT_DIR=./backups ./02-backup.sh
set -euo pipefail
: "${CONTAINER:?}" "${DB_NAME:?}" "${DB_USER:?}"
OUT_DIR="${OUT_DIR:-./backups}"
mkdir -p "$OUT_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FILE="$OUT_DIR/${DB_NAME}_${STAMP}.dump"

docker exec -i "$CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc --no-owner --no-privileges > "$FILE"

# A dump that pg_restore can't list is not a backup.
docker exec -i "$CONTAINER" pg_restore --list < "$FILE" > /dev/null

sha256sum "$FILE" | tee "$FILE.sha256"
ls -lh "$FILE"
echo "Backup OK: $FILE"
