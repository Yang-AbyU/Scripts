#!/bin/bash

belly=:136@C1
ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding
system=us_dftb
dirs=$(find us_dftb/ -maxdepth 1 -type d -name "US*" | wc -l)
cd ${system}
for replica in `seq 1 $dirs`; do
        cd US$replica
        cd rc3.4
        cp $ROOT/qmmm_minimize_all_in_sphere.in ./
        cp $ROOT/qmmm_minimize_h_all.in ./
        cp $ROOT/qmmm_minimize_h_in_sphere.in ./
        cp $ROOT/launch.sh launch.sh
        sed -i "s/__SYSTEM__/$system/g" launch.sh
        sed -i "s/__REPLICA__/$replica/g" launch.sh
        sed -i "s/__BELLY__/$belly/g" qmmm_minimize_all_in_sphere.in
        sed -i "s/__BELLY__/$belly/g" qmmm_minimize_h_in_sphere.in
        chmod +x launch.sh
        sbatch launch.sh
        cd ../..
done
cd ..
