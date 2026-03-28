#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Run this script from either a pose directory containing us_dftb/
# or directly from a us_dftb directory.
# It combines all qmmm_mini PDBs into one multi-model PDB for PyMOL.

out="${1:-all_qmmm_mini_models.pdb}"

if [ -d "us_dftb" ]; then
  base="us_dftb"
elif [ -d "US1" ] || compgen -G 'US*/rc3.4/us_dftb_*_qmmm_mini_ori.pdb' > /dev/null; then
  base="."
else
  echo "Could not find us_dftb/ or US*/rc3.4/ under: $(pwd)" >&2
  echo "Run this script from a pose directory or from inside us_dftb." >&2
  exit 1
fi

pattern="$base/US*/rc3.4/us_dftb_*_qmmm_mini_ori.pdb"
files=( $pattern )

if [ ${#files[@]} -eq 0 ]; then
  echo "No files found matching: $pattern" >&2
  exit 1
fi

rm -f "$out"

model=1
for f in "${files[@]}"; do
  printf 'MODEL     %d\n' "$model" >> "$out"
  awk '
    /^(ATOM|HETATM|TER)/ { print; next }
    /^END$/ { next }
  ' "$f" >> "$out"
  printf 'ENDMDL\n' >> "$out"
  model=$((model + 1))
done

echo "Wrote $out with $((model - 1)) models from $base/."
