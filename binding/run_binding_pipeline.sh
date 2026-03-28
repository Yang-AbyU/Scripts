#!/usr/bin/env bash
set -euo pipefail

# Binding pipeline driver
#
# Usage:
#   ./run_binding_pipeline.sh
#   ./run_binding_pipeline.sh resume
#   ./run_binding_pipeline.sh overwrite
#   PIPELINE_MODE=resume ./run_binding_pipeline.sh
#   PIPELINE_MODE=overwrite FORCE_STAGES="run_md.sh run_mmgbsa_Cyc15.sh" ./run_binding_pipeline.sh
#
# What this script does before running stages:
#   1. Copies shared binding assets into binding_snapshot/
#   2. Generates local config-driven stage scripts in the project directory
#      from project_config.sh
#   3. Runs the pipeline in resume or overwrite mode
#
# Modes:
#   resume
#     - Default mode.
#     - If a stage's expected outputs already exist, that stage is skipped.
#     - If matching Slurm jobs are already running or pending, the pipeline waits
#       for them instead of resubmitting.
#
#   overwrite
#     - Reruns selected stages from scratch.
#     - If FORCE_STAGES is not set, all stages are cleaned and rerun.
#     - If FORCE_STAGES is set, only those named stages are cleaned and rerun.
#
# Useful examples:
#   1. Resume from wherever the previous run stopped:
#      ./run_binding_pipeline.sh
#
#   2. Rerun only MD and MMGBSA preparation:
#      PIPELINE_MODE=overwrite FORCE_STAGES="run_md.sh run_mmgbsa_Cyc15.sh" ./run_binding_pipeline.sh
#
#   3. Regenerate relax, tleap, and MD from scratch:
#      PIPELINE_MODE=overwrite FORCE_STAGES="run_relax_enlighten.sh tleap.sh run_md.sh" ./run_binding_pipeline.sh

SCRIPT_SOURCE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -n "${SLURM_SUBMIT_DIR:-}" ] && [ -f "${SLURM_SUBMIT_DIR}/project_config.sh" ]; then
    SCRIPT_DIR="$SLURM_SUBMIT_DIR"
else
    SCRIPT_DIR="$SCRIPT_SOURCE_DIR"
fi
source "$SCRIPT_DIR/project_config.sh"

cd "$project_root"
state_dir="$project_root/.pipeline_state"
mkdir -p "$state_dir"

PIPELINE_MODE=${PIPELINE_MODE:-${1:-resume}}
FORCE_STAGES=${FORCE_STAGES:-}

case "$PIPELINE_MODE" in
    resume|overwrite)
        ;;
    *)
        echo "Unsupported PIPELINE_MODE: $PIPELINE_MODE" >&2
        echo "Use 'resume' or 'overwrite'." >&2
        exit 1
        ;;
esac

sync_shared_assets() {
    local snapshot_dir="$project_root/binding_snapshot"
    mkdir -p "$snapshot_dir"

    local files=(
        launch.sh
        launch_relax_template.sh
        launch_md.sh
        qmmm_minimize_all_in_sphere.in
        qmmm_minimize_h_all.in
        qmmm_minimize_h_in_sphere.in
        cpptraj_template_mini_getpdb.in
        add_params
        annealing_with_restraints.in
        annealing_without_restraints.in
        minimize_h_all.in
        minimize_all_in_sphere.in
        minimize_h_in_sphere.in
        tleap.in
        heat.i
        dynam.i
        100ps.i
        cpptraj_strip_Cyc15.i
        mmgbsa.i
        submit_MMGBSA_Cyc15.sh
        means.py
        run_min.sh
        extract_minipdb.sh
        run_enlight.sh
        run_relax_enlighten.sh
        tleap.sh
        run_md.sh
        run_mmgbsa_Cyc15.sh
        run_eb.sh
        project_config.sh
    )

    for file in "${files[@]}"; do
        if [ -f "$shared_binding_root/$file" ]; then
            cp "$shared_binding_root/$file" "$snapshot_dir/$file"
        fi
    done

    echo "Synced shared binding assets into $snapshot_dir"
}

