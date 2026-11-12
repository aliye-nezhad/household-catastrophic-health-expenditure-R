#!/usr/bin/env bash
# Schema and interview-month key audit for the original 1393 HEIS Access database.
# Only Address and MahMorajeh are streamed to runner-temporary mapping files;
# no household-level rows or identifiers are committed or uploaded.
set -euo pipefail
umask 077

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
command -v mdb-export >/dev/null 2>&1 || { echo "mdbtools is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required for safe CSV field selection." >&2; exit 1; }

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

# Record the database structure without exposing household-level data.
mdb-tables -1 "$DB" | sed '/^[[:space:]]*$/d' | sort \
  > "$OUTPUT_DIR/access_db_tables.txt"
mdb-schema "$DB" mysql > "$OUTPUT_DIR/access_db_schema.sql"
mdb-schema --relations "$DB" mysql > "$OUTPUT_DIR/access_db_relationships.sql"

[[ -s "$OUTPUT_DIR/access_db_tables.txt" && -s "$OUTPUT_DIR/access_db_schema.sql" ]] || {
  echo "Access database schema inventory is empty." >&2
  exit 1
}

# MahMorajeh (interview month) is stored in the household metadata tables,
# while Table 6 medical records carry Address and item-level fields. Stream
# only Address and MahMorajeh into temporary files for the R join audit.
# The other household columns are discarded in the pipe and never written.
for table in R93Data U93Data; do
  mapping_file="$TMP_DIR/${table}_interview_month.csv"
  mdb-export "$DB" "$table" | python3 -c '
import csv, sys
reader = csv.DictReader(sys.stdin)
required = {"Address", "MahMorajeh"}
if not reader.fieldnames or not required.issubset(reader.fieldnames):
    raise SystemExit("Required Address/MahMorajeh fields are missing from " + sys.argv[1])
writer = csv.DictWriter(sys.stdout, fieldnames=["Address", "MahMorajeh"], lineterminator="\n")
writer.writeheader()
for row in reader:
    writer.writerow({key: row.get(key, "") for key in ("Address", "MahMorajeh")})
' "$table" > "$mapping_file"
  [[ -s "$mapping_file" && "$(wc -l < "$mapping_file")" -gt 1 ]] || {
    echo "Interview-month mapping export is empty for $table." >&2
    exit 1
  }
done

{
  echo "Access database schema and interview-month key audit completed."
  echo "Database file: $(basename "$DB")"
  echo "Database bytes: $(stat -c '%s' "$DB")"
  echo "Table count: $(wc -l < "$OUTPUT_DIR/access_db_tables.txt" | tr -d ' ')"
  echo "Schema bytes: $(wc -c < "$OUTPUT_DIR/access_db_schema.sql" | tr -d ' ')"
  echo "R93Data temporary Address/month rows: $(( $(wc -l < "$TMP_DIR/R93Data_interview_month.csv") - 1 ))"
  echo "U93Data temporary Address/month rows: $(( $(wc -l < "$TMP_DIR/U93Data_interview_month.csv") - 1 ))"
  echo "Only Address and MahMorajeh are retained in runner-temporary mapping files."
  echo "No household-level identifiers or records are included in uploaded outputs."
} > "$OUTPUT_DIR/access_db_audit_summary.txt"

echo "ACCESS DATABASE SCHEMA AND INTERVIEW-MONTH AUDIT PASSED."
