#!/bin/bash

#SBATCH --job-name=relax
#SBATCH --partition=gpu-s_free
#SBATCH --account=rockhpc_jsbs
#SBATCH --ntasks-per-node=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=10G
#SBATCH --gres=gpu:L40:1
#SBATCH --time=01:30:00

source /nobackup/shared/containers/ambermd.24.25.sh

ROOT=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/scripts/relax
PARM=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/__ENZYME__/__LIG__/pose___POSE__/enlighten/__LIG__/tleap/__LIG__.top
RST=/nobackup/proj/rockhpc_jsbs/Yang/MD_simulation/__ENZYME__/__LIG__/pose___POSE__/enlighten/__LIG__/tleap/__LIG__.rst

mkdir minimize_h_all
mv minimize_h_all.in minimize_h_all
cd minimize_h_all
container.run sander -O -i minimize_h_all.in -p $PARM -c $RST -r minimize_h_all.rst -o out -ref $RST
cd ..

mkdir minimize_h_in_sphere
mv minimize_h_in_sphere.in minimize_h_in_sphere
cd minimize_h_in_sphere
container.run sander -O -i minimize_h_in_sphere.in -p $PARM -c ../minimize_h_all/minimize_h_all.rst -r minimize_h_in_sphere.rst -o out -ref ../minimize_h_all/minimize_h_all.rst
cd ..

mkdir annealing_with_restraints
mv annealing_with_restraints.in annealing_with_restraints
cd annealing_with_restraints
container.run sander -O -i annealing_with_restraints.in -p $PARM -c ../minimize_h_in_sphere/minimize_h_in_sphere.rst -r annealing_with_restraints.rst -o out -ref ../minimize_h_in_sphere/minimize_h_in_sphere.rst
cd ..

mkdir annealing_without_restraints
mv annealing_without_restraints.in annealing_without_restraints
cd annealing_without_restraints
container.run sander -O -i annealing_without_restraints.in -p $PARM -c ../annealing_with_restraints/annealing_with_restraints.rst -r annealing_without_restraints.rst -o out -ref ../annealing_with_restraints/annealing_with_restraints.rst
cd ..

mkdir minimize_all_in_sphere
mv minimize_all_in_sphere.in minimize_all_in_sphere
cd minimize_all_in_sphere
container.run sander -O -i minimize_all_in_sphere.in -p $PARM -c ../annealing_without_restraints/annealing_without_restraints.rst -r __LIG___relax.rst -o out -ref ../annealing_without_restraints/annealing_without_restraints.rst
cd ..

cp minimize_all_in_sphere/__LIG___relax.rst ./
