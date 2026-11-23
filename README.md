# pg-health-report

[![CI](https://github.com/ihebooo/pg-health-report/actions/workflows/ci.yml/badge.svg)](https://github.com/ihebooo/pg-health-report/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/ihebooo/pg-health-report)](https://github.com/ihebooo/pg-health-report/releases)

**One Bash script, one read-only report: how healthy is this PostgreSQL server — and what should I do about it?**

No agent, no extension to install, no superuser: just `psql` and a role with `pg_monitor`.
Every check gets **OK / WARN / CRIT** and a concrete next step, and the exit code is the worst
status, so the same script works by hand, from cron, or as a Nagios / Zabbix check.

📄 **Example report:** [Markdown](docs/example-report.md) ·
[HTML](https://htmlpreview.github.io/?https://github.com/ihebooo/pg-health-report/blob/main/docs/example-report.html)

## Quick start

```bash
git clone https://github.com/ihebooo/pg-health-report.git && cd pg-health-report
./pg_health.sh -h db.example.com -U monitor -d appdb              # Markdown on stdout
./pg_health.sh -h db.example.com -U monitor -d appdb -o report.html  # one HTML page
```

Or only the script:

```bash
curl -fsSLO https://raw.githubusercontent.com/ihebooo/pg-health-report/v0.1.0/pg_health.sh
chmod +x pg_health.sh
```

Requirements: Bash 4+, `psql`, `awk`. Tested in CI on PostgreSQL 16; written for PostgreSQL 12 and newer.

### A monitoring role

```sql
CREATE ROLE monitor LOGIN PASSWORD 'change-me' IN ROLE pg_monitor;
-- optional, PostgreSQL 14+: lets the bloat estimate see every table's statistics
GRANT pg_read_all_data TO monitor;
```

`pg_monitor` covers everything else: activity, replication, slots, `pg_stat_statements`.
The script only runs `SELECT`s.

## Usage

```text
pg_health.sh [options] [psql connection options...]

  -o, --output FILE   write the report to FILE (a FILE ending in .html selects HTML)
  -f, --format FMT    md (default) or html
      --to-html FILE  convert a saved Markdown report to HTML, no database needed
  -h, --help          help          -V, --version   version
```

Anything else goes to `psql`: `-h HOST -p PORT -U USER -d DB`, or a connection string such as
`"host=db.example.com dbname=appdb sslmode=require"`. Without options the libpq environment is used
(`PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` or `~/.pgpass`).

Table-level checks (bloat, vacuum, indexes, top queries) cover **the database you connect to** —
run the script once per application database.

## Checks

| Check | What it shows | WARN | CRIT |
|---|---|---|---|
| Cache hit ratio | share of reads served from `shared_buffers`, overall and per database | < 99 % | < 90 % |
| Connections | used vs `max_connections` minus reserved slots, by state | ≥ 75 % used, or a session *idle in transaction* > 5 min | ≥ 90 % used |
| Database sizes | size of every database | — | — |
| Table bloat | estimated wasted space per table (≥ 1 MB, ≥ 20 % bloat) | a table ≥ 50 % bloat | — |
| VACUUM / ANALYZE | tables past their autovacuum / autoanalyze trigger | any | — |
| Unused indexes | indexes never scanned since the stats reset (unique / PK / constraint indexes skipped) | any | — |
| Duplicate indexes | identical indexes on the same table, with the space wasted | any | — |
| Top queries | top 10 by total time from `pg_stat_statements`, or how to enable it | — | — |
| Replication | standbys and lag (primary) or WAL receiver (standby), replication slots | inactive slot, lag > 100 MB | standby not streaming, lag or inactive slot > 1 GB |
| XID wraparound | transaction ID age per database | ≥ 40 % of wraparound | ≥ 70 % |

The cache ratio is only judged after 100 000 block reads, so a freshly started server is not flagged.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | report produced, every check OK |
| 1 | report produced, at least one WARN |
| 2 | report produced, at least one CRIT |
| 3 | usage error, cannot connect, or a query failed |

### In cron, mailed only when something is wrong

```cron
0 7 * * 1-5  postgres  /opt/pg-health-report/pg_health.sh -d appdb -o /tmp/pg_health.md || mail -s "PostgreSQL health: action needed" dba@example.com < /tmp/pg_health.md
```

### As a Nagios / Icinga / NRPE check

```ini
command[check_pg_health]=/opt/pg-health-report/pg_health.sh -d appdb -o /var/tmp/pg_health.html
```

The exit code drives the alert state; the full report is in the HTML file for whoever picks up the alert.

## Try it on a test server

`tests/seed.sh` builds a demo database with one example of every problem (a bloated table, dead rows,
unused and duplicate indexes, an inactive replication slot); `tests/check-report.sh` checks that each
one is reported with the right status. CI runs both against PostgreSQL 16 on every push, plus a job
with `pg_stat_statements` preloaded.

```bash
docker run -d --name pg -p 5432:5432 -e POSTGRES_PASSWORD=postgres postgres:16
sleep 5
export PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres
tests/seed.sh && ./pg_health.sh -d pg_health_demo -o demo.html
docker rm -f pg
```

## Roadmap

- [x] overview, cache hit ratio, connections, database sizes
- [x] table bloat estimate, tables that need `VACUUM` / `ANALYZE`
- [x] unused and duplicate indexes
- [x] top queries (`pg_stat_statements`), replication and slots, XID wraparound
- [x] OK / WARN / CRIT with a hint per check, exit codes
- [x] `--format html`, `--to-html`
- [ ] configurable thresholds (`--warn-cache 98`, …)
- [ ] `--json` output for dashboards
- [ ] all databases in one run

Ideas and bug reports: [open an issue](https://github.com/ihebooo/pg-health-report/issues).
Changes per version: [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
