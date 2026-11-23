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

# md_table "Col A|Col B" "$rows" - print psql rows ('|'-separated) as a Markdown table.
md_table() {
  local header=$1 rows=$2 sep="|" col line
  local -a cols
  if [[ -z $rows ]]; then
    echo "_None._"
    return
  fi
  IFS='|' read -ra cols <<<"$header"
  for col in "${cols[@]}"; do sep+="---|"; done
  echo "| ${header//|/ | } |"
  echo "$sep"
  while IFS= read -r line; do
    echo "| ${line//|/ | } |"
  done <<<"$rows"
}

section_overview() {
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
EOF
}

# Share of block reads served from shared_buffers. Below ~99 % on an OLTP
# database usually means shared_buffers (or RAM) is too small for the working set.
section_cache_hit() {
  echo
  echo "## Cache hit ratio"
  echo
  echo "Overall: **$(q "select coalesce(round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 2)::text || ' %', 'n/a')
                     from pg_stat_database")** (since the last statistics reset)."
  echo
  md_table "Database|Hit ratio %|Blocks from cache|Blocks from disk" "$(q "
    select datname,
           coalesce(round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2)::text, 'n/a'),
           blks_hit, blks_read
    from pg_stat_database
    where datname is not null
    order by blks_hit + blks_read desc")"
}

# Client connections against what is really available to applications
# (max_connections minus the slots reserved for superusers).
section_connections() {
  echo
  echo "## Connections"
  echo
  md_table "Used|Available to applications|max_connections|Used %" "$(q "
    with s as (
      select count(*) filter (where backend_type = 'client backend') as used,
             current_setting('max_connections')::int as max_conn,
             current_setting('max_connections')::int
               - current_setting('superuser_reserved_connections')::int as avail
      from pg_stat_activity)
    select used, avail, max_conn, round(100.0 * used / nullif(avail, 0), 1) from s")"
  echo
  md_table "State|Connections" "$(q "
    select coalesce(state, 'unknown'), count(*)
    from pg_stat_activity
    where backend_type = 'client backend'
    group by 1 order by 2 desc")"
}

section_db_sizes() {
  echo
  echo "## Database sizes"
  echo
  md_table "Database|Size" "$(q "
    select datname, pg_size_pretty(pg_database_size(datname))
    from pg_database
    where datallowconn
    order by pg_database_size(datname) desc")"
}

report() {
  section_overview
  section_cache_hit
  section_connections
  section_db_sizes
}

if [[ -n $output ]]; then
  report >"$output"
  echo "report written to $output" >&2
else
  report
fi
exit 0
