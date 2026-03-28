#!/usr/bin/env bash

#SBATCH --job-name=wham
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --mem=10G
#SBATCH --partition=gpu-s_free
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
command -v wham

SCRIPT_ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/us
poses=(2)

for i in "${!poses[@]}"; do
	pose="${poses[$i]}"
	cd "pose_${pose}/us_dftb" || exit 1
	cp "$SCRIPT_ROOT/wham.sh" .
	chmod u+x wham.sh
	cp "$SCRIPT_ROOT/meta_all.dat" .
	for dir in US*/; do
		cp "$SCRIPT_ROOT/meta.dat" "$dir"
	done
	chmod u+r meta_all.dat
	chmod u+r US*/meta.dat
	./wham.sh
	wham P 1.275 3.525 45 0.000000001 300 0 meta_all.dat mega_wham_2ps.dat 0 1 > mega_wham_2ps.log
	cd ../.. || exit 1
done
