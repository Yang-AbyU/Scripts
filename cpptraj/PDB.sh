#!/bin/bash
#SBATCH --mem=5G
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:10:00
#SBATCH --job-name=cpptraj_pdb
#SBATCH --account=rockhpc_jsbs

source /nobackup/shared/containers/ambermd.24.25.sh

ligand=abyssomicin_C

container.run cpptraj << EOF
parm ../../${ligand}.top
trajin md_pro.nc 1 last 100
autoimage
strip :WAT
trajout ${ligand}_last100.pdb pdb
run
quit
EOF