#!/usr/bin/env bash

# Standalone apo-protein / protein-complex AmberTools prep launcher.
#
# What this script does:
# 1. loads the AmberTools environment
# 2. loops over the systems listed in JOB_NAMES / PDB_FILES
# 3. runs prep_apo_enlighten.py for each system
# 4. creates an Enlighten-style output tree under:
#    ${PROJECT_ROOT}/${job_name}/enlighten/${job_name}/
#
# Main outputs produced for each job:
# - pdb4amber_reduce/
# - propka/
# - tleap/
# - ${job_name}.top
# - ${job_name}.rst
#
# How to use:
# 1. Edit PROJECT_ROOT to the folder where you want the prep jobs written.
# 2. Edit PH / PH_OFFSET if you want a different propka protonation setup.
# 3. Edit SOLVENT_PADDING for the octahedral TIP3P solvent shell.
# 4. Edit ion settings if you want different neutralization or added ions.
# 5. Set OVERWRITE="true" if reruns should replace existing job folders.
# 6. Optionally fill KEEP_HET_RESNAMES if metal ions should be retained.
# 7. Fill JOB_NAMES and PDB_FILES with matching entries.
# 8. Submit with:
#      sbatch /nobackup/proj/rockhpc_jsbs/Yang/scripts/enlighten/run_apo_Enlighten_PREP.sh
#
# Minimal example:
# PROJECT_ROOT="/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/apo_jobs"
# NEUTRALIZE="true"
# NEUTRALIZE_ION="Na+"
# EXTRA_IONS=("K+ 4" "CL- 4")
# OVERWRITE="true"
# KEEP_HET_RESNAMES=("MG")
# JOB_NAMES=("af_pabb_apo")
# PDB_FILES=("/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/af_pabb_apo/input.pdb")
#
# Notes:
# - JOB_NAMES and PDB_FILES must have the same number of entries.
# - The input PDB should be the full apo protein or full protein complex.
# - Solvation now uses solvateOct, so no center atom or center coordinates are needed.
# - Neutralization is enabled by default and uses one selected ion.
# - EXTRA_IONS is optional and can contain repeated "ION COUNT" entries.
# - OVERWRITE="true" will delete an existing ${job_name} prep folder before rerunning.
# - KEEP_HET_RESNAMES is optional. Leave it empty for protein-only prep.
# - Residue names must match the PDB resName field exactly, e.g. MG, ZN, FE, MN.

#SBATCH --job-name=PREP_APO
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --mem-per-cpu=10gb
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

# Environment:
# Pick the setup that matches your cluster environment.
source /nobackup/shared/containers/ambermd.24.25.sh
export AMBERHOME=/mnt/nfs/home/nsy49/miniforge3/envs/AmberTools25
export PATH="$AMBERHOME/bin:$PATH"

# If you prefer a manual AmberTools setup instead of `module load`, use:
# source /nobackup/shared/containers/ambermd.24.25.sh
# export AMBERHOME=/mnt/nfs/home/nsy49/miniforge3/envs/AmberTools25
# export PATH="$AMBERHOME/bin:$PATH"

# Important:
# Under sbatch, the shell script may be copied to a temporary Slurm directory,
# so BASH_SOURCE[0] can point to /tmp/slurmd/... instead of the real script
# location. Use the stable project path for the prep script.
SCRIPT_DIR="/nobackup/proj/rockhpc_jsbs/Yang/scripts/enlighten"
PREP_SCRIPT="${SCRIPT_DIR}/prep_apo_enlighten.py"

# Edit these for your system(s).
PROJECT_ROOT="/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/apo_jobs"
PH="7.0"
PH_OFFSET="0.7"
SOLVENT_PADDING="10.0"
NEUTRALIZE="true"
NEUTRALIZE_ION="Na+"
EXTRA_IONS=(
)
OVERWRITE="false"
SKIP_PROPKA="false"
KEEP_HET_RESNAMES=(
)

# One entry per apo system. Arrays must have the same length.
JOB_NAMES=(
  "example_apo"
)

PDB_FILES=(
  "/path/to/example_apo_input.pdb"
)

if [[ ! -f "${PREP_SCRIPT}" ]]; then
    echo "Cannot find prep script: ${PREP_SCRIPT}" >&2
    exit 1
fi

if [[ "${#JOB_NAMES[@]}" -ne "${#PDB_FILES[@]}" ]]; then
    echo "JOB_NAMES and PDB_FILES must have the same length." >&2
    exit 1
fi

mkdir -p "${PROJECT_ROOT}"

for i in "${!JOB_NAMES[@]}"; do
    job_name="${JOB_NAMES[$i]}"
    pdb_file="${PDB_FILES[$i]}"

    if [[ ! -f "${pdb_file}" ]]; then
        echo "Input PDB does not exist for ${job_name}: ${pdb_file}" >&2
        exit 1
    fi
    pdb_file="$(readlink -f "${pdb_file}")"

    outdir="${PROJECT_ROOT}/${job_name}"
    workdir="${outdir}/enlighten"

    if [[ -e "${workdir}/${job_name}" ]]; then
        if [[ "${OVERWRITE}" == "true" ]]; then
            echo "Overwriting existing output for ${job_name}: ${workdir}/${job_name}"
        else
            echo "Output already exists for ${job_name}: ${workdir}/${job_name}" >&2
            echo "Set OVERWRITE=\"true\" or remove it manually before re-running." >&2
            exit 1
        fi
    fi

    mkdir -p "${workdir}"

    cmd=(
      python3 "${PREP_SCRIPT}"
      "${job_name}"
      "${pdb_file}"
      --ph "${PH}"
      --ph-offset "${PH_OFFSET}"
      --solvent-padding "${SOLVENT_PADDING}"
      --neutralize-with "${NEUTRALIZE_ION}"
    )

    if [[ "${SKIP_PROPKA}" == "true" ]]; then
        cmd+=(--skip-propka)
    fi

    if [[ "${OVERWRITE}" == "true" ]]; then
        cmd+=(--overwrite)
    fi

    if [[ "${NEUTRALIZE}" != "true" ]]; then
        cmd+=(--no-neutralize)
    fi

    if [[ "${#EXTRA_IONS[@]}" -gt 0 ]]; then
        for ion_spec in "${EXTRA_IONS[@]}"; do
            # shellcheck disable=SC2206
            ion_parts=(${ion_spec})
            if [[ "${#ion_parts[@]}" -ne 2 ]]; then
                echo "Each EXTRA_IONS entry must look like 'ION COUNT': ${ion_spec}" >&2
                exit 1
            fi
            cmd+=(--add-ion "${ion_parts[0]}" "${ion_parts[1]}")
        done
    fi

    if [[ "${#KEEP_HET_RESNAMES[@]}" -gt 0 ]]; then
        cmd+=(--keep-het "${KEEP_HET_RESNAMES[@]}")
    fi

    echo "Running apo prep for ${job_name}"
    printf 'Command:'
    printf ' %q' "${cmd[@]}"
    printf '\n'
    (
        cd "${workdir}"
        "${cmd[@]}"
    )
done
