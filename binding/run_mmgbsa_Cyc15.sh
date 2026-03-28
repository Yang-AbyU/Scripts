#!/usr/bin/env bash
set -euo pipefail

enzyme=abyu_wt
ligand=endo
pose=endo
system=us_dftb

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25

ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/${enzyme}/${ligand}/pose_${pose}
SCRIPT_ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding

dirs=$(find "${system}/" -maxdepth 1 -type d -name "US*" | wc -l)

cd "${system}" || exit 1

for replica in $(seq 1 "$dirs"); do
    cd "MD_MMGBSA_${replica}" || exit 1

    rm -f "${system}_${replica}.dry.top" receptor.top ligand.top "${system}_${replica}_100ps.dry.nc"

    ante-MMPBSA.py \
        -p "${ROOT}/${system}/${system}_${replica}/tleap/${system}_${replica}.top" \
        -c "${system}_${replica}.dry.top" \
        -s ":WAT" \
        -r receptor.top \
        -l ligand.top \
        -n ":LIG"

    cp "${SCRIPT_ROOT}/cpptraj_strip_Cyc15.i" ./

    sed -i "s#__SYSTEM__#${system}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__REPLICA__#${replica}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__ENZYME__#${enzyme}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__LIG__#${ligand}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__POSE__#${pose}#g" cpptraj_strip_Cyc15.i
    sed -i "s#/user/work/gp15776#${ROOT%/pose_${pose}}#g" cpptraj_strip_Cyc15.i

    cpptraj -i cpptraj_strip_Cyc15.i

    cd .. || exit 1
done

cd .. || exit 1
