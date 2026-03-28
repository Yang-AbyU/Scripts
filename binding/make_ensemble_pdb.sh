#!/usr/bin/env bash
set -euo pipefail

# Run this script from inside a us_dftb directory.
# Example:
#   cd /.../pose_endo/us_dftb
#   ./make_ensemble_pdb.sh endo.top ensamble.pdb
#   The script will submit itself through Slurm automatically.

TOPFILE="${1:-}"
OUTFILE="${2:-ensamble.pdb}"
script_path="$(readlink -f "${BASH_SOURCE[0]}")"

if [ -z "${SLURM_JOB_ID:-}" ]; then
  wrapper_dir="${PWD}/.make_ensemble_pdb_slurm"
  mkdir -p "$wrapper_dir"
  wrapper="$wrapper_dir/submit_make_ensemble_pdb.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=ENS_PDB
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --mem=8G
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs
#SBATCH --output=${wrapper_dir}/make_ensemble_pdb-%j.out
set -euo pipefail
cd "${PWD}"
bash "${script_path}" "${TOPFILE}" "${OUTFILE}"
EOF
  chmod 755 "$wrapper"
  echo "Submitting make_ensemble_pdb through Slurm..."
  sbatch "$wrapper"
  exit 0
fi

if [ -z "$TOPFILE" ]; then
  echo "Usage: $0 <topfile> [outfile]" >&2
  exit 1
fi

if [ ! -f "$TOPFILE" ]; then
  echo "Topology file not found: $TOPFILE" >&2
  echo "Run this script from inside a us_dftb directory and pass a local top file such as endo.top" >&2
  exit 1
fi

shopt -s nullglob
us_dirs=(US*)
shopt -u nullglob

if [ ${#us_dirs[@]} -eq 0 ]; then
  echo "No US* directories found in $(pwd)" >&2
  exit 1
fi

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
command -v cpptraj >/dev/null 2>&1 || {
  echo "cpptraj not found in AmberTools25" >&2
  exit 1
}

DISTANCE_COMMANDS=()

rc_windows=(
  rc1.3 rc1.4 rc1.5 rc1.6 rc1.7 rc1.8 rc1.9
  rc2.0 rc2.1 rc2.2 rc2.3 rc2.4 rc2.5 rc2.6 rc2.7 rc2.8 rc2.9
  rc3.0 rc3.1 rc3.2 rc3.3 rc3.4 rc3.5 rc3.6 rc3.7 rc3.8
)

echo "Starting ensemble build in $(pwd)"
echo "Topology: $TOPFILE"
echo "Output PDB: $OUTFILE"
rm -f "$OUTFILE" cpptraj_ensemble.in

{
  printf 'parm %s\n' "$TOPFILE"

  for us_dir in "${us_dirs[@]}"; do
    if [ ! -d "$us_dir" ]; then
      continue
    fi

    for rc in "${rc_windows[@]}"; do
      traj="$us_dir/$rc/md2ps.nc"
      if [ -f "$traj" ]; then
        printf 'trajin %s lastframe\n' "$traj"
      else
        echo "Skipping missing trajectory: $traj" >&2
      fi
    done
  done

  printf 'trajout %s pdb\n' "$OUTFILE"
  printf 'go\n'
} > cpptraj_ensemble.in

echo "Generated cpptraj_ensemble.in"
echo "Launching cpptraj..."
cpptraj -i cpptraj_ensemble.in
echo "cpptraj finished"

echo "Wrote $OUTFILE"
