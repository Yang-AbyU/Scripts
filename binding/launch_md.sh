#!/bin/bash

#SBATCH --mem-per-cpu=10G
#SBATCH --nodes=1
#SBATCH --partition=default_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=00:40:00
#SBATCH --job-name=MD_EB___REPLICA__
#SBATCH --account=rockhpc_jsbs

source /nobackup/shared/containers/ambermd.24.25.sh

SYSTEM=__SYSTEM__
REPLICA=__REPLICA__
BASENAME=${SYSTEM}_${REPLICA}

ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/Binding_energy_scripts
PARM=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/__ENZYME__/__LIG__/pose___POSE__/$SYSTEM/$BASENAME/tleap/${BASENAME}.top
RST=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/__ENZYME__/__LIG__/pose___POSE__/$SYSTEM/$BASENAME/relax/us_dftb_relax.rst

NAME=${BASENAME}_heat
container.run sander -O -i heat.i -o $NAME.out -p $PARM -c $RST -r $NAME.ncrst -x $NAME.nc

NAME=${BASENAME}_dynam
container.run sander -O -i dynam.i -o $NAME.out -p $PARM -c ${BASENAME}_heat.ncrst -r $NAME.ncrst -x $NAME.nc

NAME=${BASENAME}_100ps
container.run sander -O -i 100ps.i -o $NAME.out -p $PARM -c ${BASENAME}_dynam.ncrst -r $NAME.ncrst -x $NAME.nc
