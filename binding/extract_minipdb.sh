#!/bin/bash

source /nobackup/shared/containers/ambermd.24.25.sh
dirs=$(find us_dftb/ -maxdepth 1 -type d -name "US*" | wc -l)

ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding

cd us_dftb
for replica in `seq 1 $dirs`; do
        cd US$replica
        cd rc3.4
        cp $ROOT/cpptraj_template_mini_getpdb.in ./cpptraj.in
        sed -i "s/__SYSTEM__/us_dftb/g" cpptraj.in
        sed -i "s/__REPLICA__/$replica/g" cpptraj.in
        container.run cpptraj -i cpptraj.in
        cd ..
        cd ..
done 
cd ..
