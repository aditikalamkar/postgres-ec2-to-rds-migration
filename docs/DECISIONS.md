# Decisions and trade-offs

## 1. pg_dump / pg_restore instead of AWS DMS

**Chosen:** native dump and restore during a short write freeze.

**Why:**
- The database is small enough that a dump and parallel restore fits comfortably in a quiet-hour window.
- The output is easy to verify: exact row counts, sequences, schema all compared directly.
- Native tools carry over everything PostgreSQL knows about (constraints, indexes, sequences, functions). DMS focuses on table data and can need extra work for secondary objects.
- Fewer moving parts: no replication instance, no ongoing CDC task to watch.

**When I'd pick DMS instead:** large databases where a dump takes hours, or a business that can't accept even a short write freeze. Then DMS full load plus change data capture, cutover on a few seconds of lag.

## 2. Same PostgreSQL major version

Upgrading the major version during a move doubles the risk: if something breaks you don't know which change caused it. Move first, upgrade later as its own change.

## 3. Single-AZ to start, Multi-AZ as a planned upgrade

Single-AZ with automated backups and point-in-time recovery protects the data. Multi-AZ protects uptime (automatic failover to a standby), at roughly double the instance cost. For the current traffic, I recommended Single-AZ, and listed the triggers to switch: sustained order volume, a business requirement around downtime, or after the first busy-season review. The switch is a modify operation, no data migration.

## 4. Security choices

- No public access, no CIDR-based rules: only the app security group can reach 5432.
- App uses its own least-privilege user, not the master user.
- TLS enforced with `rds.force_ssl`.
- Encryption at rest on, deletion protection on.
- Credentials supplied through environment variables / the client's secret store, never committed.
