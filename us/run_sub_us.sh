#!/bin/bash

#SBATCH --job-name=US
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=01:00:00
#SBATCH --mem=10G
#SBATCH --partition=gpu-s_paid
#SBATCH --account=rockhpc_jsbs

set -euo pipefail
shopt -s nullglob

for dir in US*/; do
    cd "$dir" || exit 1
    sbatch submit_umb_samp.sh
    cd .. || exit 1
done
