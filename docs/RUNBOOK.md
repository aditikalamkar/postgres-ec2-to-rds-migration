# Migration runbook

Every step marked **GATE** needs a written "go" from the client before it starts. Nothing in production changes without one.

Placeholders: `<RDS_ENDPOINT>`, `<DB_NAME>`, `<APP_USER>`, `<CONTAINER>`. Real values were kept in the client's secret store, never in this repo.

## Phase 0 — Discovery (read-only)

- [ ] Record PostgreSQL version inside the container: `SELECT version();`
- [ ] Record database size: `SELECT pg_size_pretty(pg_database_size(current_database()));`
- [ ] List extensions: `\dx` — confirm each is supported on RDS for the chosen version
- [ ] List roles and which service uses which
- [ ] Check Flyway history: `SELECT version, success FROM flyway_schema_history ORDER BY installed_rank;`
- [ ] Note current peak and quiet traffic hours (for the maintenance window)
- [ ] Run `scripts/01-preflight.sh`

## Phase 1 — Plan and approvals

- [ ] Share: method, window, expected downtime, rollback plan, cost estimate
- [ ] **GATE:** client approves plan and window

## Phase 2 — Backup you can trust

- [ ] `scripts/02-backup.sh` → custom-format dump + SHA-256
- [ ] Copy dump off the instance (S3 with encryption, or the client's chosen location)
- [ ] Test restore into a scratch database and run `scripts/04-verify.sh` against it

## Phase 3 — Build RDS (no production impact)

- [ ] DB subnet group with **private** subnets only
- [ ] Security group `rds-sg`: inbound TCP 5432 **source = app security group**. No CIDR rules, no `0.0.0.0/0`
- [ ] Parameter group: `rds.force_ssl = 1`, sensible `log_min_duration_statement`
- [ ] Instance: same PostgreSQL major version, gp3 storage, encryption at rest on, deletion protection on, `Publicly accessible = No`
- [ ] Automated backups on (retention agreed with client), maintenance window set outside business hours
- [ ] Create `<APP_USER>` with only the privileges the services need
- [ ] Rehearsal: restore the Phase 2 dump into RDS, verify, time it, then drop the rehearsal database

## Phase 4 — Cutover (maintenance window)

- [ ] **GATE:** client confirms "start cutover"
- [ ] Put storefront in maintenance mode; scale write-path services to zero
- [ ] Confirm no active writes: `SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND datname = '<DB_NAME>';`
- [ ] Final dump with `scripts/02-backup.sh`
- [ ] Restore with `scripts/03-restore-to-rds.sh`
- [ ] `scripts/04-verify.sh` — row counts, sequences, Flyway history must all match
- [ ] Switch service environment variables to RDS (see `config/application-rds.yml.example`)
- [ ] Start services; watch logs for Flyway validation and Hikari pool startup

## Phase 5 — Test

- [ ] Run through `docs/TEST-REPORT.md`
- [ ] **GATE:** client confirms the store works; maintenance mode off

## Phase 6 — Hold period

- [ ] Old container **stopped, not removed**; volume and final dump kept
- [ ] Watch RDS CPU, connections, free storage, and app error rates
- [ ] **GATE:** client signs off; only then is cleanup of the old container scheduled (by the client's decision)
