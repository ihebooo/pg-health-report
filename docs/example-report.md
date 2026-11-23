# PostgreSQL health report

| | |
|---|---|
| Generated | 2026-11-23 08:00:00 UTC |
| Server | PostgreSQL 16.6 (Debian 16.6-1.pgdg120+1) |
| Address | 192.0.2.10:5432 |
| Role | primary |
| Up since | 12 days 03:14:15 |
| Connected as | monitor @ appdb |

## Summary

Overall: **CRIT**

| Check | Status | What to do |
|---|---|---|
| Replication | CRIT | an inactive slot retains more than 1 GB of WAL — drop it or bring its consumer back before the disk fills |
| Table bloat | WARN | up to 38.7 % bloat (most space wasted: public.order_lines) — pg_repack, or VACUUM FULL in a maintenance window |
| VACUUM / ANALYZE | WARN | 1 table(s) past the autovacuum trigger, first public.job_queue — vacuum it and find out why autovacuum did not |
| Unused indexes | WARN | 2 index(es) never scanned, largest public.order_lines_created_idx — confirm over a full business cycle, then drop |
| Duplicate indexes | WARN | 1 set(s) of identical indexes, first on table customers — keep one, drop the copies |
| Cache hit ratio | OK | 99.87 % |
| Connections | OK | 21.3 % of the slots used |
| XID wraparound | OK | oldest database at 9.6 % |

## Cache hit ratio

Overall: **99.87 %** (since the last statistics reset).

| Database | Hit ratio % | Blocks from cache | Blocks from disk |
|---|---|---|---|
| appdb | 99.88 | 48211907 | 57230 |
| postgres | 99.12 | 104233 | 921 |

**Status: OK** — 99.87 %

## Connections

| Used | Available to applications | max_connections | Used % |
|---|---|---|---|
| 42 | 197 | 200 | 21.3 |

| State | Connections |
|---|---|
| idle | 35 |
| active | 6 |
| idle in transaction | 1 |

**Status: OK** — 21.3 % of the slots used

## Database sizes

| Database | Size |
|---|---|
| appdb | 38 GB |
| postgres | 7532 kB |

## Table bloat (estimate, database appdb)

| Table | Size | Estimated bloat | Bloat % |
|---|---|---|---|
| public.order_lines | 4210 MB | 1630 MB | 38.7 |
| public.audit_log | 950 MB | 212 MB | 22.3 |

_Tables of at least 1 MB with 20 % or more estimated bloat. Tables whose columns the
role cannot read are not visible in pg_stats and are skipped (grant pg_read_all_data on
PostgreSQL 14+ to include them). Reclaim space with pg_repack or VACUUM FULL (locks the table)._

**Status: WARN** — up to 38.7 % bloat (most space wasted: public.order_lines) — pg_repack, or VACUUM FULL in a maintenance window

## Tables that need VACUUM / ANALYZE (database appdb)

| Table | Needs | Live rows | Dead rows | Dead % | Changed since analyze | Last vacuum | Last analyze |
|---|---|---|---|---|---|---|---|
| public.job_queue | VACUUM + ANALYZE | 120344 | 981220 | 89.1 | 1402311 | 2026-11-02 03:11 | 2026-11-02 03:11 |

_Run `VACUUM (ANALYZE, VERBOSE) <table>;` and check why autovacuum did not:
long transactions, `autovacuum_enabled = off`, or too few autovacuum workers._

**Status: WARN** — 1 table(s) past the autovacuum trigger, first public.job_queue — vacuum it and find out why autovacuum did not

## Unused indexes (database appdb)

| Index | Table | Size | Index scans |
|---|---|---|---|
| public.order_lines_created_idx | order_lines | 512 MB | 0 |
| public.customers_legacy_code_idx | customers | 18 MB | 0 |

_Counted since 2026-10-01 00:00. Make sure that covers a full business cycle (month-end jobs,
reports) and check standbys too: index usage is counted per server. Then
`DROP INDEX CONCURRENTLY <index>;`._

**Status: WARN** — 2 index(es) never scanned, largest public.order_lines_created_idx — confirm over a full business cycle, then drop

## Duplicate indexes (database appdb)

| Table | Identical indexes | Wasted space |
|---|---|---|
| customers | customers_email_idx, customers_email_idx1 | 41 MB |

_Keep the one that backs a constraint (primary key / unique), drop the others with
`DROP INDEX CONCURRENTLY`._

**Status: WARN** — 1 set(s) of identical indexes, first on table customers — keep one, drop the copies

## Top queries by total time (database appdb)

| Calls | Total time | Mean ms | % of total | Rows | Query |
|---|---|---|---|---|---|
| 1840211 | 96.4 min | 3.14 | 41.2 | 1840211 | select * from order_lines where order_id = $1 |
| 2210 | 51.0 min | 1384.62 | 21.8 | 2210 | select customer_id, sum(amount) from invoices where created_at >= $1 group by 1 |
| 98112 | 18.7 min | 11.44 | 8.0 | 98112 | update job_queue set status = $1, updated_at = now() where id = $2 |

_Start with the top lines: `EXPLAIN (ANALYZE, BUFFERS)` the query, look for missing
indexes or row-by-row loops. Reset the counters with `SELECT pg_stat_statements_reset();`._

## Replication

| Standby | Address | State | Sync | Replay lag | Lag (time) |
|---|---|---|---|---|---|
| standby1 | 192.0.2.11 | streaming | async | 0 bytes | 00:00:00 |

### Replication slots

| Slot | Type | Active | WAL retained |
|---|---|---|---|
| old_reporting | logical | no | 14 GB |
| standby1 | physical | yes | 120 kB |

_An inactive slot keeps every WAL file since its restart point until the disk fills up.
Drop it when its consumer is gone: `SELECT pg_drop_replication_slot('<slot>');`._

**Status: CRIT** — an inactive slot retains more than 1 GB of WAL — drop it or bring its consumer back before the disk fills

## Transaction ID wraparound

| Database | XID age | % of wraparound | autovacuum_freeze_max_age |
|---|---|---|---|
| appdb | 206118343 | 9.6 | 200000000 |
| postgres | 104871 | 0.0 | 200000000 |

_Above autovacuum_freeze_max_age autovacuum runs an aggressive freeze. If the age keeps
growing, look for long transactions, abandoned prepared transactions or inactive slots,
then `VACUUM (FREEZE, VERBOSE)` the oldest tables._

**Status: OK** — oldest database at 9.6 %
