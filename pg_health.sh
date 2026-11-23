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
  local header=$1 rows=$2 sep="|" line
  local -a cols
  if [[ -z $rows ]]; then
    echo "_None._"
    return
  fi
  IFS='|' read -ra cols <<<"$header"
  for _ in "${cols[@]}"; do sep+="---|"; done
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

# Estimated table bloat: pages on disk vs pages the live rows should need,
# from reltuples, the average row width in pg_stats and the fillfactor.
# An estimate only (no pgstattuple needed); tables under 1 MB are skipped.
section_bloat() {
  echo
  echo "## Table bloat (estimate, database ${db})"
  echo
  md_table "Table|Size|Estimated bloat|Bloat %" "$(q "
    select n.nspname || '.' || c.relname,
           pg_size_pretty(c.relpages::bigint * b.bs),
           pg_size_pretty(((c.relpages - e.pages) * b.bs)::bigint),
           round(100 * (c.relpages - e.pages) / c.relpages, 1)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral (select current_setting('block_size')::numeric as bs) b
    cross join lateral (
      select sum((1 - s.null_frac) * s.avg_width) as width
      from pg_stats s
      where s.schemaname = n.nspname and s.tablename = c.relname) w
    cross join lateral (
      select coalesce((select option_value::int from pg_options_to_table(c.reloptions)
                       where option_name = 'fillfactor'), 100) as ff) f
    cross join lateral (
      -- 24 bytes tuple header, rows aligned to 8 bytes, 4 bytes line pointer per row
      select ceil(c.reltuples * (ceil((24 + w.width) / 8) * 8 + 4)
                  / ((b.bs - 24) * f.ff / 100)) as pages) e
    where c.relkind in ('r', 'm')
      and n.nspname not in ('pg_catalog', 'information_schema')
      and n.nspname !~ '^pg_toast'
      and c.relpages >= 128
      and c.reltuples > 0
      and w.width is not null
      and c.relpages - e.pages >= 0.2 * c.relpages
    order by c.relpages - e.pages desc
    limit 15")"
  echo
  echo "_Tables of at least 1 MB with 20 % or more estimated bloat. Tables whose columns the"
  echo "role cannot read are not visible in pg_stats and are skipped (grant pg_read_all_data on"
  echo "PostgreSQL 14+ to include them). Reclaim space with pg_repack or VACUUM FULL (locks the table)._"
}

# Tables past their autovacuum / autoanalyze trigger point (global settings):
# autovacuum is behind, disabled for the table, or blocked by a long transaction.
section_vacuum() {
  echo
  echo "## Tables that need VACUUM / ANALYZE (database ${db})"
  echo
  md_table "Table|Needs|Live rows|Dead rows|Dead %|Changed since analyze|Last vacuum|Last analyze" "$(q "
    with t as (
      select schemaname || '.' || relname as tbl,
             n_live_tup, n_dead_tup, n_mod_since_analyze,
             greatest(last_vacuum, last_autovacuum) as last_vac,
             greatest(last_analyze, last_autoanalyze) as last_an,
             n_dead_tup > current_setting('autovacuum_vacuum_threshold')::int
                          + current_setting('autovacuum_vacuum_scale_factor')::float8 * n_live_tup
               as need_vac,
             n_mod_since_analyze > current_setting('autovacuum_analyze_threshold')::int
                          + current_setting('autovacuum_analyze_scale_factor')::float8 * n_live_tup
               as need_an
      from pg_stat_user_tables
      where n_live_tup + n_dead_tup >= 1000)
    select tbl,
           concat_ws(' + ', case when need_vac then 'VACUUM' end, case when need_an then 'ANALYZE' end),
           n_live_tup, n_dead_tup,
           round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1),
           n_mod_since_analyze,
           coalesce(to_char(last_vac, 'YYYY-MM-DD HH24:MI'), 'never'),
           coalesce(to_char(last_an, 'YYYY-MM-DD HH24:MI'), 'never')
    from t
    where need_vac or need_an
    order by n_dead_tup desc
    limit 20")"
  echo
  echo "_Run \`VACUUM (ANALYZE, VERBOSE) <table>;\` and check why autovacuum did not:"
  echo "long transactions, \`autovacuum_enabled = off\`, or too few autovacuum workers._"
}

report() {
  section_overview
  section_cache_hit
  section_connections
  section_db_sizes
  section_bloat
  section_vacuum
}

if [[ -n $output ]]; then
  report >"$output"
  echo "report written to $output" >&2
else
  report
fi
exit 0
