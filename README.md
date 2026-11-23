# pg-health-report

[![CI](https://github.com/ihebooo/pg-health-report/actions/workflows/ci.yml/badge.svg)](https://github.com/ihebooo/pg-health-report/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**One Bash script, one read-only report:** how healthy is this PostgreSQL server?
No agent, no extension to install, no superuser — just `psql` and a role with `pg_monitor`.

> 🚧 Work in progress — a new check lands almost every day. See the [roadmap](#roadmap).

## Quick start

```bash
git clone https://github.com/ihebooo/pg-health-report.git && cd pg-health-report
./pg_health.sh -h db.example.com -U monitor -d postgres     # report on stdout
./pg_health.sh -o report.md "host=db.example.com dbname=postgres sslmode=require"
```

Without connection options the usual libpq variables are used
(`PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` or `~/.pgpass`).

### A monitoring role

```sql
CREATE ROLE monitor LOGIN PASSWORD 'change-me' IN ROLE pg_monitor;
```

## Example output

```markdown
# PostgreSQL health report

| | |
|---|---|
| Generated | 2026-11-23 08:00:00 UTC |
| Server | PostgreSQL 16.6 (Debian 16.6-1.pgdg120+1) |
| Address | 192.0.2.10:5432 |
| Role | primary |
| Up since | 12 days 03:14:15 |
| Connected as | monitor @ postgres |

## Cache hit ratio

Overall: **99.87 %** (since the last statistics reset).

| Database | Hit ratio % | Blocks from cache | Blocks from disk |
|---|---|---|---|
| appdb | 99.88 | 48211907 | 57230 |
| postgres | 99.12 | 104233 | 921 |

## Connections

| Used | Available to applications | max_connections | Used % |
|---|---|---|---|
| 42 | 197 | 200 | 21.3 |

| State | Connections |
|---|---|
| idle | 35 |
| active | 6 |
| idle in transaction | 1 |

## Database sizes

| Database | Size |
|---|---|
| appdb | 38 GB |
| postgres | 7532 kB |

## Table bloat (estimate, database appdb)

| Table | Size | Estimated bloat | Bloat % |
|---|---|---|---|
| public.order_lines | 4210 MB | 1630 MB | 38.7 |

## Tables that need VACUUM / ANALYZE (database appdb)

| Table | Needs | Live rows | Dead rows | Dead % | Changed since analyze | Last vacuum | Last analyze |
|---|---|---|---|---|---|---|---|
| public.job_queue | VACUUM + ANALYZE | 120344 | 981220 | 89.1 | 1402311 | 2026-11-02 03:11 | 2026-11-02 03:11 |
```

## Checks

| Section | What it shows | Why it matters |
|---|---|---|
| Cache hit ratio | share of block reads served from `shared_buffers`, overall and per database | below ~99 % on an OLTP database the working set does not fit in memory |
| Connections | used vs `max_connections` minus superuser-reserved slots, by state | running out of slots means new logins fail; many `idle in transaction` sessions block `VACUUM` |
| Database sizes | size of every database | growth trend, disk planning |
| Table bloat | pages on disk vs pages the live rows need (from `pg_stats` and fillfactor), tables ≥ 1 MB with ≥ 20 % bloat | wasted disk and slower sequential scans; fix with `pg_repack` or `VACUUM FULL` |
| VACUUM / ANALYZE | tables past their autovacuum / autoanalyze trigger point, dead rows, last runs | autovacuum is behind or blocked: bloat grows, plans go bad |

Bloat and VACUUM checks cover the database you connect to; run the script once per database.
Bloat needs column statistics the role can see — add `pg_read_all_data` (PostgreSQL 14+) to the
monitoring role to include every table.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | report produced, every check OK |
| 1 | report produced, at least one WARN |
| 2 | report produced, at least one CRIT |
| 3 | usage error or cannot connect |

So it can run from cron, a CI job or a monitoring check (Nagios / Zabbix style).

## Roadmap

- [x] skeleton, `--help`, server info header, CI against PostgreSQL 16
- [x] cache hit ratio, connections vs `max_connections`, database sizes
- [x] table bloat estimate, tables that need `VACUUM` / `ANALYZE`
- [ ] unused and duplicate indexes, with the space they waste
- [ ] top queries from `pg_stat_statements` (when installed)
- [ ] replication lag, inactive slots, transaction ID wraparound age
- [ ] OK / WARN / CRIT per check, with a "what to do" hint
- [ ] `--format html` (single self-contained file)

## License

[MIT](LICENSE)
