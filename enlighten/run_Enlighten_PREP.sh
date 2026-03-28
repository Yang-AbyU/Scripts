#!/usr/bin/env bash

#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu-s_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=1-00:00:00
#SBATCH --job-name=PREP_AbyU_WT_ext_endo
#SBATCH --account=rockhpc_jsbs

#source ~/pmemd24/amber.sh
source /nobackup/shared/containers/ambermd.24.25.sh
export AMBERHOME=/mnt/nfs/home/nsy49/miniforge3/envs/AmberTools25
export PATH="$AMBERHOME/bin:$PATH"

ligand=endo
poses=(endo)
c_atoms=(12)
enzyme=abyu_wt

for i in "${!poses[@]}"; do
	mkdir -p pose_${poses[$i]}
	cd pose_${poses[$i]}
	mkdir -p enlighten
	cd enlighten
	cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/enlighten/add_params .
	cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/${ligand}/${ligand}_docked_model${poses[$i]}.pdb .
	atom="${c_atoms[$i]}"
	pdbfile=${ligand}_docked_model${poses[$i]}.pdb
	center_line=$(awk -v atomnum="$atom" '$1=="HETATM" && $4=="LIG" && $3=="C"atomnum && $5=="L" {print $7, $8, $9}' "${pdbfile}")
	sed -i "s/__CATOM__/${center_line}/g" add_params
	python3 /mnt/nfs/home/nsy49/enlighten2/prep.py ${ligand} ${ligand}_docked_model${poses[$i]}.pdb LIG 0 /user/work/gp15776/${enzyme}/${ligand}/pose_${poses[$i]}/enlighten/add_params
	cd ../../
done