materialize_local_stage_scripts() {
    local out

    out="$project_root/run_min.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
ROOT="$shared_binding_root"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "US${replica}/rc3.4"
    cp "$ROOT/qmmm_minimize_all_in_sphere.in" ./
    cp "$ROOT/qmmm_minimize_h_all.in" ./
    cp "$ROOT/qmmm_minimize_h_in_sphere.in" ./
    cp "$ROOT/launch.sh" launch.sh
    sed -i "s/__SYSTEM__/$system/g" launch.sh
    sed -i "s/__REPLICA__/$replica/g" launch.sh
    sed -i "s/__BELLY__/$belly/g" qmmm_minimize_all_in_sphere.in
    sed -i "s/__BELLY__/$belly/g" qmmm_minimize_h_in_sphere.in
    chmod +x launch.sh
    bash launch.sh
    cd "$project_root/$system"
done
EOS
    chmod 755 "$out"

    out="$project_root/extract_minipdb.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
source "$amber_container_setup"
ROOT="$shared_binding_root"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "US${replica}/rc3.4"
    cp "$ROOT/cpptraj_template_mini_getpdb.in" ./cpptraj.in
    sed -i "s/__SYSTEM__/$system/g" cpptraj.in
    sed -i "s/__REPLICA__/$replica/g" cpptraj.in
    container.run cpptraj -i cpptraj.in
    cd "$project_root/$system"
done
EOS
    chmod 755 "$out"

    out="$project_root/run_enlight.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
source "$conda_setup"
conda activate "$conda_env"
export AMBERHOME="$CONDA_PREFIX"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    mkdir -p enlighten
    cd enlighten
    cp "../US${replica}/rc3.4/${system}_${replica}_qmmm_mini_ori.pdb" ./
    cp "$shared_binding_root/add_params" ./
    pdbfile="${system}_${replica}_qmmm_mini_ori.pdb"
    center_line=$(awk -v atomnum="$c_atoms" -v resid="$ligand_residue_id" -v resname="$ligand_resname" '$4 == resname && $5 == resid && $3=="C" atomnum {print $6, $7, $8}' "$pdbfile")
    sed -i "s/__CATOM__/${center_line}/g" add_params
    rm -rf "${system}_${replica}"
    python3 /mnt/nfs/home/nsy49/enlighten2/prep.py "${system}_${replica}" "$pdbfile" "$ligand_resname" 0 add_params
    rm -rf "../${system}_${replica}"
    mv "${system}_${replica}" ../
    cd ..
    rm -rf enlighten
done

ref_replica="${shared_ligand_param_replica:-${replicas[0]}}"
ref_antechamber_dir="$project_root/$system/${system}_${ref_replica}/antechamber"
if [ ! -f "$ref_antechamber_dir/LIG.prepc" ] || [ ! -f "$ref_antechamber_dir/LIG.frcmod" ]; then
    echo "Reference ligand parameter files not found in $ref_antechamber_dir" >&2
    exit 1
fi
for replica in "${replicas[@]}"; do
    [ "$replica" = "$ref_replica" ] && continue
    target_antechamber_dir="$project_root/$system/${system}_${replica}/antechamber"
    cp "$ref_antechamber_dir/LIG.prepc" "$target_antechamber_dir/LIG.prepc"
    cp "$ref_antechamber_dir/LIG.frcmod" "$target_antechamber_dir/LIG.frcmod"
done

echo "Synchronized ligand parameters across replicas from reference replica $ref_replica"
EOS
    chmod 755 "$out"

    out="$project_root/run_relax_enlighten.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
ROOT="$shared_binding_root"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "${system}_${replica}"
    rm -rf relax
    mkdir -p relax
    cd relax
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
    chmod +x launch.sh
    bash launch.sh
    cd "$project_root/$system"
done
EOS
    chmod 755 "$out"

    out="$project_root/tleap.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
source "$amber_container_setup"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "${system}_${replica}"
    mkdir -p tleap
    cd tleap
    rm -f cpptraj.in input.pdb tleap.in "${system}_${replica}.top" "${system}_${replica}.rst" "${system}_${replica}.pdb"
    cat > cpptraj.in <<CPPEOF
parm ../${system}_${replica}.top
trajin ../relax/${system}_relax.rst
trajout input.pdb pdb
run
CPPEOF
    container.run cpptraj -i cpptraj.in
    cp "$shared_binding_root/tleap.in" ./
    sed -i "s/__SYSTEM__/$system/g" tleap.in
    sed -i "s/__REPLICA__/$replica/g" tleap.in
    sed -i "s/__ENZYME__/$enzyme/g" tleap.in
    sed -i "s/__POSE__/$pose/g" tleap.in
    sed -i "s/__LIG__/$ligand/g" tleap.in
    container.run tleap -f tleap.in
    cd "$project_root/$system"
done
EOS
    chmod 755 "$out"

    out="$project_root/run_md.sh"
    cat > "$out" <<'EOS'
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
EOS
    chmod 755 "$out"

    out="$project_root/run_mmgbsa_Cyc15.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
source "$conda_setup"
conda activate "$conda_env"
ROOT="$project_root"
SCRIPT_ROOT="$shared_binding_root"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "MD_MMGBSA_${replica}"
    rm -f "${system}_${replica}.dry.top" receptor.top ligand.top "${system}_${replica}_100ps.dry.nc"
    ante-MMPBSA.py \
        -p "$ROOT/$system/${system}_${replica}/tleap/${system}_${replica}.top" \
        -c "${system}_${replica}.dry.top" \
        -s ":WAT" \
        -r receptor.top \
        -l ligand.top \
        -n ":LIG"
    cp "$SCRIPT_ROOT/cpptraj_strip_Cyc15.i" ./
    sed -i "s#__SYSTEM__#${system}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__REPLICA__#${replica}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__ENZYME__#${enzyme}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__LIG__#${ligand}#g" cpptraj_strip_Cyc15.i
    sed -i "s#__POSE__#${pose}#g" cpptraj_strip_Cyc15.i
    sed -i "s#/user/work/gp15776#${ROOT%/pose_${pose}}#g" cpptraj_strip_Cyc15.i
    cpptraj -i cpptraj_strip_Cyc15.i
    cd "$project_root/$system"
done
EOS
    chmod 755 "$out"

    out="$project_root/run_eb.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
source "$conda_setup"
conda activate "$conda_env"
export AMBERHOME="$CONDA_PREFIX"
ROOT="$project_root"
cd "$project_root/$system"
for replica in "${replicas[@]}"; do
    cd "${system}_${replica}/tleap"
    cat > tleap_mbondi.in <<TLEAPEOF
source oldff/leaprc.ff14SB
source leaprc.water.tip3p
source leaprc.gaff2
loadamberprep ../antechamber/LIG.prepc
loadamberparams ../antechamber/LIG.frcmod
mol = loadpdb ${system}_${replica}.pdb
set default PBRadii mbondi2
saveamberparm mol ${system}_${replica}_mbondi.top ${system}_${replica}_mbondi.rst
quit
TLEAPEOF
    tleap -f tleap_mbondi.in
    rm -f "${system}_${replica}_mbondi.rst"
    cd "$project_root/$system/MD_MMGBSA_${replica}"
    rm -f "${system}_${replica}_mbondi.dry.top" ligand_mbondi.top receptor_mbondi.top
    ante-MMPBSA.py -p "$ROOT/$system/${system}_${replica}/tleap/${system}_${replica}_mbondi.top" -c "${system}_${replica}_mbondi.dry.top" -s ":WAT" -r receptor_mbondi.top -l ligand_mbondi.top -n ":LIG,FR2"
    cp "$shared_binding_root/cpptraj_strip_Cyc15.i" ./
    sed -i "s/__SYSTEM__/$system/g" cpptraj_strip_Cyc15.i
    sed -i "s/__REPLICA__/$replica/g" cpptraj_strip_Cyc15.i
    sed -i "s/__ENZYME__/$enzyme/g" cpptraj_strip_Cyc15.i
    sed -i "s%__LIG__%$ligand%g" cpptraj_strip_Cyc15.i
    sed -i "s/__POSE__/$pose/g" cpptraj_strip_Cyc15.i
    cpptraj -i cpptraj_strip_Cyc15.i
    cd "$project_root/$system"
done
rm -rf dry_trj_mbondi
mkdir dry_trj_mbondi
cp "$shared_binding_root/mmgbsa.i" dry_trj_mbondi/
for replica in "${replicas[@]}"; do
    cp "MD_MMGBSA_${replica}/${system}_${replica}_mbondi.dry.top" dry_trj_mbondi/
    cp "MD_MMGBSA_${replica}/receptor_mbondi.top" dry_trj_mbondi/
    cp "MD_MMGBSA_${replica}/ligand_mbondi.top" dry_trj_mbondi/
    cp "MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc" dry_trj_mbondi/
done
cat > dry_trj_mbondi/submit.sh <<SUBMITEOF
#!/usr/bin/env bash
#SBATCH --job-name=EB_${ligand}_${pose}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:30:00
#SBATCH --mem-per-cpu=20gb
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs
set -euo pipefail
source "$conda_setup"
conda activate "$conda_env"
export AMBERHOME="$CONDA_PREFIX"
replicas=(${replicas[*]})
work_root="$project_root/$system"
mmgbsa_input="$project_root/$system/dry_trj_mbondi/mmgbsa.i"
csv_file="$project_root/$system/dry_trj_mbondi/per_replica_binding_energy.csv"
summary_file="$project_root/$system/dry_trj_mbondi/binding_energy_summary.csv"
per_replica_results_dir="$project_root/$system/dry_trj_mbondi/per_replica_results"
rm -rf "\$per_replica_results_dir"
mkdir -p "\$per_replica_results_dir"
printf "replica,binding_energy_kcal_mol,sd,sem
" > "\$csv_file"
for replica in "\${replicas[@]}"; do
    workdir="\$work_root/MD_MMGBSA_\$replica"
    cd "\$workdir"
    rm -f FINAL_RESULTS_MMPBSA.dat FINAL_RESULTS_MMPBSA.csv mmpbsa.csv mmpbsa_run.log
    MMPBSA.py -O -i "\$mmgbsa_input"         -cp "${system}_\${replica}_mbondi.dry.top"         -rp receptor_mbondi.top         -lp ligand_mbondi.top         -y "${system}_\${replica}_100ps.dry.nc"         -eo mmpbsa.csv > mmpbsa_run.log 2>&1
    read avg sd sem < <(awk '\$1=="DELTA" && \$2=="TOTAL"{print \$3, \$4, \$5}' FINAL_RESULTS_MMPBSA.dat | tail -n 1)
    if [ -z "\${avg:-}" ]; then
        echo "Failed to parse DELTA TOTAL for replica \$replica" >&2
        exit 1
    fi
    cp FINAL_RESULTS_MMPBSA.dat "\$per_replica_results_dir/FINAL_RESULTS_MMPBSA_replica_\${replica}.dat"
    printf "%s,%s,%s,%s
" "\$replica" "\$avg" "\$sd" "\$sem" >> "\$csv_file"
done
python - "\$csv_file" "\$summary_file" <<'PYCSV'
import csv, math, statistics, sys
csv_file, summary_file = sys.argv[1:3]
vals = []
with open(csv_file, newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        vals.append(float(row['binding_energy_kcal_mol']))
if not vals:
    raise SystemExit('No per-replica binding energies found')
mean = statistics.mean(vals)
sd = statistics.stdev(vals) if len(vals) > 1 else 0.0
se = sd / math.sqrt(len(vals)) if len(vals) > 0 else 0.0
with open(summary_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['n_replicas', 'binding_energy_mean_kcal_mol', 'binding_energy_sd_kcal_mol', 'binding_energy_se_kcal_mol'])
    writer.writerow([len(vals), mean, sd, se])
PYCSV

cd "\$work_root/dry_trj_mbondi"
rm -f FINAL_RESULTS_MMPBSA.dat FINAL_RESULTS_MMPBSA.csv mmpbsa.csv combined_mmpbsa_run.log
set +e
MMPBSA.py -O -i mmgbsa.i     -cp *_1_mbondi.dry.top     -rp receptor_mbondi.top     -lp ligand_mbondi.top     -y *.dry.nc     -eo mmpbsa.csv > combined_mmpbsa_run.log 2>&1
combined_status=\$?
set -e
if [ "\$combined_status" -ne 0 ]; then
    echo "Combined MMPBSA.py failed; synthesizing FINAL_RESULTS_MMPBSA.dat from per-replica results." >&2
    python - "\$csv_file" "\$summary_file" <<'PYFALLBACK'
import csv, sys
csv_file, summary_file = sys.argv[1:3]
rows = []
with open(csv_file, newline='') as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)
if not rows:
    raise SystemExit('No per-replica rows found for fallback FINAL_RESULTS_MMPBSA.dat')
with open(summary_file, newline='') as f:
    reader = csv.DictReader(f)
    summary = next(reader)
mean = float(summary['binding_energy_mean_kcal_mol'])
sd = float(summary['binding_energy_sd_kcal_mol'])
se = float(summary['binding_energy_se_kcal_mol'])
with open('FINAL_RESULTS_MMPBSA.dat', 'w') as out:
    out.write('SYNTHESIZED FROM PER-REPLICA MMPBSA RESULTS\n')
    out.write('Combined topology-based MMPBSA failed; this file reports the mean across per-replica runs.\n\n')
    out.write(f"Using {len(rows)} replicas\n\n")
    out.write('PER-REPLICA DELTA TOTAL (kcal/mol)\n')
    out.write('Replica,DELTA_TOTAL\n')
    for row in rows:
        out.write(f"{row['replica']},{row['binding_energy_kcal_mol']}\n")
    out.write('\nSUMMARY\n')
    out.write('Energy Component            Average              SD(Prop.)         Std. Err. of Mean\n')
    out.write(f"DELTA TOTAL                {mean:16.4f}      {sd:16.4f}      {se:16.4f}\n")
PYFALLBACK
fi
SUBMITEOF
chmod +x dry_trj_mbondi/submit.sh
EOS
    chmod 755 "$out"

    out="$project_root/submit_eb.sh"
    cat > "$out" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/project_config.sh"
workdir="$project_root/$system/dry_trj_mbondi"
if [ ! -f "$workdir/submit.sh" ]; then
    echo "Missing $workdir/submit.sh" >&2
    exit 1
fi
cd "$workdir"
bash submit.sh
EOS
    chmod 755 "$out"

    echo "Materialized local config-driven stage scripts under $project_root"
}

