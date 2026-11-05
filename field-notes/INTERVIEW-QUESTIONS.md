# Senior-level interview questions on this migration

Questions an interviewer might ask about a production EC2 → RDS PostgreSQL migration, with the answers I'd give. Useful for practice, and for anyone reviewing the decisions in this repo.

---

### 1. Why `pg_dump`/`pg_restore` and not AWS DMS?

For a small-to-medium database where a short write freeze is acceptable, native dump/restore is simpler and easier to prove correct. It carries everything PostgreSQL knows about (sequences, constraints, indexes, functions), and I can verify it with exact row counts. DMS is focused on moving table data; it adds a replication instance and tasks to monitor, and secondary objects often need extra handling.

I'd switch to **DMS with full load + CDC** (or native logical replication) when the database is large enough that a dump takes hours, or the business can't accept a write freeze. Then cutover happens on a few seconds of replication lag.

### 2. How would you get near-zero downtime instead of a maintenance window?

Logical replication: create a publication on the source, a subscription on RDS, let it sync, keep it streaming, then switch the app when lag is near zero. Things to watch: tables need primary keys (or replica identity), **sequences are not replicated** so they must be set at cutover, and DDL is not replicated, so schema changes freeze during the sync. A brief pause in writes at the very end is still the safest way to switch.

### 3. How do you prove there was no data loss?

Several layers, cheapest first:
1. Exact `count(*)` for every table, source vs target, compared with `diff`.
2. Sequences ≥ `MAX(id)` for every owned sequence.
3. `flyway_schema_history` identical.
4. For critical tables (orders, payments), checksums over ordered rows, e.g. `md5(string_agg(t::text, '' ORDER BY id))`, compared on both sides.
5. A business test of the real flows.

Row counts alone don't prove content matched, which is why critical tables get a content checksum.

### 4. The first order after cutover fails with a duplicate key error. What happened?

A sequence was behind the data, so `nextval` returned an id that already existed. I'd check `last_value` against `MAX(id)` and `setval` it. Better: this check runs before traffic is switched, so it never reaches a customer.

### 5. Single-AZ or Multi-AZ? How do you decide?

Separate two things. **Data durability** comes from automated backups and point-in-time recovery, and you get those on Single-AZ. **Availability** (surviving an AZ or instance failure in a minute or two) needs Multi-AZ, at roughly double the instance cost.

So the question for the business is: what does an hour of downtime cost compared with the monthly price of a standby? For an early-stage store I'd start Single-AZ with backups and agree the trigger for upgrading. Because the DB subnet group already spans two AZs, the switch is a modify operation.

Also worth saying: Multi-AZ standby (one standby) is not a read replica. It doesn't serve reads; read scaling needs read replicas.

### 6. How do you make sure RDS is never exposed publicly?

Private subnets with no route to an internet gateway, `Publicly accessible = No`, and a security group whose only inbound rule is 5432 from the application's security group (referenced by ID, not by IP). Admin access goes through the app host, an SSM session, or a bastion inside the VPC, never by opening the port. TLS is enforced with `rds.force_ssl`.

### 7. How do Spring Boot services get the new credentials safely?

Through environment variables or a secret store (AWS Secrets Manager or SSM Parameter Store), never in `application.yml` committed to Git or baked into the image. With Secrets Manager you also get rotation; the app then needs to handle reconnecting with new credentials (or use the AWS JDBC wrapper that does this). The app connects with a least-privilege user, not the master user.

### 8. What happens to HikariCP pools when you move to a small RDS instance?

`max_connections` on RDS depends on instance memory, and six services with a default pool of 10 each is already 60 connections plus admin and monitoring. I size pools so the total stays well below the limit. If more services or instances arrive, I'd look at **RDS Proxy** to pool connections centrally and also smooth over failovers.

### 9. Something goes wrong one hour after reopening the store. What's your rollback?

Before reopening, rollback is just config: point the services back to the old container and start it, because writes were frozen and it's unchanged.

After reopening, new orders exist only in RDS, so flipping back would lose them. The options become: fix forward on RDS, or freeze writes again and copy RDS back to the old database before switching. For data mistakes (bad update), RDS point-in-time recovery into a new instance and compare. That's why the plan says when each rollback option stops being valid.

### 10. Why keep the same PostgreSQL major version?

To change one thing at a time. If a query behaves differently after the move, I want to know it's the infrastructure, not the planner or a deprecated feature in a new major version. Major upgrade is a separate change, done later with its own test cycle (RDS supports in-place major upgrade or blue/green deployments).

### 11. Your migration window is 30 minutes and the rehearsal restore took 45. What do you do?

Options, in order: restore with more parallel `--jobs`; temporarily use a bigger instance class and scale down afterwards; drop and rebuild large secondary indexes after the data load; move to logical replication / DMS CDC so the bulk copy happens before the window. What I don't do is start the window and hope.

### 12. How would you estimate and control the monthly cost?

Instance class (on-demand per hour) + storage (gp3 per GB-month) + backup storage beyond the free allowance + data transfer across AZs + CPU credits on T-class instances in Unlimited mode. I'd start with a burstable instance, watch CloudWatch for 30 days (CPU, credit usage, connections, memory), then right-size and consider a Reserved Instance or Database Savings Plan once usage is stable. Moving the database off the app server can also let the EC2 instance shrink.

### 13. What did you monitor after go-live?

`CPUUtilization` and `CPUCreditBalance` (T-class), `DatabaseConnections`, `FreeStorageSpace`, `FreeableMemory`, `ReadLatency`/`WriteLatency`, plus application error rates and slow queries via `log_min_duration_statement` or Performance Insights. Alarms on storage and connections first, because those fail suddenly.

### 14. What would you do differently on a much bigger, busier database?

Logical replication or DMS CDC instead of a freeze; Multi-AZ from the start; RDS Proxy; Secrets Manager with rotation; infrastructure as code (Terraform/CloudFormation) so the environment is reproducible; and a blue/green style cutover with a tested, timed fallback.
