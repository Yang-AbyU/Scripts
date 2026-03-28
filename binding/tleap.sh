#!/usr/bin/env bash
set -euo pipefail

source /nobackup/shared/containers/ambermd.24.25.sh

system=us_dftb
ligand=exo_ext
pose=2
enzyme=abyu_wt

cd "${system}"
for replica in 1 3 4 10 11 12 14 15 19 20; do
    cd "us_dftb_${replica}"

    mkdir -p tleap
    cd tleap

    rm -f cpptraj.in input.pdb tleap.in \
      "${system}_${replica}.top" "${system}_${replica}.rst" "${system}_${replica}.pdb"

    cat > cpptraj.in <<CPPEOF
parm ../${system}_${replica}.top
trajin ../relax/${system}_relax.rst
trajout input.pdb pdb
run
CPPEOF

    container.run cpptraj -i cpptraj.in

    cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding/tleap.in .

    sed -i "s/__SYSTEM__/$system/g" tleap.in
    sed -i "s/__REPLICA__/$replica/g" tleap.in
    sed -i "s/__ENZYME__/$enzyme/g" tleap.in
    sed -i "s/__POSE__/$pose/g" tleap.in
    sed -i "s/__LIG__/$ligand/g" tleap.in

    container.run tleap -f tleap.in

    cd ../..
done
