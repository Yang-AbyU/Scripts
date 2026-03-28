#!/bin/bash
#
#SBATCH --job-name=docking
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --time=10:00:00
#SBATCH --partition=short,compute,mwvdk
#SBATCH --account=bioc028927

ligand=exo_ext
enzyme=AbyU_WT

/user/work/al23945/VINA/bin/vina --ligand ${ligand}.pdbqt --receptor ${enzyme}_rigid.pdbqt --flex ${enzyme}_flex.pdbqt --out ${ligand}_docked.pdbqt --log ${ligand}_docked.log --config config.txt
