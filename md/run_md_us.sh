#!/bin/bash

#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --partition=gpu-s_paid
#SBATCH --ntasks-per-node=1
#SBATCH --time=01:00:00
#SBATCH --job-name=md_us
#SBATCH --account=rockhpc_jsbs

set -euo pipefail

residue=133
enzyme=abyu_test
ligand=mk_07
poses=(1 2 7 8)
c_atoms=(1 1 1 1)
c1=2046
c2=2052
c3=2031
c4=2055
c5=2033
c6=2065
nrep=20
SCRIPT_ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts
ROOT1="$SCRIPT_ROOT/md"
ROOT2="$SCRIPT_ROOT/us"
for i in "${!poses[@]}"; do
	pose="${poses[$i]}"
	belly=":${residue}@C${c_atoms[$i]}"
	cd "pose_${pose}" || exit 1
	mkdir -p md
    cd md || exit 1
    cp "$ROOT1/run_init.sh" ./
	cp "$ROOT1/run_sep_dynam.sh" ./
	cp "$ROOT1/heat_prep.in" ./
	cp "$ROOT1/md_prep.in" ./
	cp "$ROOT1/heat.in" ./
	cp "$ROOT1/md.in" ./
    sed -i "s/__ENZYME__/$enzyme/g" run_init.sh run_sep_dynam.sh
    sed -i "s%__LIG__%$ligand%g" run_init.sh run_sep_dynam.sh
    sed -i "s/__POSE__/$pose/g" run_init.sh run_sep_dynam.sh
    sed -i "s/__BELLY__/$belly/g" heat_prep.in md_prep.in heat.in md.in
	for j in $(seq 1 "$nrep"); do
		mkdir -p "dynam${j}"
		cp heat.in "dynam${j}"
		cp md.in "dynam${j}"
	done
	mkdir -p dynam_prep
	mv heat_prep.in md_prep.in dynam_prep
	rm -f heat.in md.in
	jid1=$(sbatch run_init.sh | awk '{print $4}')
	jid2=$(sbatch --dependency=afterok:$jid1 run_sep_dynam.sh | awk '{print $4}')	
	cd .. || exit 1
	
	mkdir -p us_dftb
    cd us_dftb || exit 1
    cp "$ROOT2/setup_us.sh" ./
	cp "$ROOT2/md2ps.i" ./
	cp "$ROOT2/run_sub_us.sh" ./
    sed -i "s/__ENZYME__/$enzyme/g" setup_us.sh
    sed -i "s%__LIG__%$ligand%g" setup_us.sh
    sed -i "s/__POSE__/$pose/g" setup_us.sh
    sed -i "s/__BELLY__/$belly/g" md2ps.i
    sed -i "s/__c1__/$c1/g" setup_us.sh
    sed -i "s/__c2__/$c2/g" setup_us.sh
    sed -i "s/__c3__/$c3/g" setup_us.sh
    sed -i "s/__c4__/$c4/g" setup_us.sh
    sed -i "s/__c5__/$c5/g" setup_us.sh
    sed -i "s/__c6__/$c6/g" setup_us.sh
	ln -sf "/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/${enzyme}/${ligand}/pose_${pose}/enlighten/${ligand}/tleap/${ligand}.top" .
	for j in $(seq 1 "$nrep"); do
		mkdir -p "US${j}"
		cp md2ps.i "US${j}"
		cp setup_us.sh "US${j}"
		cd "US${j}" || exit 1
		sed -i "s/__REPLICA__/$j/g" setup_us.sh
		chmod u+x setup_us.sh
		ln -sf "/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/${enzyme}/${ligand}/pose_${pose}/md/dynam${j}/md.rst_5000" .
		./setup_us.sh
		rm -f md2ps.i setup_us.sh
		cd .. || exit 1
	done
	rm -f md2ps.i setup_us.sh
	sbatch --dependency=afterok:$jid2 run_sub_us.sh
	cd ../.. || exit 1
done
