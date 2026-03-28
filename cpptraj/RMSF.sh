#!/bin/bash
#SBATCH --mem=5G
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:10:00
#SBATCH --job-name=cpptraj_rmsf
#SBATCH --account=rockhpc_jsbs

source /nobackup/shared/containers/ambermd.24.25.sh

ligand=abyssomicin_C

container.run cpptraj << EOF
parm ../../${ligand}.top
trajin md_pro.nc

autoimage
rms first :1-470@CA
average crdset AVG
run

autoimage
rms ref AVG :1-470@CA
atomicfluct out ${ligand}_rmsf.dat :1-470@CA byres
run
quit
EOF