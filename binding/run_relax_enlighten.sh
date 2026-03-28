#!/usr/bin/env bash
#SBATCH --job-name=submit_relax_17
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --mem=1G
#SBATCH --partition=default_paid
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

SCRIPT_DIR="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
cd "$SCRIPT_DIR" || exit 1

system=us_dftb
enzyme=abyu_y76f
ligand=ext_exo
pose=2
belly=:133@C12
ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding

cd "${system}" || exit 1

for replica in $(seq 1 "$dirs"); do
    cd "${system}_${replica}" || exit 1

    rm -rf relax
    mkdir -p relax
    cd relax || exit 1

    cp "$ROOT/launch_relax_template.sh" launch.sh
    cp "$ROOT/annealing_with_restraints.in" ./
    cp "$ROOT/annealing_without_restraints.in" ./
    cp "$ROOT/minimize_h_all.in" ./
    cp "$ROOT/minimize_all_in_sphere.in" ./
    cp "$ROOT/minimize_h_in_sphere.in" ./

    sed -i "s/__SYSTEM__/$system/g" launch.sh
    sed -i "s/__REPLICA__/$replica/g" launch.sh
    sed -i "s/__ENZYME__/$enzyme/g" launch.sh
    sed -i "s%__LIG__%$ligand%g" launch.sh
    sed -i "s/__POSE__/$pose/g" launch.sh

    sed -i "s/__BELLY__/$belly/g" annealing_with_restraints.in
    sed -i "s/__BELLY__/$belly/g" annealing_without_restraints.in
    sed -i "s/__BELLY__/$belly/g" minimize_h_in_sphere.in
    sed -i "s/__BELLY__/$belly/g" minimize_all_in_sphere.in

    chmod u+x launch.sh
    sbatch launch.sh

    cd .. || exit 1
    cd .. || exit 1
done
