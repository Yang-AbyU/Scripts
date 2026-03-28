MD with only ibelly restraint on atoms outside sphere
&cntrl

! General setup
 imin=0,          !Do dynamics, not minimization
 nstlim=10000,    !Total number of MD steps
 dt=0.002,        !timestep (picoseconds)
 irest=1, 
 ntx=5,
! Input reading / Output writing
 ntpr=500,        !Print energies and other stuff every 500 steps
 ntwx=500,        !Save snapshots to the trajectory every 500 steps
 ioutfm=0,        !Specifies input format (ignore that)
 ntwr=-5000,      !Every 1000 steps save a snapshot to separate file

! Motion and forces
 ntf=2,           !Do not calculate forces for bonds with hydrogen atoms
 ntc=2,           !Fix bonds with hydrogen atoms (allows 2fs timestep)
 ntb=0,           !Do not use periodic boundary conditions
 cut=10,          !Ignore interaction between atoms >10 A apart

! Thermostat
 ig=-1,           !Set random number seed to current time in microseconds
 tempi=300.0      !Initial temperature
 ntt=1,           !Use thermostat
 tautp=4.0,       !Thermostat "coupling" (how strongly it affects the dynamics)
 temp0=300.0,     !Thermostat temperature

! Constraints
 ibelly=1,                 !Fix some atoms
 bellymask='__BELLY__<:20.0', !Mask for atom fixing (all atoms >26 A apart from C1 of residue KPI)
/
