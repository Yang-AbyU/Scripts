#!/usr/bin/env bash
set -euo pipefail

#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00
#SBATCH --job-name=MMGBSA
#SBATCH --account=rockhpc_jsbs

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
export AMBERHOME="$CONDA_PREFIX"

command -v MMPBSA.py >/dev/null 2>&1 || {
  echo "MMPBSA.py not found in AmberTools25" >&2
  exit 1
}

MMPBSA.py -O -i mmgbsa.i -cp *_1.dry.top -rp receptor.top -lp ligand.top -y *.dry.nc -eo mmgbsa.csv
