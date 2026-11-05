# Troubleshooting notes

Problems that come up when moving PostgreSQL from a Docker container on EC2 to Amazon RDS, and how to get past each one. Written as symptom → cause → fix, so it's quick to scan when something breaks at 1 a.m.

---

## Networking and access

### 1. Connection to RDS just hangs, then times out

**Symptom:** `psql` or the Spring Boot app waits ~30 seconds and fails with a timeout. No "password failed", no "refused", just silence.

**Cause:** a timeout almost always means packets never reached the database. Usually one of:
- the RDS security group doesn't allow 5432 from the app's security group
- the app instance and RDS are in different VPCs
- a network ACL on the private subnets blocks the traffic (or the return traffic on ephemeral ports)

**Fix:**
```bash
# from the EC2 host
nc -zv <RDS_ENDPOINT> 5432
pg_isready -h <RDS_ENDPOINT> -p 5432
```
Check the RDS security group inbound rule: **source must be the app security group ID**, not an IP. Confirm both resources show the same VPC ID.

> Rule of thumb: *timeout* = network, *refused* = nothing listening on that port, *auth failed* = you reached Postgres and it said no.

### 2. `no pg_hba.conf entry for host ... no encryption`

**Cause:** `rds.force_ssl = 1` is set (good), but the client is connecting without TLS.

**Fix:** add `sslmode=require` to the JDBC URL and set `PGSSLMODE=require` for `psql`, `pg_restore` and scripts.
```
jdbc:postgresql://<RDS_ENDPOINT>:5432/<DB_NAME>?sslmode=require
```

### 3. App still talks to the old database after the switch

**Symptom:** everything "works", but new orders are not showing up in RDS.

**Cause:** the JDBC URL baked into `application.yml` inside the image, or a leftover `.env` file, wins over the new environment variable. Or one of the services wasn't restarted.

**Fix:** check what each side actually sees.
```sql
-- on RDS: are the services connected here?
SELECT usename, application_name, client_addr, count(*)
FROM pg_stat_activity WHERE datname = current_database()
GROUP BY 1, 2, 3;
```
Keeping the old container **stopped** during cutover makes this obvious: a service still pointing at it fails loudly instead of silently writing to the wrong place.

---

## Dump and restore

### 4. Dump file is corrupt / `pg_restore: input file does not appear to be a valid archive`

**Cause:** the dump was taken with `docker exec -it`. The `-t` allocates a TTY, which rewrites line endings and breaks the binary custom-format file.

**Fix:** use `-i` only:
```bash
docker exec -i <CONTAINER> pg_dump -U <USER> -d <DB> -Fc > db.dump
docker exec -i <CONTAINER> pg_restore --list < db.dump > /dev/null   # sanity check
```

### 5. `pg_dump: error: aborting because of server version mismatch`

**Cause:** the `pg_dump` installed on the EC2 host is older than the PostgreSQL server in the container.

**Fix:** run `pg_dump` **inside the container** (it always matches the server). For the restore side, `pg_restore` must be the same or newer than the version that made the dump. If the host package is old, run it from an official image instead of upgrading the host:
```bash
docker run --rm -i -e PGPASSWORD -e PGSSLMODE=require -v "$PWD:/b" postgres:<MAJOR> \
  pg_restore -h <RDS_ENDPOINT> -U <ADMIN> -d <DB> --no-owner --no-privileges /b/db.dump
```

### 6. `role "xyz" does not exist` during restore

**Cause:** the dump carries ownership and GRANTs for roles that only existed in the container.

**Fix:** dump or restore with `--no-owner --no-privileges`, then grant explicitly to the application user (see `scripts/03-restore-to-rds.sh`).

### 7. `must be owner of extension plpgsql` or `permission denied to create extension`

**Cause:** RDS has no true superuser. The master user is in `rds_superuser`, which can create **supported** extensions but can't change built-in ones like `plpgsql`.

**Fix:**
- The `COMMENT ON EXTENSION plpgsql` error is harmless. Exclude it with a filtered list: `pg_restore -l db.dump | grep -v 'COMMENT - EXTENSION plpgsql' > list.txt` then `pg_restore -L list.txt ...`
- For anything else, check the extension is on the RDS supported list for that engine version **before** picking a migration date.

### 8. Restore is slow

**Fix:** custom-format dump + `pg_restore --jobs=N` (N ≈ vCPUs of the RDS instance). Temporarily larger instance class during restore is also an option, then scale back down. Run `ANALYZE` afterwards or the first queries will use bad plans.

### 9. EC2 runs out of disk while dumping

**Fix:** check `df -h` first. Custom format is compressed, but leave headroom of at least the database size. Write the dump to a separate volume or stream a copy to S3 straight after.

---

## After the data is in

### 10. `duplicate key value violates unique constraint "orders_pkey"` on the first new order

**Cause:** a sequence is behind the highest id in its table, so it hands out an id that already exists. Happens when rows were inserted with explicit ids, or a sequence wasn't restored as expected.

**Fix:** compare every owned sequence with `MAX(id)` before switching traffic, and `setval` the ones that are behind. `scripts/sql/fix_sequences.sql` does both (dry run first).

### 11. Flyway fails on startup

| Error | Usual cause | Fix |
|---|---|---|
| `Validate failed: Migration checksum mismatch` | a migration file was edited after it was applied | don't edit applied migrations; if the edit was only whitespace/comments and is understood, `flyway repair` |
| `Detected applied migration not resolved locally` | a service is running an older build than the database schema | deploy the matching version of every service |
| `Found non-empty schema(s) ... without schema history table` | `flyway_schema_history` didn't come across | it must be restored with the data; never "baseline" a migrated production DB to hide this |
| `permission denied for table flyway_schema_history` | app user has only DML grants | run migrations with a separate migration user, or grant the needed rights to the app user deliberately |

### 12. `HikariPool-1 - Connection is not available, request timed out` / `too many connections`

**Cause:** several services × default pool size of 10 can exceed `max_connections` on a small RDS instance (it scales with instance memory).

**Fix:**
```sql
SHOW max_connections;
SELECT count(*) FROM pg_stat_activity;
```
Set `maximum-pool-size` per service so the total stays well below the limit, leaving room for admin sessions and monitoring.

### 13. Timestamps look shifted by 5:30 hours

**Cause:** the container may have run with a local `timezone` setting while RDS defaults to UTC. Columns of type `timestamp without time zone` and code relying on the server's timezone will show different values.

**Fix:** compare `SHOW timezone;` on both before cutover. Either set the same `timezone` in the RDS parameter group, or (better) make the app explicit: `spring.jpa.properties.hibernate.jdbc.time_zone=UTC` and store `timestamptz`.

### 14. Same query, different sort order or slightly different results

**Cause:** different encoding/collation (or a different glibc collation version) between the container and RDS.

**Fix:** compare before migrating:
```sql
SELECT datname, pg_encoding_to_char(encoding), datcollate, datctype FROM pg_database;
```
Create the RDS database with matching settings.
