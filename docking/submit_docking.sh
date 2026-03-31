#!/bin/bash
#
#SBATCH --job-name=docking
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=10:00:00
#SBATCH --partition=gpu-s_free
#SBATCH --account=rockhpc_jsbs

module load Boost/1.75.0-GCC-12.3.0

ligand=exo_ext
enzyme=AbyU_Y76F

/mnt/nfs/home/nsy49/AutoDock-Vina/build/linux/release/vina --ligand ${ligand}.pdbqt --receptor ${enzyme}_rigid.pdbqt --flex ${enzyme}_flex.pdbqt --out ${ligand}_docked.pdbqt --config config.txt \
> ${ligand}_docked.log 2>&1