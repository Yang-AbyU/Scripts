#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script_path="$(readlink -f "${BASH_SOURCE[0]}")"
resi=133

if [ -z "${SLURM_JOB_ID:-}" ]; then
  wrapper_dir="${SCRIPT_DIR}/.cluster_slurm"
  mkdir -p "$wrapper_dir"
  wrapper="$wrapper_dir/submit_cluster.sh"
  cat > "$wrapper" <<EOF
#!/usr/bin/env bash
#SBATCH --job-name=CLUSTER_US
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:30:00
#SBATCH --mem=10G
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs
#SBATCH --output=${wrapper_dir}/cluster-%j.out
set -euo pipefail
cd "${SCRIPT_DIR}"
bash "${script_path}"
EOF
  chmod 755 "$wrapper"
  echo "Submitting cluster.sh through Slurm..."
  sbatch "$wrapper"
  exit 0
fi

cd "$SCRIPT_DIR"
source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
export AMBERHOME="$CONDA_PREFIX"
command -v cpptraj >/dev/null 2>&1 || {
  echo "cpptraj not found in AmberTools25" >&2
  exit 1
}

if [ ! -d dry_trj_mbondi ]; then
  echo "Missing dry_trj_mbondi in $SCRIPT_DIR" >&2
  exit 1
fi

for i in $(seq 2 5); do
printf "parm dry_trj_mbondi/*_1_mbondi.dry.top
trajin dry_trj_mbondi/*.dry.nc
cluster c1 \
        kmeans clusters ${i} \
        rms :${resi}&!@H= nofit \
        sieve 10 \
        out cluster_cnumvtime.dat \
        summary cluster_summary.dat \
        summarysplit cluster_split.dat \
        splitframe 100,200,300,400,500,600,700,800,900,1000 \
        repout cluster_rep repfmt pdb \
        avgout cluster_avg avgfmt pdb \
        info infofile_num \
        sil sil_num \
        clusterout cluster_traj_split
run
" > cluster_${i}.in
cpptraj -i cluster_${i}.in
rm -rf cluster_num${i}
mkdir cluster_num${i}
mv cluster_avg* cluster_cnumvtime.dat cluster_rep* cluster_split.dat cluster_summary.dat cluster_traj_split* infofile_num* sil_num* cluster_${i}.in cluster_num${i}
done

grep -rni -e "pSF" -e "DBI" cluster_num*/infofile_num > clustering.dat

echo "Wrote clustering outputs in $SCRIPT_DIR"
