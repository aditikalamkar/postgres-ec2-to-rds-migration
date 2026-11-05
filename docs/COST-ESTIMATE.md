# Estimated monthly AWS cost

Region: Asia Pacific (Mumbai), `ap-south-1`. On-demand pricing, PostgreSQL engine, approximate figures in USD as checked in late 2026. Always confirm with the [AWS Pricing Calculator](https://calculator.aws/) before committing, prices change.

## Instance options considered

| Instance | vCPU / RAM | Single-AZ (~/month) | Multi-AZ (~/month) | Fit |
|---|---|---|---|---|
| db.t4g.micro | 2 / 1 GiB | ~$15 | ~$30 | Dev/test only; too little memory for six services |
| **db.t4g.small** | 2 / 2 GiB | **~$31** | ~$62 | **Recommended start** for current traffic |
| db.t4g.medium | 2 / 4 GiB | ~$61 | ~$122 | Next step when memory or connections get tight |

On top of the instance:

- **Storage (gp3):** billed per GB-month; a few dollars for a small database
- **Backups:** free up to the size of your provisioned storage, extra beyond that
- **CPU credits:** T-class RDS instances run in Unlimited mode, so a database that stays above its CPU baseline all day gets charged extra. Watch the CPU metric for the first weeks.
- **Data transfer:** traffic between EC2 and RDS in the same AZ is free; across AZs is charged per GB

## Recommendation

Start on **db.t4g.small, Single-AZ, gp3, 7-day backups** for roughly **$35–40/month** all in. Revisit after 30 days of CloudWatch metrics. If it stays steady, a 1-year Reserved Instance or a Database Savings Plan brings it down further.

## Saving the EC2 side

With PostgreSQL off the application instance, the EC2 box no longer needs memory headroom for the database. After the hold period, it may be possible to right-size it, which can offset part of the RDS cost.
