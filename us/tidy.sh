#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

replicas=$1
SCRIPT_ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/us

cp "$SCRIPT_ROOT/ren_del_dftb.sh" us_dftb
cp "$SCRIPT_ROOT/ren_del_md.sh" md

cd md || exit 1
./ren_del_md.sh "$replicas"
rm -f ren_del_md.sh
cd .. || exit 1

cd us_dftb || exit 1
./ren_del_dftb.sh "$replicas"
rm -f ren_del_dftb.sh
rm -f US*/md.rst_5000
for dir in US*/; do
	replica="${dir#US}"
	replica="${replica%/}"
	ln -sf "../md/dynam${replica}/md.rst_5000" "$dir/md.rst_5000"
done
rm -f wham_*
./wham.sh
wham P 1.275 3.525 45 0.000000001 300 0 meta_all.dat mega_wham_2ps.dat 0 1 > mega_wham_2ps.log
cd .. || exit 1
