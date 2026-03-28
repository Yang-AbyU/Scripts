#!/bin/bash
#SBATCH --mem=5G
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:10:00
#SBATCH --job-name=cpptraj_rmsd
#SBATCH --account=rockhpc_jsbs

source /nobackup/shared/containers/ambermd.24.25.sh

ligand=abyssomicin_C

container.run cpptraj << EOF
parm ../../${ligand}.top
trajin md_pro.nc
autoimage
rms first @CA out ${ligand}_Ca_rmsd.dat
run
quit
EOF