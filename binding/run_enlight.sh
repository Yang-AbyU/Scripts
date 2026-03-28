#!/usr/bin/env bash

#SBATCH --mem-per-cpu=20G
#SBATCH --nodes=1
#SBATCH --partition=gpu-s_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00
#SBATCH --job-name=PREP
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
export AMBERHOME="$CONDA_PREFIX"

c_atoms=12

dirs=$(find us_dftb/ -maxdepth 1 -type d -name "US*" | wc -l)
cd us_dftb
for replica in 1 4 5 7 9 12 14 15 16 19; do
	mkdir -p enlighten
	cd enlighten
	cp ../US${replica}/rc3.4/us_dftb_${replica}_qmmm_mini_ori.pdb .
	cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding/add_params .
	atom=${c_atoms}
	pdbfile=us_dftb_${replica}_qmmm_mini_ori.pdb
	center_line=$(awk -v atomnum="$atom" '$4 =="LIG" && $5 =="133" && $3=="C" atomnum {print $6, $7, $8}' "${pdbfile}")
	sed -i "s/__CATOM__/${center_line}/g" add_params
	rm -rf us_dftb_${replica}
	python3 /mnt/nfs/home/nsy49/enlighten2/prep.py us_dftb_${replica} ${pdbfile} LIG 0 add_params
	rm -rf ../us_dftb_${replica}
	mv us_dftb_${replica} ../
	cd ../
	rm -r enlighten
done

