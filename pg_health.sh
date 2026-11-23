#!/usr/bin/env bash
# pg_health.sh - one-script PostgreSQL health report (Markdown or HTML).
#
# Read-only: it only runs SELECT queries. A role with pg_monitor is enough.
# See --help for usage and exit codes.
set -euo pipefail

readonly VERSION="0.1.0"
readonly PROG=${0##*/}

usage() {
  cat <<EOF
Usage: $PROG [options] [psql connection options...]

Print a health report of a PostgreSQL server in Markdown or HTML.

Options:
  -o, --output FILE   write the report to FILE instead of stdout
                      (a FILE ending in .html selects --format html)
  -f, --format FMT    md (default) or html: one self-contained page
      --to-html FILE  convert a saved Markdown report to HTML and exit
                      (no database connection)
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

# md_to_html - turn the report's Markdown (stdin) into one self-contained HTML
# page (stdout). Handles only what this script writes: headings, tables,
# paragraphs, **bold**, `code` and _notes_. Plain POSIX awk, no dependency.
md_to_html() {
  awk '
    # replace without gsub: "&" in a gsub replacement means "the match", and
    # escaping it differs between awk implementations
    function rep(t, a, b,   n, p, i, o) { n = split(t, p, a); o = p[1]; for (i = 2; i <= n; i++) o = o b p[i]; return o }
    function esc(t) { return rep(rep(rep(t, "&", "&amp;"), "<", "&lt;"), ">", "&gt;") }
    function bold(t,   o, i, j, r) {
      o = ""
      while ((i = index(t, "**")) > 0) {
        r = substr(t, i + 2); j = index(r, "**"); if (!j) break
        o = o substr(t, 1, i - 1) "<strong>" substr(r, 1, j - 1) "</strong>"; t = substr(r, j + 2)
      }
      return o t
    }
    function inline(t,   o, i, j, r) {
      t = esc(t); o = ""
      while ((i = index(t, "`")) > 0) {
        r = substr(t, i + 1); j = index(r, "`"); if (!j) break
        o = o bold(substr(t, 1, i - 1)) "<code>" substr(r, 1, j - 1) "</code>"; t = substr(r, j + 1)
      }
      t = o bold(t)
      gsub(/<strong>Status: OK<\/strong>/, "<span class=\"st OK\">OK</span>", t)
      gsub(/<strong>Status: WARN<\/strong>/, "<span class=\"st WARN\">WARN</span>", t)
      gsub(/<strong>Status: CRIT<\/strong>/, "<span class=\"st CRIT\">CRIT</span>", t)
      gsub(/Overall: <strong>OK<\/strong>/, "Overall: <span class=\"st OK\">OK</span>", t)
      gsub(/Overall: <strong>WARN<\/strong>/, "Overall: <span class=\"st WARN\">WARN</span>", t)
      gsub(/Overall: <strong>CRIT<\/strong>/, "Overall: <span class=\"st CRIT\">CRIT</span>", t)
      return t
    }
    function cell(t, tag) {
      gsub(/^ +| +$/, "", t)
      if (t == "OK" || t == "WARN" || t == "CRIT") return "<" tag "><span class=\"st " t "\">" t "</span></" tag ">"
      return "<" tag ">" inline(t) "</" tag ">"
    }
    function flush_para(   t) {
      if (para == "") return
      t = para; para = ""
      if (t ~ /^_.*_$/) { print "<p class=\"note\">" inline(substr(t, 2, length(t) - 2)) "</p>"; return }
      print "<p>" inline(t) "</p>"
    }
    function close_table() { if (intable) { print "</tbody></table></div>"; intable = 0 } }
    BEGIN { para = ""; intable = 0; body = ""; title = "PostgreSQL health report" }
    /^\|/ {
      flush_para()
      if ($0 ~ /^\|(---\|)+$/) next
      line = $0; sub(/^\| ?/, "", line); sub(/ ?\|$/, "", line)
      n = split(line, c, "|")
      if (!intable) { printf "<div class=\"tw\"><table><thead><tr>"; for (k = 1; k <= n; k++) printf "%s", cell(c[k], "th"); print "</tr></thead><tbody>"; intable = 1; next }
      printf "<tr>"; for (k = 1; k <= n; k++) printf "%s", cell(c[k], "td"); print "</tr>"
      next
    }
    { close_table() }
    /^### / { flush_para(); print "<h3>" inline(substr($0, 5)) "</h3>"; next }
    /^## /  { flush_para(); print "<h2>" inline(substr($0, 4)) "</h2>"; next }
    /^# /   { flush_para(); print "<h1>" inline(substr($0, 3)) "</h1>"; next }
    /^[[:space:]]*$/ { flush_para(); next }
    { para = (para == "" ? $0 : para " " $0) }
    END { flush_para(); close_table() }
  ' | {
    cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PostgreSQL health report</title>
<style>
  :root { --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --line: #d1d9e0; --head: #f6f8fa;
          --ok: #1a7f37; --warn: #9a6700; --crit: #cf222e; --code: #eff1f3; }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --line: #3d444d; --head: #151b23;
            --ok: #3fb950; --warn: #d29922; --crit: #f85149; --code: #262c36; }
  }
  body { margin: 0 auto; max-width: 1100px; padding: 24px 16px 48px; background: var(--bg); color: var(--fg);
         font: 15px/1.5 -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
  h1 { font-size: 26px; margin: 0 0 16px; }
  h2 { font-size: 20px; margin: 36px 0 10px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
  h3 { font-size: 16px; margin: 20px 0 8px; }
  .tw { overflow-x: auto; margin: 8px 0; }
  table { border-collapse: collapse; font-size: 14px; }
  th, td { border: 1px solid var(--line); padding: 5px 10px; text-align: left; vertical-align: top; }
  th { background: var(--head); }
  td { font-variant-numeric: tabular-nums; }
  code { background: var(--code); padding: 1px 5px; border-radius: 4px; font-size: 13px;
         font-family: ui-monospace, SFMono-Regular, Consolas, monospace; }
  p.note { color: var(--muted); font-size: 13px; }
  .st { display: inline-block; min-width: 44px; text-align: center; padding: 1px 8px; border-radius: 10px;
        color: #fff; font-weight: 600; font-size: 12px; }
  .st.OK { background: var(--ok); } .st.WARN { background: var(--warn); } .st.CRIT { background: var(--crit); }
  footer { margin-top: 40px; color: var(--muted); font-size: 12px; }
</style>
</head>
<body>
HTML
    cat
    printf '<footer>Generated by pg_health.sh %s — https://github.com/ihebooo/pg-health-report</footer>\n' "$VERSION"
    printf '</body>\n</html>\n'
  }
}

output=""
format=""
psql_args=()
while (($#)); do
  case $1 in
    -o|--output)
      [[ $# -ge 2 && -n $2 ]] || die "$1 needs a file name (see --help)"
      output=$2
      shift 2
      ;;
    -f|--format)
      [[ $# -ge 2 && ( $2 == md || $2 == html ) ]] || die "$1 needs md or html (see --help)"
      format=$2
      shift 2
      ;;
    --to-html)
      [[ $# -ge 2 && -r $2 ]] || die "$1 needs a readable Markdown report"
      md_to_html <"$2"
      exit 0
      ;;
    --help)    usage; exit 0 ;;
    -V|--version) echo "$PROG $VERSION"; exit 0 ;;
    *)         psql_args+=("$1"); shift ;;
  esac
done

if [[ -z $format ]]; then
  format=md
  [[ $output == *.html ]] && format=html
fi

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
                 coalesce(host(inet_server_addr()), 'local socket'),
                 current_setting('port'),
                 current_database(),
                 current_user,
                 date_trunc('second', now() - pg_postmaster_start_time()),
                 pg_is_in_recovery()" 2>&1) \
  || die "cannot connect: ${info}"

IFS='|' read -r version addr port db user uptime in_recovery <<<"$info"
role="primary"
[[ $in_recovery == "t" ]] && role="standby (in recovery)"

# md_table "Col A|Col B" "SQL" - run SQL and print its rows as a Markdown table.
# A failing query stops the report with exit 3 instead of showing an empty table.
md_table() {
  local header=$1 rows sep="|" line
  local -a cols
  rows=$(q "$2") || die "query failed (see the psql error above)"
  table_rows=$rows   # kept for the status of the calling section
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

# --- status of each check -----------------------------------------------------
worst=0          # 0 OK, 1 WARN, 2 CRIT -> exit code
summary=()       # "check|STATUS|what to do"
table_rows=""

# status LEVEL CHECK HINT - print the status line of a section and remember it.
status() {
  local level=$1 check=$2 hint=$3 n=0
  case $level in
    WARN) n=1 ;;
    CRIT) n=2 ;;
  esac
  (( n > worst )) && worst=$n
  summary+=("${check}|${level}|${hint}")
  echo
  echo "**Status: ${level}** — ${hint}"
}

# ge A B - true when number A >= number B (decimals allowed).
ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }

# max_field N - largest value of field N (1-based) in the last table's rows.
max_field() {
  [[ -n $table_rows ]] || { echo 0; return; }
  awk -F'|' -v f="$1" 'BEGIN { m = 0; s = "0" } $f + 0 > m { m = $f + 0; s = $f } END { print s }' <<<"$table_rows"
}

# first_field - first column of the first row of the last table.
first_field() { local l=${table_rows%%$'\n'*}; echo "${l%%|*}"; }

row_count() { [[ -n $table_rows ]] && wc -l <<<"$table_rows" || echo 0; }

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
  local overall
  overall=$(q "select coalesce(round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 2)::text || ' %', 'n/a')
               from pg_stat_database") || die "query failed (see the psql error above)"
  echo "Overall: **${overall}** (since the last statistics reset)."
  echo
  md_table "Database|Hit ratio %|Blocks from cache|Blocks from disk" "
    select datname,
           coalesce(round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2)::text, 'n/a'),
           blks_hit, blks_read
    from pg_stat_database
    where datname is not null
    order by blks_hit + blks_read desc"
  local blocks ratio
  IFS='|' read -r blocks ratio <<<"$(q "select coalesce(sum(blks_hit + blks_read), 0),
                                              coalesce(round(100.0 * sum(blks_hit) / nullif(sum(blks_hit + blks_read), 0), 2), 100)
                                       from pg_stat_database")"
  if ! ge "$blocks" 100000; then
    status OK "Cache hit ratio" "not enough reads since the statistics reset to judge yet"
  elif ! ge "$ratio" 90; then
    status CRIT "Cache hit ratio" "${ratio} %: most reads go to disk — raise shared_buffers or add RAM, look for full scans (top queries)"
  elif ! ge "$ratio" 99; then
    status WARN "Cache hit ratio" "${ratio} %: the working set does not fit in memory — check shared_buffers and the top queries"
  else
    status OK "Cache hit ratio" "${ratio} %"
  fi
}

# Client connections against what is really available to applications
# (max_connections minus the slots reserved for superusers).
section_connections() {
  echo
  echo "## Connections"
  echo
  md_table "Used|Available to applications|max_connections|Used %" "
    with s as (
      select count(*) filter (where backend_type = 'client backend') as used,
             current_setting('max_connections')::int as max_conn,
             current_setting('max_connections')::int
               - current_setting('superuser_reserved_connections')::int as avail
      from pg_stat_activity)
    select used, avail, max_conn, round(100.0 * used / nullif(avail, 0), 1) from s"
  local pct
  pct=$(awk -F'|' '{ print $4 + 0 }' <<<"$table_rows")
  echo
  md_table "State|Connections" "
    select coalesce(state, 'unknown'), count(*)
    from pg_stat_activity
    where backend_type = 'client backend'
    group by 1 order by 2 desc"
  local idle_tx
  idle_tx=$(q "select count(*) from pg_stat_activity
               where state like 'idle in transaction%'
                 and now() - state_change > interval '5 minutes'") \
    || die "query failed (see the psql error above)"
  if ge "$pct" 90; then
    status CRIT "Connections" "${pct} % of the slots used: new logins will soon fail — find who holds them, use a pooler (PgBouncer)"
  elif ge "$pct" 75; then
    status WARN "Connections" "${pct} % of the slots used — check for connection leaks before raising max_connections"
  elif (( idle_tx > 0 )); then
    status WARN "Connections" "${idle_tx} session(s) idle in transaction for more than 5 minutes: they hold locks and block VACUUM"
  else
    status OK "Connections" "${pct} % of the slots used"
  fi
}

section_db_sizes() {
  echo
  echo "## Database sizes"
  echo
  md_table "Database|Size" "
    select datname, pg_size_pretty(pg_database_size(datname))
    from pg_database
    where datallowconn
    order by pg_database_size(datname) desc"
}

# Estimated table bloat: pages on disk vs pages the live rows should need,
# from reltuples, the average row width in pg_stats and the fillfactor.
# An estimate only (no pgstattuple needed); tables under 1 MB are skipped.
section_bloat() {
  echo
  echo "## Table bloat (estimate, database ${db})"
  echo
  md_table "Table|Size|Estimated bloat|Bloat %" "
    select n.nspname || '.' || c.relname,
           pg_size_pretty(c.relpages::bigint * b.bs),
           pg_size_pretty(((c.relpages - e.pages) * b.bs)::bigint),
           round(100 * (c.relpages - e.pages) / c.relpages, 1)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    cross join lateral (select current_setting('block_size')::numeric as bs) b
    cross join lateral (
      select sum(((1 - s.null_frac) * s.avg_width)::numeric) as width
      from pg_stats s
      where s.schemaname = n.nspname and s.tablename = c.relname) w
    cross join lateral (
      select coalesce((select option_value::int from pg_options_to_table(c.reloptions)
                       where option_name = 'fillfactor'), 100) as ff) f
    cross join lateral (
      -- 24 bytes tuple header, rows aligned to 8 bytes, 4 bytes line pointer per row
      select ceil(c.reltuples::numeric * (ceil((24 + w.width) / 8) * 8 + 4)
                  / ((b.bs - 24) * f.ff / 100)) as pages) e
    where c.relkind in ('r', 'm')
      and n.nspname not in ('pg_catalog', 'information_schema')
      and n.nspname !~ '^pg_toast'
      and c.relpages >= 128
      and c.reltuples > 0
      and w.width is not null
      and c.relpages - e.pages >= 0.2 * c.relpages
    order by c.relpages - e.pages desc
    limit 15"
  echo
  echo "_Tables of at least 1 MB with 20 % or more estimated bloat. Tables whose columns the"
  echo "role cannot read are not visible in pg_stats and are skipped (grant pg_read_all_data on"
  echo "PostgreSQL 14+ to include them). Reclaim space with pg_repack or VACUUM FULL (locks the table)._"
  local top
  top=$(max_field 4)
  if ge "$top" 50; then
    status WARN "Table bloat" "up to ${top} % bloat (most space wasted: $(first_field)) — pg_repack, or VACUUM FULL in a maintenance window"
  elif [[ -n $table_rows ]]; then
    status OK "Table bloat" "some bloat (up to ${top} %), nothing urgent"
  else
    status OK "Table bloat" "no table with significant bloat"
  fi
}

# Tables past their autovacuum / autoanalyze trigger point (global settings):
# autovacuum is behind, disabled for the table, or blocked by a long transaction.
section_vacuum() {
  echo
  echo "## Tables that need VACUUM / ANALYZE (database ${db})"
  echo
  md_table "Table|Needs|Live rows|Dead rows|Dead %|Changed since analyze|Last vacuum|Last analyze" "
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
    limit 20"
  echo
  echo "_Run \`VACUUM (ANALYZE, VERBOSE) <table>;\` and check why autovacuum did not:"
  echo "long transactions, \`autovacuum_enabled = off\`, or too few autovacuum workers._"
  if [[ -n $table_rows ]]; then
    status WARN "VACUUM / ANALYZE" "$(row_count) table(s) past the autovacuum trigger, first $(first_field) — vacuum it and find out why autovacuum did not"
  else
    status OK "VACUUM / ANALYZE" "autovacuum keeps up"
  fi
}

# Indexes never used since the statistics were reset. Unique and primary-key
# indexes are skipped: they enforce constraints even when no query reads them.
section_unused_indexes() {
  echo
  echo "## Unused indexes (database ${db})"
  echo
  md_table "Index|Table|Size|Index scans" "
    select s.schemaname || '.' || s.indexrelname,
           s.relname,
           pg_size_pretty(pg_relation_size(s.indexrelid)),
           s.idx_scan
    from pg_stat_user_indexes s
    join pg_index i on i.indexrelid = s.indexrelid
    where s.idx_scan = 0
      and not i.indisunique
      and not i.indisprimary
      and not exists (select 1 from pg_constraint c where c.conindid = s.indexrelid)
    order by pg_relation_size(s.indexrelid) desc
    limit 20"
  local unused=$table_rows
  echo
  local since
  since=$(q "select coalesce(to_char(stats_reset, 'YYYY-MM-DD HH24:MI'), 'server start')
             from pg_stat_database where datname = current_database()") \
    || die "query failed (see the psql error above)"
  echo "_Counted since ${since}. Make sure that covers a full business cycle (month-end jobs,"
  echo "reports) and check standbys too: index usage is counted per server. Then"
  echo "\`DROP INDEX CONCURRENTLY <index>;\`._"
  table_rows=$unused
  if [[ -n $table_rows ]]; then
    status WARN "Unused indexes" "$(row_count) index(es) never scanned, largest $(first_field) — confirm over a full business cycle, then drop"
  else
    status OK "Unused indexes" "every index has been used"
  fi
}

# Indexes with the same table, columns, operator classes, expressions and
# predicate: every copy but one only costs disk and slows down writes.
section_duplicate_indexes() {
  echo
  echo "## Duplicate indexes (database ${db})"
  echo
  md_table "Table|Identical indexes|Wasted space" "
    with i as (
      select x.indrelid, x.indexrelid,
             x.indkey::text || ' ' || x.indclass::text || ' ' || x.indcollation::text || ' '
               || coalesce(pg_get_expr(x.indexprs, x.indrelid), '') || ' '
               || coalesce(pg_get_expr(x.indpred, x.indrelid), '') as signature
      from pg_index x
      join pg_class c on c.oid = x.indrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname not in ('pg_catalog', 'information_schema')
        and n.nspname !~ '^pg_toast')
    select indrelid::regclass,
           string_agg(indexrelid::regclass::text, ', ' order by indexrelid::regclass::text),
           pg_size_pretty(sum(pg_relation_size(indexrelid)) - max(pg_relation_size(indexrelid)))
    from i
    group by indrelid, signature
    having count(*) > 1
    order by sum(pg_relation_size(indexrelid)) - max(pg_relation_size(indexrelid)) desc"
  echo
  echo "_Keep the one that backs a constraint (primary key / unique), drop the others with"
  echo "\`DROP INDEX CONCURRENTLY\`._"
  if [[ -n $table_rows ]]; then
    status WARN "Duplicate indexes" "$(row_count) set(s) of identical indexes, first on table $(first_field) — keep one, drop the copies"
  else
    status OK "Duplicate indexes" "no duplicates"
  fi
}

# Most expensive statements from pg_stat_statements, when it is installed in
# this database AND loaded (shared_preload_libraries); otherwise how to enable it.
section_top_queries() {
  echo
  echo "## Top queries by total time (database ${db})"
  echo
  local state
  state=$(q "select case
                when not exists (select 1 from pg_extension where extname = 'pg_stat_statements')
                  then 'not-installed'
                when current_setting('shared_preload_libraries') !~ 'pg_stat_statements'
                  then 'not-loaded'
                else 'ok' end") || die "query failed (see the psql error above)"
  case $state in
    not-installed)
      echo "_pg_stat_statements is not installed in this database. Add it to"
      echo "\`shared_preload_libraries\`, restart, then \`CREATE EXTENSION pg_stat_statements;\`._"
      return ;;
    not-loaded)
      echo "_The extension exists but is not loaded: add pg_stat_statements to"
      echo "\`shared_preload_libraries\` and restart PostgreSQL._"
      return ;;
  esac
  local total="total_exec_time" mean="mean_exec_time"
  if (( $(q "select current_setting('server_version_num')::int") < 130000 )); then
    total="total_time"; mean="mean_time"   # column names before PostgreSQL 13
  fi
  md_table "Calls|Total time|Mean ms|% of total|Rows|Query" "
    select calls,
           case when ${total} >= 60000 then round((${total} / 60000)::numeric, 1) || ' min'
                else round((${total} / 1000)::numeric, 1) || ' s' end,
           round(${mean}::numeric, 2),
           round((100 * ${total} / nullif(sum(${total}) over (), 0))::numeric, 1),
           rows,
           replace(left(regexp_replace(query, '\s+', ' ', 'g'), 90), '|', '¦')
    from pg_stat_statements
    where dbid = (select oid from pg_database where datname = current_database())
    order by ${total} desc
    limit 10"
  echo
  echo "_Start with the top lines: \`EXPLAIN (ANALYZE, BUFFERS)\` the query, look for missing"
  echo "indexes or row-by-row loops. Reset the counters with \`SELECT pg_stat_statements_reset();\`._"
}

# Streaming replication seen from this server, plus slots that hold WAL back.
section_replication() {
  echo
  echo "## Replication"
  echo
  if [[ $in_recovery == "t" ]]; then
    md_table "WAL receiver|Primary|Last message|Replay delay" "
      select status, coalesce(sender_host, '-') || ':' || coalesce(sender_port::text, '-'),
             date_trunc('second', now() - last_msg_receipt_time),
             coalesce(date_trunc('second', now() - pg_last_xact_replay_timestamp())::text, 'n/a')
      from pg_stat_wal_receiver"
    echo
    echo "_No WAL receiver row means the standby is not connected to its primary (check its log)._"
  else
    md_table "Standby|Address|State|Sync|Replay lag|Lag (time)" "
      select application_name, coalesce(client_addr::text, 'local'), state, sync_state,
             pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)),
             coalesce(date_trunc('second', replay_lag)::text, '-')
      from pg_stat_replication
      order by application_name"
  fi
  echo
  echo "### Replication slots"
  echo
  local lsn="pg_current_wal_lsn()"
  [[ $in_recovery == "t" ]] && lsn="pg_last_wal_replay_lsn()"
  md_table "Slot|Type|Active|WAL retained" "
    select slot_name, slot_type, case when active then 'yes' else 'no' end,
           coalesce(pg_size_pretty(pg_wal_lsn_diff(${lsn}, restart_lsn)), 'n/a')
    from pg_replication_slots
    order by active, pg_wal_lsn_diff(${lsn}, restart_lsn) desc nulls last"
  echo
  echo "_An inactive slot keeps every WAL file since its restart point until the disk fills up."
  echo "Drop it when its consumer is gone: \`SELECT pg_drop_replication_slot('<slot>');\`._"

  local broken lag_bytes inactive retained
  if [[ $in_recovery == "t" ]]; then
    broken=$(q "select count(*) = 0 or bool_or(status <> 'streaming') from pg_stat_wal_receiver")
    lag_bytes=0
  else
    IFS='|' read -r broken lag_bytes <<<"$(q "select coalesce(bool_or(state <> 'streaming'), false),
             coalesce(max(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)), 0)::bigint
      from pg_stat_replication")"
  fi
  IFS='|' read -r inactive retained <<<"$(q "select count(*) filter (where not active),
         coalesce(max(pg_wal_lsn_diff(${lsn}, restart_lsn)) filter (where not active), 0)::bigint
    from pg_replication_slots")"
  if [[ $broken == "t" ]]; then
    status CRIT "Replication" "a standby is not streaming — check both server logs, network and pg_hba"
  elif ge "$retained" 1073741824; then
    status CRIT "Replication" "an inactive slot retains more than 1 GB of WAL — drop it or bring its consumer back before the disk fills"
  elif ge "$lag_bytes" 1073741824; then
    status CRIT "Replication" "a standby is more than 1 GB behind — check its disk I/O and network"
  elif (( inactive > 0 )); then
    status WARN "Replication" "${inactive} inactive replication slot(s) holding WAL — drop them if their consumer is gone"
  elif ge "$lag_bytes" 104857600; then
    status WARN "Replication" "a standby is more than 100 MB behind"
  else
    status OK "Replication" "no lag problem, no inactive slot"
  fi
}

# Transaction ID age per database. At 2^31 PostgreSQL stops accepting writes to
# prevent wraparound; autovacuum freezes rows long before that if it can.
section_wraparound() {
  echo
  echo "## Transaction ID wraparound"
  echo
  md_table "Database|XID age|% of wraparound|autovacuum_freeze_max_age" "
    select datname, age(datfrozenxid),
           round(100.0 * age(datfrozenxid) / 2147483648, 1),
           current_setting('autovacuum_freeze_max_age')
    from pg_database
    order by age(datfrozenxid) desc"
  echo
  echo "_Above autovacuum_freeze_max_age autovacuum runs an aggressive freeze. If the age keeps"
  echo "growing, look for long transactions, abandoned prepared transactions or inactive slots,"
  echo "then \`VACUUM (FREEZE, VERBOSE)\` the oldest tables._"
  local pct
  pct=$(max_field 3)
  if ge "$pct" 70; then
    status CRIT "XID wraparound" "$(first_field) is at ${pct} % of wraparound — VACUUM (FREEZE) it now, remove what blocks autovacuum"
  elif ge "$pct" 40; then
    status WARN "XID wraparound" "$(first_field) is at ${pct} % of wraparound — check that autovacuum can freeze it"
  else
    status OK "XID wraparound" "oldest database at ${pct} %"
  fi
}

# Summary of every check with a status, worst first.
section_summary() {
  local names=(OK WARN CRIT) line level
  echo
  echo "## Summary"
  echo
  echo "Overall: **${names[$worst]}**"
  echo
  echo "| Check | Status | What to do |"
  echo "|---|---|---|"
  for level in CRIT WARN OK; do
    for line in "${summary[@]}"; do
      IFS='|' read -r check st hint <<<"$line"
      [[ $st == "$level" ]] && echo "| ${check} | ${st} | ${hint} |"
    done
  done
  return 0
}

# Sections run first (their statuses feed the summary), then the overview and
# the summary are printed above them.
body="" md=""
trap 'rm -f ${body:+"$body"} ${md:+"$md"}' EXIT

report() {
  body=$(mktemp)
  {
    section_cache_hit
    section_connections
    section_db_sizes
    section_bloat
    section_vacuum
    section_unused_indexes
    section_duplicate_indexes
    section_top_queries
    section_replication
    section_wraparound
  } >"$body"
  section_overview
  section_summary
  cat "$body"
}

render() {
  if [[ $format == html ]]; then
    # not "report | md_to_html": the pipe would run report in a subshell and
    # lose the statuses that make the exit code
    md=$(mktemp)
    report >"$md"
    md_to_html <"$md"
  else
    report
  fi
}

if [[ -n $output ]]; then
  render >"$output"
  echo "report written to $output" >&2
else
  render
fi
exit "$worst"
