# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/) · versions: [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-11-23

First release.

### Added
- `pg_health.sh`: read-only PostgreSQL health report in Markdown or HTML, needs only `psql` and `pg_monitor`.
- Checks: cache hit ratio, connections, database sizes, table bloat estimate, tables that need
  VACUUM / ANALYZE, unused and duplicate indexes, top queries (`pg_stat_statements`), replication
  and replication slots, transaction ID wraparound.
- OK / WARN / CRIT status with a "what to do" hint per check, a summary table, and exit codes
  0 / 1 / 2 (3 = usage or connection error).
- `--format html` / `-o report.html`: one self-contained page (light and dark theme);
  `--to-html` converts a saved Markdown report.
- `tests/seed.sh` and `tests/check-report.sh`: a demo database with every problem and the checks
  that it is reported.
- CI: ShellCheck, the full report against PostgreSQL 16, a monitoring-role run, and a job with
  `pg_stat_statements` preloaded.

[0.1.0]: https://github.com/ihebooo/pg-health-report/releases/tag/v0.1.0
