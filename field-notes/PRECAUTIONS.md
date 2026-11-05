# Precautions I take on a production database migration

The client's conditions were "no data loss, nothing deleted until approved, no production change without approval, database never public, rollback plan before cutover." These are the habits that turn those conditions into practice.

## Before touching anything

- **Read-only first.** The first session on the server only reads: versions, size, extensions, roles, Flyway history, connection counts. Nothing is changed while I'm still learning the system.
- **Write the plan down and get a yes.** Method, timing, expected downtime, rollback steps and cost go to the client in writing. Every production step has an approval gate.
- **Pick the quiet window from data, not guesses.** Look at when orders actually come in, then agree the window with the business.
- **Match versions.** Same PostgreSQL major version on RDS. An upgrade is its own separate change, later.
- **Check RDS limits up front:** supported extensions, no superuser, parameter differences. Finding these on cutover night is too late.

## Backups

- **A backup isn't real until it's been restored.** Every dump is test-restored into a scratch database and verified.
- **Checksum every dump** (SHA-256) and check it again before restoring.
- **Keep a copy off the instance.** If the EC2 host dies, the backup shouldn't die with it.
- **Take a fresh dump at cutover**, after writes are frozen. The rehearsal dump is only for practice.

## Security

- **Never public.** `Publicly accessible = No`, private subnets only, and the security group allows 5432 only from the app's security group. No `0.0.0.0/0`, not even "just for testing".
- **No secrets in code, Git, images or chat.** Credentials go in environment variables or the client's secret store. The repo has `.gitignore` rules for dumps, `.env` and keys.
- **Least privilege.** The app uses its own user with only the grants it needs. The master user is for administration only.
- **Encryption on from day one:** at rest (KMS) and in transit (`rds.force_ssl`). Turning on storage encryption later means another migration.
- **Deletion protection on.** One click shouldn't be able to remove the production database.

## During cutover

- **Freeze writes properly.** Maintenance page up, write services scaled down, and a check that there are no active writers left, before the final dump.
- **Stop, don't delete.** The old container is stopped and its volume is left alone. It's the rollback path.
- **Rehearse first.** A full dry run (restore, verify, time it) on RDS before the real night, so the timing in the plan is measured, not hoped for.
- **Change one thing at a time.** Database location changes; app code, schema and versions don't.

## Verification before reopening

- Exact row counts for every table, source vs RDS (`count(*)`, not statistics estimates).
- Every sequence at or above its table's highest id.
- Flyway history identical, and `flyway validate` passes.
- End-to-end business test: login, products, pricing, checkout, inventory, reports, admin edit.
- Connections are encrypted (`pg_stat_ssl`) and port 5432 is unreachable from outside the VPC.

## After go-live

- **Hold period.** Old database kept until the client signs off. Deleting it is the client's decision, not mine.
- **Watch the first days:** CPU (and CPU credits on T-class instances), connections, free storage, error rates.
- **Hand over the knowledge:** runbook, rollback plan, cost estimate and test report, so the client isn't dependent on me to operate their own database.
