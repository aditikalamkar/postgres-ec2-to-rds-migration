# Post-migration test report

| Date | Environment | Tester |
|---|---|---|
| | Production on RDS | |

## Data checks

| Check | Expected | Result |
|---|---|---|
| Row count, every table (source vs RDS) | Identical | ☐ Pass ☐ Fail |
| Sequences ≥ MAX(id) on every table | True | ☐ Pass ☐ Fail |
| `flyway_schema_history` rows | Identical | ☐ Pass ☐ Fail |
| `flyway validate` on service startup | No errors | ☐ Pass ☐ Fail |
| Extensions present | Same list | ☐ Pass ☐ Fail |

## Connectivity and security

| Check | Expected | Result |
|---|---|---|
| RDS `Publicly accessible` | No | ☐ |
| Port 5432 from outside VPC | Times out | ☐ |
| Port 5432 from app instance | Connects | ☐ |
| Connection uses SSL (`pg_stat_ssl`) | `ssl = true` | ☐ |
| Total Hikari max pool across services | Below instance limit | ☐ |

## Business flows

| Flow | Steps | Result | Notes |
|---|---|---|---|
| Authentication | Register, login, token refresh, logout | ☐ | |
| Products | List, search, filter, product detail | ☐ | |
| Pricing | Price shown matches pre-migration for sample products | ☐ | |
| Orders | Add to cart, checkout, order appears in history | ☐ | |
| Inventory | Stock reduces after test order | ☐ | |
| Reports | Sales and inventory reports load with historical data | ☐ | |
| Admin | Admin login, edit a product, change persists | ☐ | |

## Backup and recovery

| Check | Result |
|---|---|
| Automated backups enabled, retention set | ☐ |
| Latest restorable time is recent (PITR working) | ☐ |
| Deletion protection on | ☐ |

## Sign-off

Client approval to close the hold period: ____________________