wait_for_jobs() {
    :
}

has_active_jobs() {
    local pattern="$1"
    local count
    local queue_user
    queue_user=${USER:-$(id -un)}
    count=$(squeue -u "$queue_user" -h -o "%j" | grep -E "$pattern" | wc -l || true)
    [ "$count" -gt 0 ]
}

active_job_id_for_pattern() {
    local pattern="$1"
    local queue_user
    queue_user=${USER:-$(id -un)}
    squeue -u "$queue_user" -h -o "%i %j" | awk -v pat="$pattern" '$2 ~ pat {print $1; exit}'
}

active_md_jobids() {
    local queue_user
    local replica
    local jobid
    local ids=()
    queue_user=${USER:-$(id -un)}
    for replica in "${replicas[@]}"; do
        [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.nc" ] && continue
        jobid=$(squeue -u "$queue_user" -h -o "%i %j" | awk -v name="MD_EB_${replica}" '$2 == name {print $1; exit}')
        [ -n "$jobid" ] && ids+=("$jobid")
    done
    if [ ${#ids[@]} -gt 0 ]; then
        (IFS=:; printf '%s
' "${ids[*]}")
    fi
}

submit_md_stage() {
    local dependency_jobids="${1:-}"
    local target
    target=$(resolve_stage_script run_md.sh)
    if [ -n "$dependency_jobids" ]; then
        STAGE_DEPENDENCY_JOBIDS="$dependency_jobids" bash "$target"
    else
        bash "$target"
    fi
}

stage_done_file() {
    local script="$1"
    printf '%s/%s.done\n' "$state_dir" "$script"
}

mark_stage_done() {
    local script="$1"
    touch "$(stage_done_file "$script")"
}

clear_stage_done() {
    local script="$1"
    rm -f "$(stage_done_file "$script")"
}

stage_is_forced() {
    local script="$1"

    if [ "$PIPELINE_MODE" != "overwrite" ]; then
        return 1
    fi

    if [ -z "$FORCE_STAGES" ]; then
        return 0
    fi

    case " $FORCE_STAGES " in
        *" $script "*) return 0 ;;
        *) return 1 ;;
    esac
}

stage_is_complete() {
    local script="$1"
    local replica

    case "$script" in
        run_min.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/US${replica}/rc3.4/${system}_${replica}_qmmm_mini.rst" ] || return 1
            done
            ;;
        extract_minipdb.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/US${replica}/rc3.4/${system}_${replica}_qmmm_mini_ori.pdb" ] || return 1
            done
            ;;
        run_enlight.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/${system}_${replica}/antechamber/LIG.prepc" ] || return 1
                [ -f "$project_root/$system/${system}_${replica}/${system}_${replica}.top" ] || return 1
                [ -f "$project_root/$system/${system}_${replica}/${system}_${replica}.rst" ] || return 1
            done
            ;;
        run_relax_enlighten.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/${system}_${replica}/relax/${system}_relax.rst" ] || return 1
            done
            ;;
        tleap.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/${system}_${replica}/tleap/${system}_${replica}.top" ] || return 1
                [ -f "$project_root/$system/${system}_${replica}/tleap/${system}_${replica}.rst" ] || return 1
            done
            ;;
        run_md.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.nc" ] || return 1
            done
            ;;
        run_mmgbsa_Cyc15.sh)
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}.dry.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/receptor.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/ligand.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc" ] || return 1
            done
            ;;
        run_eb.sh)
            [ -d "$project_root/$system/dry_trj_mbondi" ] || return 1
            [ -f "$project_root/$system/dry_trj_mbondi/mmgbsa.i" ] || return 1
            [ -f "$project_root/$system/dry_trj_mbondi/submit.sh" ] || return 1
            for replica in "${replicas[@]}"; do
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_mbondi.dry.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/receptor_mbondi.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/ligand_mbondi.top" ] || return 1
                [ -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc" ] || return 1
            done
            ;;
        submit_eb.sh)
            [ -f "$project_root/$system/dry_trj_mbondi/per_replica_binding_energy.csv" ] || return 1
            [ -f "$project_root/$system/dry_trj_mbondi/binding_energy_summary.csv" ] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    return 0
}

