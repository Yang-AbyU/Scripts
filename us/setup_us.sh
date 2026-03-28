#!/bin/bash

#SBATCH --job-name=QM_AdRedAm
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=05:00:00
#SBATCH --mem=10G
#SBATCH --partition=gpu-s_paid
#SBATCH --account=rockhpc_jsbs

# Prepare for Umbrella sampling, WITHOUT spawning:
#  - create directory for each rc
#  - create md inputfile(s) for each rc (requires presence of 'template' $md_files)
#  - create restraint (.RST) files for each rc
#  - create job submission script that runs series of jobs (run_umb_samp.sh)

set -euo pipefail

C1=__c1__
C2=__c2__
C3=__c3__
C4=__c4__
C5=__c5__
C6=__c6__

prmtop="../../__LIG__.top"
restart="md.rst_5000"
md_files="md2ps.i"
start_rc=1.3
end_rc=3.8
step=0.1
kumb=200
rc_line="iat=${C1},${C2},${C3},${C4}, rstwt=0.7,0.3,"

check_bc=1
command -v bc >/dev/null 2>&1 || check_bc=0

qsub_file="submit_umb_samp.sh"

echo "Preparing the following reaction coordinate values:"

workdir=$(pwd)
printf '#!/bin/bash

#SBATCH --job-name=US__REPLICA__
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=6:00:00
#SBATCH --mem=10G
#SBATCH --partition=gpu-s_paid
#SBATCH --account=rockhpc_jsbs

export MYDIR="%s"
cd "$MYDIR" || exit 1
source /nobackup/shared/containers/ambermd.24.25.sh
export MYEXE="container.run sander"
' "$workdir" > "$qsub_file"

for i in $(seq "$start_rc" "$step" "$end_rc"); do
    rc=$(printf '%3.1f' "$i")
    if [[ $check_bc -eq 1 ]]; then
        r1=$(echo "scale=2; $rc-10" | bc)
        r4=$(echo "scale=2; $rc+10" | bc)
    else
        r1=-10.0
        r4=10.0
    fi
    printf '	%s
' "$rc"

    mkdir -p "rc$rc"
    cd "rc$rc" || exit 1

    cat > "rc$rc.RST" <<EOF
# reaction coordinate
&rst
$rc_line,
r1=$r1,r2=$rc,r3=$rc,r4=$r4,
rk2=$kumb,rk3=$kumb,
/
&rst
iat=${C1},${C2},
r1=0,r2=1.0,r3=3.0,r4=10.0,
rk2=0,rk3=0,
/
&rst
iat=${C3},${C4},
r1=0,r2=1.0,r3=3.0,r4=10.0,
rk2=0,rk3=0,
/
&rst
iat=${C5},${C6},
r1=0,r2=2.7,r3=3.7,r4=10.0,
rk2=100,rk3=0,
/
EOF

    sed -e 's/ifqnt=1,/ifqnt=1, nmropt=1,/g' ../md2ps.i > md2ps.i
    cat >> md2ps.i <<EOF
&wt type='DUMPFREQ', istep1=1 /
&wt type='END' /
DISANG=rc$rc.RST
DUMPAVE=rc${rc}.tra
EOF

    printf 'cd "$MYDIR/rc%s" || exit 1
' "$rc" >> "../$qsub_file"
    printf '$MYEXE -O -i md2ps.i -o md2ps.log -p %s -c ../%s -x md2ps.nc -r md2ps.rst
' "$prmtop" "$restart" >> "../$qsub_file"
    restart="rc$rc/md2ps.rst"
    cd .. || exit 1
done

echo 'All done.'
echo '   Carefully check the contents of the reaction coordinate directories created.'
echo '   Check and, if necessary, alter the job submission file: submit_umb_samp.sh'
echo 'Have fun umbrella sampling!'
