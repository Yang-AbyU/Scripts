QM/MM MD with ibelly restraint outside 20.0 sphere (sp20)
&cntrl
 imin=0, irest=1, ntx=5,
 nstlim=2000, dt=0.001,
 ntpr=100, ntwx=500, ioutfm=1, ntwr=1000,
 ntf = 2, ntc = 2, tol = 0.0000005,
 ntb=0, cut=10,
 ibelly=1,
 bellymask='__BELLY__<:20.0',
 ntt=1, tautp=4.0, temp0=300.0,
 ifqnt=1,
/
&qmmm
 qmmask=':LIG',
 qmcharge=0,
 qm_theory='DFTB',
 qmshake=0,
 qmcut=10
/
