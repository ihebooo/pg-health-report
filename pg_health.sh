#!/usr/bin/env bash
# pg_health.sh - one-script PostgreSQL health report (Markdown).
#
# Read-only: it only runs SELECT queries. A role with pg_monitor is enough.
# See --help for usage and exit codes.
set -euo pipefail

readonly VERSION="0.1.0-dev"
readonly PROG=${0##*/}

usage() {
  cat <<EOF
Usage: $PROG [options] [psql connection options...]

Print a health report of a PostgreSQL server in Markdown.

Options:
  -o, --output FILE   write the report to FILE instead of stdout
  -h, --help          show this help and exit
  -V, --version       show the version and exit

Any other argument is passed to psql, e.g.:
  $PROG -h db.example.com -p 5432 -U monitor -d postgres
  $PROG -o report.md "host=db.example.com dbname=postgres sslmode=require"
Without connection options the libpq environment is used
(PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSWORD / ~/.pgpass).

Required privileges: a role with pg_monitor (no superuser needed).

Exit codes:
  0  report produced, every check OK
  1  report produced, at least one WARN
  2  report produced, at least one CRIT
  3  usage error or cannot connect
EOF
}

die() { echo "$PROG: $*" >&2; exit 3; }

output=""
psql_args=()
while (($#)); do
  case $1 in
    -o|--output)
      [[ $# -ge 2 && -n $2 ]] || die "$1 needs a file name (see --help)"
      output=$2
      shift 2
      ;;
    --help)    usage; exit 0 ;;
    -V|--version) echo "$PROG $VERSION"; exit 0 ;;
    *)         psql_args+=("$1"); shift ;;
  esac
done

# -h alone means help, as in most tools; "-h HOST" is passed to psql.
if [[ ${#psql_args[@]} -eq 1 && ${psql_args[0]} == "-h" ]]; then
  usage
  exit 0
fi

command -v psql >/dev/null 2>&1 || die "psql not found in PATH"

# Run one query and print the unaligned result (fields separated by '|').
q() {
  psql "${psql_args[@]}" -X -v ON_ERROR_STOP=1 -F '|' -qAtc "$1"
}

info=$(q "select current_setting('server_version'),
                 coalesce(inet_server_addr()::text, 'local socket'),
                 current_setting('port'),
                 current_database(),
                 current_user,
                 date_trunc('second', now() - pg_postmaster_start_time()),
                 pg_is_in_recovery()" 2>&1) \
  || die "cannot connect: ${info}"

IFS='|' read -r version addr port db user uptime in_recovery <<<"$info"
role="primary"
[[ $in_recovery == "t" ]] && role="standby (in recovery)"

report() {
  cat <<EOF
# PostgreSQL health report

| | |
|---|---|
| Generated | $(date -u '+%Y-%m-%d %H:%M:%S UTC') |
| Server | PostgreSQL ${version} |
| Address | ${addr}:${port} |
| Role | ${role} |
| Up since | ${uptime} |
| Connected as | ${user} @ ${db} |

_Checks are added one by one — see the README for the list._
EOF
}

if [[ -n $output ]]; then
  report >"$output"
  echo "report written to $output" >&2
else
  report
fi
exit 0
