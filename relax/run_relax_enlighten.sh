#!/bin/bash

#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu-s_free
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00
#SBATCH --job-name=Relax
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

residue=136
enzyme=abyu
ligand=mk_11
poses=(2 5 7 10)
c_atoms=(12 8 13 21)

ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/relax

for i in "${!poses[@]}"; do
    pose="${poses[$i]}"
    belly=":${residue}@C${c_atoms[$i]}"
    workdir="pose_${pose}/enlighten/${ligand}"

    cd "$workdir" || exit 1

    rm -rf relax
    mkdir -p relax
    cd relax || exit 1

    cp "$ROOT/launch_relax_template.sh" launch.sh
    cp "$ROOT/annealing_with_restraints.in" ./
    cp "$ROOT/annealing_without_restraints.in" ./
    cp "$ROOT/minimize_h_all.in" ./
    cp "$ROOT/minimize_all_in_sphere.in" ./
    cp "$ROOT/minimize_h_in_sphere.in" ./

    sed -i "s/__ENZYME__/$enzyme/g" launch.sh
    sed -i "s%__LIG__%$ligand%g" launch.sh
    sed -i "s/__POSE__/$pose/g" launch.sh
    sed -i "s/__BELLY__/$belly/g" annealing_with_restraints.in
    sed -i "s/__BELLY__/$belly/g" annealing_without_restraints.in
    sed -i "s/__BELLY__/$belly/g" minimize_h_in_sphere.in
    sed -i "s/__BELLY__/$belly/g" minimize_all_in_sphere.in

    chmod +x launch.sh
    sbatch launch.sh

    cd ../../../..
done
