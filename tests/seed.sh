#!/usr/bin/env bash
# tests/seed.sh - build a demo database with one example of every problem the
# report looks for. Use it on a TEST server only (it creates a database and a
# replication slot).
#
# Usage: tests/seed.sh [DBNAME]        (default: pg_health_demo)
# Connection: the usual libpq variables (PGHOST, PGPORT, PGUSER, PGPASSWORD);
# needs a superuser (or CREATEDB + REPLICATION).
set -euo pipefail

demo=${1:-pg_health_demo}
[[ $demo =~ ^[a-z_][a-z0-9_]*$ ]] || { echo "invalid database name: $demo" >&2; exit 3; }

# One psql session per call: statistics counters are flushed when a session ends,
# so each step sees the counters of the previous ones.
sql() { psql -X -v ON_ERROR_STOP=1 -d "$demo" -qc "$1"; }

echo "creating database $demo"
psql -X -v ON_ERROR_STOP=1 -d postgres -qc "drop database if exists $demo"
psql -X -v ON_ERROR_STOP=1 -d postgres -qc "create database $demo"

echo "table bloat: delete 90 % of the rows over every page, then VACUUM (pages stay)"
sql "create table bloated (id int, pad text) with (autovacuum_enabled = off);
     insert into bloated select g, repeat('x', 100) from generate_series(1, 100000) g;"
sql "delete from bloated where id % 10 <> 0"
sql "vacuum analyze bloated"

echo "VACUUM / ANALYZE: dead rows and changes since the last ANALYZE, autovacuum off"
sql "create table dead (id int) with (autovacuum_enabled = off);
     insert into dead select generate_series(1, 10000);"
sql "analyze dead"
sql "delete from dead where id <= 5000"

echo "indexes: one never used, two identical"
sql "create table orders (id int primary key, customer int, note text);
     insert into orders select g, g % 100, 'n' from generate_series(1, 20000) g;
     create index orders_customer_idx on orders (customer);
     create index orders_customer_idx2 on orders (customer);
     create index orders_note_idx on orders (note);
     analyze orders;"
sql "select count(*) from orders where id = 42"   # scans the primary key only

echo "replication: an inactive physical slot that holds WAL"
psql -X -v ON_ERROR_STOP=1 -d "$demo" -qAt >/dev/null <<'SQL'
select pg_drop_replication_slot(slot_name) from pg_replication_slots where slot_name = 'pg_health_demo_slot';
select pg_create_physical_replication_slot('pg_health_demo_slot', true);
SQL

echo "done: run  ./pg_health.sh -d $demo  (expect exit code 1, overall WARN)"