clean_stage_outputs() {
    local script="$1"
    local replica

    echo "Cleaning outputs for $script"

    case "$script" in
        run_min.sh)
            for replica in "${replicas[@]}"; do
                rm -f "$project_root/$system/US${replica}/rc3.4/${system}_${replica}_qmmm_mini.rst"
            done
            ;;
        extract_minipdb.sh)
            for replica in "${replicas[@]}"; do
                rm -f "$project_root/$system/US${replica}/rc3.4/${system}_${replica}_qmmm_mini_ori.pdb"
            done
            ;;
        run_enlight.sh)
            for replica in "${replicas[@]}"; do
                rm -rf "$project_root/$system/${system}_${replica}"
            done
            ;;
        run_relax_enlighten.sh)
            for replica in "${replicas[@]}"; do
                rm -rf "$project_root/$system/${system}_${replica}/relax"
            done
            ;;
        tleap.sh)
            for replica in "${replicas[@]}"; do
                rm -f "$project_root/$system/${system}_${replica}/tleap/${system}_${replica}.top"
                rm -f "$project_root/$system/${system}_${replica}/tleap/${system}_${replica}.rst"
                rm -f "$project_root/$system/${system}_${replica}/tleap/${system}_${replica}.pdb"
                rm -f "$project_root/$system/${system}_${replica}/tleap/input.pdb"
                rm -f "$project_root/$system/${system}_${replica}/tleap/cpptraj.in"
                rm -f "$project_root/$system/${system}_${replica}/tleap/tleap.in"
            done
            ;;
        run_md.sh)
            for replica in "${replicas[@]}"; do
                rm -rf "$project_root/$system/MD_MMGBSA_${replica}"
            done
            ;;
        run_mmgbsa_Cyc15.sh)
            for replica in "${replicas[@]}"; do
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}.dry.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/receptor.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/ligand.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc"
            done
            ;;
        run_eb.sh)
            rm -rf "$project_root/$system/dry_trj_mbondi"
            for replica in "${replicas[@]}"; do
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_mbondi.dry.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/receptor_mbondi.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/ligand_mbondi.top"
                rm -f "$project_root/$system/MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc"
            done
            ;;
        submit_eb.sh)
            rm -f "$project_root/$system/dry_trj_mbondi/per_replica_binding_energy.csv"
            rm -f "$project_root/$system/dry_trj_mbondi/binding_energy_summary.csv"
            rm -f "$project_root/$system/dry_trj_mbondi/FINAL_RESULTS_MMPBSA.dat"
            rm -f "$project_root/$system/dry_trj_mbondi/FINAL_RESULTS_MMPBSA.csv"
            rm -f "$project_root/$system/dry_trj_mbondi/mmpbsa.csv"
            rm -f "$project_root/$system/dry_trj_mbondi/combined_mmpbsa_run.log"
            ;;
        *)
            echo "No cleanup rule defined for $script" >&2
            ;;
    esac

    clear_stage_done "$script"
}

