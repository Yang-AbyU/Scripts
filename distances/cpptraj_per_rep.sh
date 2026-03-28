dirs=$(find us_dftb/ -maxdepth 1 -type d -name "US*" | wc -l)
for i in `seq 1 $dirs`;do
	cp cpptraj.in MD_MMGBSA_${i}
	cd MD_MMGBSA_${i}
	sed -i "s/__REPLICA__/$i/g" cpptraj.in
	cpptraj -i cpptraj.in
	cp distance.out ../distance_${i}.out 
	cd ../
done
