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
```

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
- [ ] cache hit ratio, connections vs `max_connections`, database sizes
- [ ] table bloat estimate, tables that need `VACUUM` / `ANALYZE`
- [ ] unused and duplicate indexes, with the space they waste
- [ ] top queries from `pg_stat_statements` (when installed)
- [ ] replication lag, inactive slots, transaction ID wraparound age
- [ ] OK / WARN / CRIT per check, with a "what to do" hint
- [ ] `--format html` (single self-contained file)

## License

[MIT](LICENSE)