resolve_stage_script() {
    local script="$1"
    if [ -f "$project_root/$script" ]; then
        printf '%s\n' "$project_root/$script"
    elif [ -f "$shared_binding_root/$script" ]; then
        printf '%s\n' "$shared_binding_root/$script"
    else
        echo "Stage script not found in project or shared binding folder: $script" >&2
        return 1
    fi
}

stage_job_name() {
    local script="$1"
    local base="${script%.sh}"
    base="${base//./_}"
    printf 'PIPE_%s_%s_%s\n' "$base" "$ligand" "$pose"
}

stage_time() {
    case "$1" in
        run_min.sh) echo '03:00:00' ;;
        extract_minipdb.sh) echo '01:00:00' ;;
        run_enlight.sh) echo '04:00:00' ;;
        run_relax_enlighten.sh) echo '08:00:00' ;;
        tleap.sh) echo '02:00:00' ;;
        run_md.sh) echo '08:00:00' ;;
        run_mmgbsa_Cyc15.sh) echo '03:00:00' ;;
        run_eb.sh) echo '04:00:00' ;;
        submit_eb.sh) echo '04:00:00' ;;
        *) echo '04:00:00' ;;
    esac
}

stage_mem() {
    case "$1" in
        run_enlight.sh) echo '12G' ;;
        run_mmgbsa_Cyc15.sh|run_eb.sh|submit_eb.sh) echo '20G' ;;
        *) echo '8G' ;;
    esac
}

