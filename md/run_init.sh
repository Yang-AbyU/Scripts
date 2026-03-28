#!/bin/bash

#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu-s_paid
#SBATCH --ntasks-per-node=1
#SBATCH --time=06:00:00
#SBATCH --job-name=md_init
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

source /nobackup/shared/containers/ambermd.24.25.sh
export MYDIR="/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/__ENZYME__/__LIG__/pose___POSE__/md"

cd "$MYDIR/dynam_prep" || exit 1
container.run sander -O -i heat_prep.in -o heat.log -p ../../enlighten/__LIG__/tleap/__LIG__.top -c ../../enlighten/__LIG__/relax/__LIG___relax.rst -r heat.rst -x heat.trj
container.run sander -O -i md_prep.in -o md.log -p ../../enlighten/__LIG__/tleap/__LIG__.top -c heat.rst -r md.rst -x md.trj
