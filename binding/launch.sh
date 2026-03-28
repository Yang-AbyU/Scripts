#!/bin/bash

#SBATCH --mem-per-cpu=5G
#SBATCH --cpus-per-task=1
#SBATCH --nodes=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:30:00
#SBATCH --job-name=MIN___REPLICA__
#SBATCH --account=rockhpc_jsbs

source /nobackup/shared/containers/ambermd.24.25.sh

SYSTEM=__SYSTEM__ 
REPLICA=__REPLICA__ 

BASENAME=${SYSTEM}_${REPLICA}

container.run sander -O -i qmmm_minimize_h_all.in -p ../../*.top -c md2ps.rst -r minimize_h_all.rst -o out -ref md2ps.rst

container.run sander -O -i qmmm_minimize_h_in_sphere.in -p ../../*.top -c minimize_h_all.rst -r minimize_h_in_sphere.rst -o out -ref minimize_h_all.rst

NAME=${BASENAME}_qmmm_mini
container.run sander -O -i qmmm_minimize_all_in_sphere.in -p ../../*.top -c minimize_h_in_sphere.rst -r $NAME.rst -o out -ref minimize_h_in_sphere.rst

