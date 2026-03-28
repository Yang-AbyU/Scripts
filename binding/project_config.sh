#!/usr/bin/env bash

# Shared project settings for the binding workflow.
#
# How to use this file:
#   1. Copy this file into your project folder, or edit the local project copy.
#   2. Update the variables below for the current protein / ligand / pose.
#   3. Run the pipeline from the project directory:
#        ./run_binding_pipeline.sh
#
# Important fields to edit for a new project:
#   - project_root: absolute path to the current project directory
#   - enzyme: protein/enzyme name
#   - ligand: ligand name
#   - pose: pose identifier or pose number
#   - system: usually us_dftb unless your project uses another name
#   - replicas: list of replica IDs to process in every stage
#   - belly: ligand-centered restraint / belly mask used by relax and MD steps
#   - c_atoms: ligand carbon index used by run_enlight.sh when filling add_params
#   - ligand_residue_id: residue number of the ligand in the prepared structures
#   - ligand_resname: residue name of the ligand, usually LIG
#
# Notes:
#   - The pipeline scripts source this file and use these values for every stage.
#   - If project_root is wrong, the pipeline may submit jobs in one place but check
#     outputs in a different place.
#   - Keep the replica list consistent across the whole workflow by editing it here
#     instead of editing each stage script separately.

project_root=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/abyu_wt/exo_ext/pose_2
shared_binding_root=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding
amber_container_setup=/nobackup/shared/containers/ambermd.24.25.sh
conda_setup=/mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda_env=AmberTools25

enzyme=abyu_wt
ligand=exo_ext
pose=2
system=us_dftb

# Replica list to process in every stage.
replicas=(1 3 4 10 11 12 14 15 19 20)

# Ligand atom/mask settings used by qmmm/enlighten/md scripts.
belly=':133@C8'
c_atoms=8
ligand_residue_id=133
ligand_resname=LIG

# Pipeline waiting interval in seconds.
poll_seconds=30
