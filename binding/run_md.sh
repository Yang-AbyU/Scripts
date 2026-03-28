#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
ROOT="$shared_binding_root"
STAGE_DEPENDENCY_JOBIDS="${STAGE_DEPENDENCY_JOBIDS:-}"
jobids=()

cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    if [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.nc" ]; then
        echo "Skipping replica ${replica}; MD output already present" >&2
        continue
    fi

    rm -rf "MD_MMGBSA_${replica}"
    mkdir "MD_MMGBSA_${replica}"
    cd "MD_MMGBSA_${replica}"
    cp "$ROOT/launch_md.sh" launch.sh
    cp "$ROOT/heat.i" ./
    cp "$ROOT/100ps.i" ./
    cp "$ROOT/dynam.i" ./
    sed -i "s/__SYSTEM__/$system/g" launch.sh
    sed -i "s/__REPLICA__/$replica/g" launch.sh
    sed -i "s/__ENZYME__/$enzyme/g" launch.sh
    sed -i "s/__POSE__/$pose/g" launch.sh
    sed -i "s%__LIG__%$ligand%g" launch.sh
    sed -i "s/__BELLY__/$belly/g" heat.i
    sed -i "s/__BELLY__/$belly/g" dynam.i
    sed -i "s/__BELLY__/$belly/g" 100ps.i
    chmod +x launch.sh

    if [ -n "$STAGE_DEPENDENCY_JOBIDS" ]; then
        jobid=$(sbatch --parsable --dependency=afterok:${STAGE_DEPENDENCY_JOBIDS} launch.sh)
    else
        jobid=$(sbatch --parsable launch.sh)
    fi
    echo "Submitted MD replica ${replica} as job ${jobid}" >&2
    jobids+=("$jobid")
    cd "$project_root/$system"
done

if [ ${#jobids[@]} -gt 0 ]; then
    (IFS=:; printf '%s
' "${jobids[*]}")
fi
