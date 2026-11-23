#!/usr/bin/env bash
# tests/check-report.sh - run pg_health.sh on the database built by tests/seed.sh
# and check that every seeded problem is reported with the right status, in
# Markdown and in HTML.
#
# Usage: tests/check-report.sh [DBNAME]   (default: pg_health_demo)
set -euo pipefail
cd "$(dirname "$0")/.."

demo=${1:-pg_health_demo}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
fails=0

check() {  # check <description> <grep -E pattern> <file>
  if grep -Eq -- "$2" "$3"; then
    echo "ok   - $1"
  else
    echo "FAIL - $1   (pattern: $2)"
    fails=$((fails + 1))
  fi
}
check_not() {  # check_not <description> <grep -E pattern> <file>
  if grep -Eq -- "$2" "$3"; then
    echo "FAIL - $1   (unexpected: $2)"
    fails=$((fails + 1))
  else
    echo "ok   - $1"
  fi
}

set +e
./pg_health.sh -d "$demo" -o "$out/report.md"; rc_md=$?
./pg_health.sh -d "$demo" -o "$out/report.html"; rc_html=$?
set -e

md=$out/report.md
html=$out/report.html

echo "# exit codes"
for run in "Markdown:$rc_md" "HTML:$rc_html"; do
  if [[ ${run#*:} -eq 1 ]]; then
    echo "ok   - ${run%%:*} run exits 1 (WARN)"
  else
    echo "FAIL - ${run%%:*} run exits ${run#*:}, expected 1"
    fails=$((fails + 1))
  fi
done

echo "# summary"
check "overall WARN"                 '^Overall: \*\*WARN\*\*$' "$md"
check "summary lists bloat as WARN"  '^\| Table bloat \| WARN \| up to (8|9)[0-9]\.[0-9] % bloat' "$md"
check "summary lists vacuum as WARN" '^\| VACUUM / ANALYZE \| WARN \|' "$md"
check "summary lists unused indexes" '^\| Unused indexes \| WARN \| [0-9]+ index\(es\) never scanned' "$md"
check "summary lists duplicates"     '^\| Duplicate indexes \| WARN \| 1 set\(s\) of identical indexes, first on table orders' "$md"
check "summary lists the slot"       '^\| Replication \| WARN \| 1 inactive replication slot' "$md"
check "wraparound is OK"             '^\| XID wraparound \| OK \|' "$md"
check "connections are OK"           '^\| Connections \| OK \|' "$md"

echo "# sections"
check "bloated table, 80-99 % bloat" '^\| public\.bloated \| [0-9]+ MB \| [0-9]+ MB \| (8|9)[0-9]\.[0-9] \|$' "$md"
check "table needing VACUUM+ANALYZE" '^\| public\.dead \| VACUUM \+ ANALYZE \| [0-9]+ \| 5000 \| ' "$md"
check "unused index with its size"   '^\| public\.orders_note_idx \| orders \| [0-9]+ kB \| 0 \|$' "$md"
check_not "primary key never listed as unused" '^\| public\.orders_pkey \|' "$md"
check "duplicate pair with waste"    '^\| orders \| orders_customer_idx, orders_customer_idx2 \| [0-9]+ kB \|$' "$md"
check "inactive slot with WAL"       '^\| pg_health_demo_slot \| physical \| no \| [0-9]+ (bytes|kB|MB) \|$' "$md"
check "top queries: how to enable"   'pg_stat_statements is not (installed|loaded)|^## Top queries' "$md"
check "every status line has a hint" '^\*\*Status: (OK|WARN|CRIT)\*\* — .+' "$md"

echo "# html"
check "html page"                    '^<!doctype html>$' "$html"
check "WARN badge in the summary"    '<td><span class="st WARN">WARN</span></td>' "$html"
check "bloat table header"           '<th>Table</th><th>Size</th><th>Estimated bloat</th><th>Bloat %</th>' "$html"
check_not "no raw Markdown left"     '^\||\*\*|^#' "$html"

echo
if (( fails )); then
  echo "$fails check(s) failed. Report:"
  cat "$md"
  exit 1
fi
echo "all checks passed"