submit_stage_job() {
    local script="$1"
    local dependency_jobid="${2:-}"
    local target wrapper job_name time_limit mem_limit sbatch_output jobid
    target=$(resolve_stage_script "$script")
    wrapper="$state_dir/${script%.sh}.slurm.sh"
    job_name=$(stage_job_name "$script")
    time_limit=$(stage_time "$script")
    mem_limit=$(stage_mem "$script")
    sbatch_output="$state_dir/${script%.sh}.slurm-%j.out"

    cat > "$wrapper" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=${job_name}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=${time_limit}
#SBATCH --mem=${mem_limit}
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs
#SBATCH --output=${sbatch_output}
set -euo pipefail
bash "$target"
EOF
    chmod 755 "$wrapper"

    if [ -n "$dependency_jobid" ]; then
        jobid=$(sbatch --parsable --dependency=afterok:${dependency_jobid} "$wrapper")
    else
        jobid=$(sbatch --parsable "$wrapper")
    fi
    printf '%s\n' "$jobid"
}

submit_pipeline_chain() {
    local stages=(run_min.sh extract_minipdb.sh run_enlight.sh run_relax_enlighten.sh tleap.sh run_md.sh run_mmgbsa_Cyc15.sh run_eb.sh submit_eb.sh)
    local script prev_jobid="" current_jobid active_jobid

    for script in "${stages[@]}"; do
        if stage_is_forced "$script"; then
            echo "=== Overwriting $script ==="
            clean_stage_outputs "$script"
        elif stage_is_complete "$script"; then
            echo "=== Skipping $script (outputs already present) ==="
            mark_stage_done "$script"
            continue
        fi

        if [ "$script" = "run_md.sh" ]; then
            active_jobid=$(active_md_jobids)
            if [ -n "$active_jobid" ] && ! stage_is_forced "$script"; then
                echo "=== Reusing existing submitted MD replica jobs for $script as $active_jobid ==="
                prev_jobid="$active_jobid"
                continue
            fi

            current_jobid=$(submit_md_stage "$prev_jobid")
            if [ -n "$current_jobid" ]; then
                echo "Submitted $script replica jobs as $current_jobid"
                prev_jobid="$current_jobid"
            else
                echo "No new MD replica jobs were submitted for $script"
            fi
            continue
        fi

        active_jobid=$(active_job_id_for_pattern "^$(stage_job_name "$script")$")
        if [ -n "$active_jobid" ] && ! stage_is_forced "$script"; then
            echo "=== Reusing existing submitted stage $script as job $active_jobid ==="
            prev_jobid="$active_jobid"
            continue
        fi

        current_jobid=$(submit_stage_job "$script" "$prev_jobid")
        echo "Submitted $script as job $current_jobid"
        prev_jobid="$current_jobid"
    done

    if [ -n "$prev_jobid" ]; then
        echo
        echo "Pipeline submitted through final stage job $prev_jobid"
        echo "Monitor with: sacct -j $prev_jobid --format=JobID,JobName,State,ExitCode"
    else
        echo
        echo "All pipeline stages already appear complete. Nothing new was submitted."
    fi
}

sync_shared_assets
materialize_local_stage_scripts

echo "Pipeline mode: $PIPELINE_MODE"
if [ -n "$FORCE_STAGES" ]; then
    echo "Forced stages: $FORCE_STAGES"
fi

submit_pipeline_chain

exit 0
