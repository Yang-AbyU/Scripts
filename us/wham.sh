#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

replica=1
for dir in US*/; do
	cd "$dir" || exit 1
	wham P 1.275 3.525 45 0.000000001 300 0 meta.dat wham_2ps.dat 0 1 > wham_2ps.log
	cp wham_2ps.dat "../wham_${replica}.dat"
	cd .. || exit 1
	replica=$((replica + 1))
done
