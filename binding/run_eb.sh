#!/bin/bash

enzyme=abyu_wt
ligand=endo
pose=endo

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
export AMBERHOME="$CONDA_PREFIX"

ROOT=$(pwd)
dirs=$(find us_dftb/ -maxdepth 1 -type d -name "US*" | wc -l)
system=us_dftb
cd ${system}
for replica in `seq 1 $dirs`; do
	cd us_dftb_${replica}/tleap
	printf "source oldff/leaprc.ff14SB
source leaprc.water.tip3p
source leaprc.gaff2
loadamberprep ../antechamber/LIG.prepc
loadamberparams ../antechamber/LIG.frcmod
mol = loadpdb us_dftb_${replica}.pdb
set default PBRadii mbondi2
saveamberparm mol ${system}_${replica}_mbondi.top ${system}_${replica}_mbondi.rst
quit
" > tleap_mbondi.in
	tleap -f tleap_mbondi.in
	rm ${system}_${replica}_mbondi.rst
	cd ../../
	cd MD_MMGBSA_$replica
        rm -f ${system}_${replica}_mbondi.dry.top
        rm -f ligand_mbondi.top
        rm -f receptor_mbondi.top
        nice $AMBERHOME/bin/ante-MMPBSA.py -p $ROOT/${system}/${system}_${replica}/tleap/${system}_${replica}_mbondi.top -c ${system}_${replica}_mbondi.dry.top -s ":WAT" -r receptor_mbondi.top -l ligand_mbondi.top  -n ":LIG,FR2"
	cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding/cpptraj_strip_Cyc15.i ./
        sed -i "s/__SYSTEM__/$system/g" cpptraj_strip_Cyc15.i
        sed -i "s/__REPLICA__/$replica/g" cpptraj_strip_Cyc15.i
        sed -i "s/__ENZYME__/$enzyme/g" cpptraj_strip_Cyc15.i
        sed -i "s%__LIG__%$ligand%g" cpptraj_strip_Cyc15.i
        sed -i "s/__POSE__/$pose/g" cpptraj_strip_Cyc15.i
        cpptraj -i cpptraj_strip_Cyc15.i
        cd ../
done

rm -rf dry_trj_mbondi
mkdir dry_trj_mbondi
cd dry_trj_mbondi
cp /nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/binding/mmgbsa.i ./
printf "#!/bin/bash

#SBATCH --job-name=EB_${ligand}_${pose}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:59:00
#SBATCH --mem-per-cpu=20gb
#SBATCH --partition=default_free
#SBATCH --account=rockhpc_jsbs

source /mnt/nfs/home/nsy49/miniforge3/etc/profile.d/conda.sh
conda activate AmberTools25
export AMBERHOME=\$CONDA_PREFIX

$AMBERHOME/bin/MMPBSA.py -O -i mmgbsa.i -cp *_1_mbondi.dry.top -rp receptor_mbondi.top -lp ligand_mbondi.top -y *.dry.nc -eo mmgbsa.csv
" > submit.sh
cd ..
for replica in `seq 1 $dirs`; do
        cp MD_MMGBSA_${replica}/${system}_${replica}_mbondi.dry.top dry_trj_mbondi
        cp MD_MMGBSA_${replica}/receptor_mbondi.top dry_trj_mbondi
        cp MD_MMGBSA_${replica}/ligand_mbondi.top dry_trj_mbondi
        cp MD_MMGBSA_${replica}/${system}_${replica}_100ps.dry.nc dry_trj_mbondi
done
cp MD_MMGBSA_1/receptor_mbondi.top dry_trj_mbondi
cp MD_MMGBSA_1/ligand_mbondi.top dry_trj_mbondi
cd dry_trj_mbondi
cd ../../
