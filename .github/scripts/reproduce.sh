#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 ]]; then
  printf 'Usage: bash %s [output-parent-directory]\n' "${BASH_SOURCE[0]}" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
cd -- "$repo_root"

seven_zip="$(command -v 7zz || command -v 7z)" || {
  echo "7-Zip is required. Run this project with pixi run --locked reproduce." >&2
  exit 1
}
sha256sum --strict --check data/raw.sha256

# Use a fresh directory so each run has its own results.
umask 077
output_parent="${1:-reproduced}"
mkdir -p -- "$output_parent"
output_parent="$(cd -- "$output_parent" && pwd -P)"
work="$(mktemp -d "$output_parent/.work-XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT
run_dir="$output_parent/run-${work##*.work-}"

mkdir -p "$work/data/processed" "$work/outputs/diagnostics" "$work/tmp"
ln -s "$repo_root/data/raw" "$work/data/raw"
ln -s "$repo_root/code" "$work/code"
{
  cat data/raw.sha256
  sha256sum pixi.lock
} > "$work/outputs/diagnostics/input_sha256.txt"

# Use the R libraries from Pixi and a fixed locale.
unset R_LIBS R_LIBS_SITE
export R_LIBS_USER="$work/user-library"
export TMPDIR="$work/tmp"
export TZ=UTC LC_ALL=C.UTF-8 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1

(
  cd -- "$work"
  for area in R93 U93; do
    "$seven_zip" e "data/raw/$area.rar" "$area.xls" -odata/processed -y >/dev/null
    test -s "data/processed/$area.xls"
  done
  "$seven_zip" l data/raw/93.rar > outputs/diagnostics/93_archive_inventory.txt
  bash "$script_dir/audit_access_database.sh"
  Rscript --vanilla code/Health_Expenditure_Analysis.R
  Rscript --vanilla code/validate_reproduction.R
)

mv -T -- "$work/outputs" "$run_dir"
echo "Results: $run_dir"
