# Rollback plan

Written and shared with the client **before** cutover.

## Why rollback stays cheap

During cutover, writes are frozen and the old PostgreSQL container is only stopped. Its data volume isn't touched. So at any point before the store reopens, the old database is exactly as it was at the freeze.

## When to roll back

Roll back if any of these happen and can't be fixed inside the agreed window:

- row counts or sequence checks don't match
- `flyway validate` fails against RDS
- a core flow fails in testing (login, checkout, inventory update)
- services can't hold stable connections to RDS

## Steps (before the store reopens)

1. Stop the services.
2. Point their database environment variables back to the old container.
3. Start the PostgreSQL container: `docker start <CONTAINER>`
4. Start the services, confirm health checks and a test login.
5. Take the store out of maintenance mode.
6. Keep RDS running (no traffic) to investigate. Nothing is deleted.

Expected time: about 10 to 15 minutes, because it's a config change and restarts.

## After the store reopens on RDS

New orders now exist only in RDS, so "roll back" stops being a config switch. The plan from this point:

- small problems: fix forward on RDS
- serious problems: freeze writes again, dump RDS, restore into the old container, switch back. This is why the old container is kept for the full hold period.
- data mistakes: RDS point-in-time recovery to a new instance, then compare
