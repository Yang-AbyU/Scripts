
mut=$1

if [ ! $# -eq 1 ]; then 
	echo "Usage: make_complex_pdbs_for_mut.sh [mutant docking case e.g wt] "
	exit
fi

if [ ! -d docked_pose_pdbs/$mut ]; then echo "$mut doesn't exist: Exiting..."; exit; fi

if [ ! -e protein_pdbs/${mut}.pdb ]; then echo "Protein pdb or pdbqts for $mut doesn't exist: Exiting..."; exit; fi

# Get array of filenames of the docked ligand pose pdbs for which to create the corresponding complex pdbs
cd docked_pose_pdbs/$mut

for pdb in *.pdb; do if [ ! -e $pdb ]; then continue; fi; file_array+=($pdb); done

cd ../../complex_pdbs

if [ ! -d $mut ]; then 
	mkdir $mut
fi

cd $mut

# Get string of flexible residues from the flexible protein pdbqt for this mutant
res_list=`awk '/^ATOM/ {print $6}' ../../protein_pdbqts/${mut}_flex_A.pdbqt | uniq`

## Make a pdb of the rigid part of the protein from the original mutant pdb by only printing backbone atoms of the residues which were treated flexibly (i.e. those that are in $res_list)
awk -v r="$res_list" 'BEGIN{ split(r,res_array) } { 

	for(i in res_array) {
		if($6==res_array[i]) {
			if (($3=="N")||($3=="CA")||($3=="C")||($3=="O")) {
				pr=1; break
			} else {
				pr=0; break
			}
		} else {
			pr=1 
		}
	}
	
	if(pr==1) { print }
	pr=0
	
}' ../../protein_pdbs/${mut}.pdb > rigid_prot.pdb

for file in ${file_array[@]}; do

	# Get just the filename of the docked ligand pose from the full filepath to use for naming the output complex pdbs
	docked_pose=`basename $file`
	
	if [ -e $docked_pose ]; then echo "$docked_pose already exists: skipping..."; continue; fi
	
	echo "Processing $file"
	
	# Combine the atoms from the rigid protein pdb and flexible residue atoms from the docked pose pdb into a single pdb (in order of residue number)
	for i in `seq 1 180`; do 
		awk -v res=$i '/^ATOM/ {if ($6==res) print}' rigid_prot.pdb; 
		awk -v res=$i '/^ATOM/ {if (($6==res)&&($3!="CA")) print}' ../../docked_pose_pdbs/$mut/$file; 
	done > $docked_pose

	# Combine protein & ligand
	echo "TER" >> $docked_pose
	awk '/^HETATM/ {printf("%sL%s\n",substr($0,0,21),substr($0,23,70))}' ../../docked_pose_pdbs/$mut/$file >> $docked_pose
	echo "END" >> $docked_pose

done



