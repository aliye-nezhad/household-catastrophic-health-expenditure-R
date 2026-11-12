#!/usr/bin/env bash
# Schema-only inventory of the original 1393 HEIS Access database.
# No household-level records are exported or written to the repository.
set -euo pipefail

ARCHIVE="data/raw/93.rar"
OUTPUT_DIR="outputs/diagnostics"
TMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/heis-93-mdb"

[[ -s "$ARCHIVE" ]] || { echo "Missing archive: $ARCHIVE" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

if command -v 7zz >/dev/null 2>&1; then
  SEVEN_ZIP="$(command -v 7zz)"
elif command -v 7z >/dev/null 2>&1; then
  SEVEN_ZIP="$(command -v 7z)"
else
  echo "7-Zip executable not found." >&2
  exit 1
fi

command -v mdb-tables >/dev/null 2>&1 || { echo "mdbtools is required." >&2; exit 1; }
command -v mdb-schema >/dev/null 2>&1 || { echo "mdbtools is required." >&2; exit 1; }

"$SEVEN_ZIP" x "$ARCHIVE" "-o$TMP_DIR" -y >/dev/null
mapfile -d '' MDB_FILES < <(find "$TMP_DIR" -type f -iname '*.mdb' -print0)
[[ "${#MDB_FILES[@]}" -eq 1 ]] || {
  echo "Expected exactly one MDB file; found ${#MDB_FILES[@]}." >&2
  exit 1
}
DB="${MDB_FILES[0]}"

printf 'Archive: %s\nDatabase filename: %s\nDatabase bytes: %s\n' \
  "$ARCHIVE" "$(basename "$DB")" "$(stat -c '%s' "$DB")" \
  > "$OUTPUT_DIR/access_db_inventory.txt"

# Schema-only commands. Do not use mdb-export or query data rows here.
mdb-tables -1 "$DB" | sed '/^[[:space:]]*$/d' | sort \
  > "$OUTPUT_DIR/access_db_tables.txt"
mdb-schema "$DB" mysql > "$OUTPUT_DIR/access_db_schema.sql"
mdb-schema --relations "$DB" mysql > "$OUTPUT_DIR/access_db_relationships.sql"

[[ -s "$OUTPUT_DIR/access_db_tables.txt" && -s "$OUTPUT_DIR/access_db_schema.sql" ]] || {
  echo "Access database schema inventory is empty." >&2
  exit 1
}

{
  echo "Schema-only Access database audit completed."
  echo "Database file: $(basename "$DB")"
  echo "Database bytes: $(stat -c '%s' "$DB")"
  echo "Table count: $(wc -l < "$OUTPUT_DIR/access_db_tables.txt" | tr -d ' ')"
  echo "Schema bytes: $(wc -c < "$OUTPUT_DIR/access_db_schema.sql" | tr -d ' ')"
  echo "No household-level records were exported."
} > "$OUTPUT_DIR/access_db_audit_summary.txt"

echo "ACCESS DATABASE SCHEMA AUDIT PASSED."
