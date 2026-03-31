#!/usr/bin/env python3
"""
Standalone AmberTools preparation for an apo protein or protein complex.

This script is independent of the ligand-oriented Enlighten2 prep workflow.
It runs the needed AmberTools programs directly and creates an Enlighten-style
directory layout for an apo system:

<job_name>/
  pdb4amber_reduce/
  propka/
  tleap/
  <job_name>.top
  <job_name>.rst

Workflow:
1. copy the input PDB into pdb4amber_reduce/input.pdb
2. run pdb4amber
3. run reduce
4. keep protein ATOM records and optional retained HETATM residues
5. optionally run propka31 and rename residues for Amber compatibility
6. write a standalone tleap.in
7. solvate the full system with solvateOct
8. write the final topology/restart files

Typical manual usage:
    python3 prep_apo_enlighten.py af_pabb_apo /path/to/input.pdb \
        --ph 7.0 --ph-offset 0.7 --solvent-padding 10.0

Example keeping metal ions:
    python3 prep_apo_enlighten.py af_pabb_mg /path/to/input.pdb \
        --solvent-padding 10.0 --keep-het MG ZN

Example with flexible ion addition:
    python3 prep_apo_enlighten.py af_pabb_apo /path/to/input.pdb \
        --solvent-padding 10.0 --neutralize-with Na+ \
        --add-ion Cl- 2 --add-ion K+ 4

Important notes:
- The input PDB should be the whole apo protein or whole protein complex.
- Solvation uses solvateOct, not solvatecap.
- The solvated system is neutralized by default with one selected ion.
- Use --overwrite if you want to delete an existing job folder and rebuild it.
- No ligand parameters are used.
- If you need to retain metal ions or other simple HETATM residues, pass their
  residue names with --keep-het, for example: --keep-het MG ZN MN FE CA
- The script expects AmberTools commands (pdb4amber, reduce, tleap, and
  optionally propka31) to be available in PATH.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys


PROT_DICT = {"ASP": "ASH", "GLU": "GLH"}
DEPROT_DICT = {"CYS": "CYM", "LYS": "LYN"}
HIS_RENAME_DICT = {"no HE2": "HID", "no HD1": "HIE", "bothHN": "HIP"}


def log(message):
    print(message)
    sys.stdout.flush()


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def ensure_job_does_not_exist(job_name, overwrite=False):
    if os.path.exists(job_name):
        if overwrite:
            shutil.rmtree(job_name)
            return
        fail(
            f"Output folder {job_name} already exists. Remove it or choose a new job name."
        )


def run_command(command, cwd, outfile=None, accept_existing_output=False):
    if outfile:
        with open(outfile, "w") as handle:
            result = subprocess.run(
                command,
                cwd=cwd,
                stdout=handle,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
            )
    else:
        result = subprocess.run(
            command,
            cwd=cwd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
    if result.returncode != 0:
        if outfile and accept_existing_output and os.path.isfile(outfile) and os.path.getsize(outfile) > 0:
            log(
                "Command returned a non-zero exit code but produced output; continuing: "
                + " ".join(command)
            )
            return
        location = outfile if outfile else cwd
        fail(f"Command failed: {' '.join(command)}\nCheck {location} for details.")


def parse_atom_line(line):
    return {
        "record": line[:6].strip(),
        "serial": int(line[6:11].strip()) if line[6:11].strip() else 0,
        "name": line[12:16].strip(),
        "altLoc": line[16].strip(),
        "resName": line[17:20].strip(),
        "chainID": line[21].strip(),
        "resSeq": int(line[22:26].strip()),
        "iCode": line[26].strip(),
        "x": float(line[30:38]),
        "y": float(line[38:46]),
        "z": float(line[46:54]),
        "occupancy": float(line[54:60]) if line[54:60].strip() else 1.0,
        "tempFactor": float(line[60:66]) if line[60:66].strip() else 0.0,
        "element": line[76:78].strip(),
        "charge": line[78:80].strip(),
        "extras": line[80:] if len(line) > 80 else "\n",
    }


def parse_ter_line(line):
    return {
        "record": "TER",
        "serial": int(line[6:11].strip()) if line[6:11].strip() else 0,
        "resName": line[17:20].strip(),
        "chainID": line[21].strip(),
        "resSeq": int(line[22:26].strip()) if line[22:26].strip() else 0,
        "iCode": line[26].strip(),
        "extras": line[27:] if len(line) > 27 else "\n",
    }


def format_atom_line(atom):
    name_format = "{name:>4}" if len(atom["name"]) > 2 else " {name:<3}"
    return (
        "{record:6}{serial:5} "
        + name_format
        + "{altLoc:1}{resName:>3} {chainID:1}{resSeq:4}{iCode:1}"
        "   {x:8.3f}{y:8.3f}{z:8.3f}{occupancy:6.2f}{tempFactor:6.2f}"
        "          {element:>2}{charge:>2}{extras}"
    ).format(**atom)


def format_ter_line(ter):
    return (
        "{record:6}{serial:5} {resName:>8} {chainID:1}{resSeq:4}{iCode:1}{extras}"
    ).format(**ter)


def residue_id(entry):
    return (entry["chainID"], entry["resSeq"], entry["iCode"])


def residue_key(entry):
    return (entry["chainID"], entry["resSeq"], entry["resName"])


def load_pdb(path):
    atoms = []
    ters = []
    conect = []
    other = []
    with open(path) as handle:
        for line in handle:
            if line.startswith(("ATOM  ", "HETATM")):
                atoms.append(parse_atom_line(line))
            elif line.startswith("TER"):
                ters.append(parse_ter_line(line))
            elif line.startswith("CONECT"):
                conect.append(line)
            else:
                other.append(line)
    return atoms, ters, conect, other


def write_pdb(path, atoms, ters=None, conect=None, other=None):
    ters = ters or []
    conect = conect or []
    other = other or []
    ters_by_residue = {residue_id(ter): ter for ter in ters}
    with open(path, "w") as handle:
        for line in other:
            if line.startswith("USER  MOD"):
                handle.write(line)
        for index, atom in enumerate(atoms):
            handle.write(format_atom_line(atom))
            current_residue = residue_id(atom)
            next_residue = residue_id(atoms[index + 1]) if index + 1 < len(atoms) else None
            if current_residue != next_residue and current_residue in ters_by_residue:
                ter = ters_by_residue.pop(current_residue)
                ter["resName"] = atom["resName"]
                handle.write(format_ter_line(ter))
        for line in conect:
            handle.write(line)


def select_retained_entries(atoms, ters, keep_het_resnames=None):
    keep_het_resnames = {name.upper() for name in (keep_het_resnames or [])}
    protein_atoms = [atom for atom in atoms if atom["record"] == "ATOM"]
    retained_het_atoms = [
        atom
        for atom in atoms
        if atom["record"] == "HETATM" and atom["resName"].upper() in keep_het_resnames
    ]
    kept_atoms = protein_atoms + retained_het_atoms
    protein_residues = {residue_id(atom) for atom in protein_atoms}
    protein_ters = [ter for ter in ters if residue_id(ter) in protein_residues]
    return kept_atoms, protein_ters


def rename_histidines(atoms, other_lines):
    rename_map = {}
    for line in other_lines:
        if not line.startswith("USER  MOD"):
            continue
        if line[25:28] != "HIS":
            continue
        new_name = HIS_RENAME_DICT.get(line[39:45])
        if not new_name:
            continue
        key = (line[19].strip(), int(line[20:24]), "HIS")
        rename_map[key] = new_name

    for atom in atoms:
        key = (atom["chainID"], atom["resSeq"], atom["resName"])
        if key in rename_map:
            atom["resName"] = rename_map[key]


def parse_propka_output(path):
    with open(path) as handle:
        for line in handle:
            if line == "SUMMARY OF THIS PREDICTION\n":
                break
        else:
            return {}
        next(handle, None)
        results = {}
        for line in handle:
            if len(line.strip()) != 29:
                continue
            raw = line.split()
            results[(raw[2], int(raw[1]), raw[0])] = {
                "resName": raw[0],
                "chainID": raw[2],
                "resSeq": int(raw[1]),
                "pKa": float(raw[3]),
            }
        return results


def apply_propka_residue_names(atoms, propka_entries, ph, ph_offset):
    protonate_cutoff = ph + ph_offset
    deprotonate_cutoff = ph - ph_offset

    prot_list = []
    deprot_list = []
    residue_actions = {}
    for entry in propka_entries.values():
        key = (entry["chainID"], entry["resSeq"])
        if entry["resName"] in PROT_DICT and entry["pKa"] >= protonate_cutoff:
            residue_actions[key] = PROT_DICT[entry["resName"]]
            prot_list.append(entry)
        if entry["resName"] in DEPROT_DICT and entry["pKa"] <= deprotonate_cutoff:
            residue_actions[key] = DEPROT_DICT[entry["resName"]]
            deprot_list.append(entry)

    for atom in atoms:
        key = (atom["chainID"], atom["resSeq"])
        if key in residue_actions:
            atom["resName"] = residue_actions[key]

    # Remove extra H atoms that conflict with deprotonated states.
    filtered_atoms = []
    for atom in atoms:
        if atom["resName"] == "LYN" and atom["name"] == "HZ1":
            continue
        if atom["resName"] == "CYM" and atom["name"] == "HG":
            continue
        if atom["name"].startswith("H") and "new" in atom["extras"]:
            original_key = (atom["chainID"], atom["resSeq"], "LYS")
            if original_key in propka_entries and propka_entries[original_key]["pKa"] <= deprotonate_cutoff:
                continue
            original_key = (atom["chainID"], atom["resSeq"], "CYS")
            if original_key in propka_entries and propka_entries[original_key]["pKa"] <= deprotonate_cutoff:
                continue
        filtered_atoms.append(atom)

    if prot_list:
        log(
            "Propka protonated residues: "
            + ", ".join(
                f'{entry["resName"]}{entry["resSeq"]}{entry["chainID"]}'
                for entry in prot_list
            )
        )
    if deprot_list:
        log(
            "Propka deprotonated residues: "
            + ", ".join(
                f'{entry["resName"]}{entry["resSeq"]}{entry["chainID"]}'
                for entry in deprot_list
            )
        )

    return filtered_atoms


def split_residue_atom(spec):
    if "@" not in spec:
        fail("Center atom must look like RESSEQ@ATOM, e.g. 325@CZ")
    resseq, atom_name = spec.split("@", 1)
    return int(resseq), atom_name.strip()


def write_tleap_input(path, name, solvent_padding, neutralize=True, neutralize_with="Na+", extra_ions=None):
    extra_ions = extra_ions or []
    with open(path, "w") as handle:
        handle.write("source oldff/leaprc.ff14SB\n")
        handle.write("source leaprc.water.tip3p\n")
        handle.write("mol = loadpdb input.pdb\n")
        handle.write(f"solvateOct mol TIP3PBOX {solvent_padding}\n")
        if neutralize:
            handle.write(f"addIons mol {neutralize_with} 0\n")
        for ion_name, ion_count in extra_ions:
            handle.write(f"addIons mol {ion_name} {ion_count}\n")
        handle.write(f"saveamberparm mol {name}.top {name}.rst\n")
        handle.write(f"savepdb mol {name}.pdb\n")
        handle.write("quit\n")


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Prepare an apo protein with AmberTools and create a folder containing "
            "pdb4amber/reduce, optional propka, tleap, and final top/rst files."
        ),
        epilog=(
            "Example:\n"
            "  python3 prep_apo_enlighten.py af_pabb_apo /path/to/input.pdb "
            "--ph 7.0 --ph-offset 0.7 --solvent-padding 10.0\n"
            "  python3 prep_apo_enlighten.py af_pabb_mg /path/to/input.pdb "
            "--solvent-padding 10.0 --keep-het MG --neutralize-with Na+\n"
            "  python3 prep_apo_enlighten.py af_pabb_salt /path/to/input.pdb "
            "--solvent-padding 10.0 --add-ion K+ 4 --add-ion Cl- 4\n\n"
            "Outputs are written under <name>/ with pdb4amber_reduce/, propka/, "
            "tleap/, <name>.top, and <name>.rst."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("name", help="Name of the output job directory")
    parser.add_argument("pdb", help="Input protein PDB file", type=argparse.FileType())
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite an existing output folder for this job name",
    )
    parser.add_argument("--ph", type=float, default=7.0)
    parser.add_argument("--ph-offset", type=float, default=0.7)
    parser.add_argument("--skip-propka", action="store_true")
    parser.add_argument(
        "--solvent-padding",
        type=float,
        default=10.0,
        help="Padding in Angstrom for solvateOct (default: 10.0)",
    )
    parser.add_argument(
        "--keep-het",
        nargs="*",
        default=[],
        metavar="RESNAME",
        help=(
            "Optional HETATM residue names to retain in the final system, "
            "for example: --keep-het MG ZN FE"
        ),
    )
    parser.add_argument(
        "--no-neutralize",
        action="store_true",
        help="Do not add counterions after solvation",
    )
    parser.add_argument(
        "--neutralize-with",
        default="Na+",
        help="Ion name used for tleap neutralization (default: Na+)",
    )
    parser.add_argument(
        "--add-ion",
        action="append",
        nargs=2,
        default=[],
        metavar=("ION", "COUNT"),
        help="Add a specific ion and count after neutralization, repeatable",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    ensure_job_does_not_exist(args.name, overwrite=args.overwrite)

    log(f"Starting apo PREP protocol in {args.name}/")
    os.mkdir(args.name)

    pdb4amber_dir = os.path.join(args.name, "pdb4amber_reduce")
    propka_dir = os.path.join(args.name, "propka")
    tleap_dir = os.path.join(args.name, "tleap")
    os.mkdir(pdb4amber_dir)
    os.mkdir(propka_dir)
    os.mkdir(tleap_dir)

    raw_input_path = os.path.abspath(args.pdb.name)
    args.pdb.close()

    shutil.copy2(raw_input_path, os.path.join(pdb4amber_dir, "input.pdb"))

    log("Running pdb4amber")
    run_command(
        ["pdb4amber", "-i", "input.pdb", "-o", "pdb4amber.pdb", "--nohyd"],
        cwd=pdb4amber_dir,
        outfile=os.path.join(pdb4amber_dir, "pdb4amber.out"),
    )

    log("Running reduce")
    run_command(
        ["reduce", "-build", "-nuclear", "pdb4amber.pdb"],
        cwd=pdb4amber_dir,
        outfile=os.path.join(pdb4amber_dir, "reduce.pdb"),
        accept_existing_output=True,
    )

    atoms, ters, _, other = load_pdb(os.path.join(pdb4amber_dir, "reduce.pdb"))
    rename_histidines(atoms, other)
    atoms, ters = select_retained_entries(atoms, ters, args.keep_het)
    if args.keep_het:
        log("Retaining HETATM residue names: " + ", ".join(name.upper() for name in args.keep_het))

    propka_input = os.path.join(propka_dir, "input.pdb")
    write_pdb(propka_input, atoms, ters)

    if args.skip_propka:
        log("Skipping propka")
    elif shutil.which("propka31"):
        log("Running propka")
        run_command(
            ["propka31", "input.pdb"],
            cwd=propka_dir,
            outfile=os.path.join(propka_dir, "propka31.out"),
        )
        propka_entries = parse_propka_output(os.path.join(propka_dir, "input.pka"))
        atoms = apply_propka_residue_names(atoms, propka_entries, args.ph, args.ph_offset)
        write_pdb(propka_input, atoms, ters)
    else:
        log("propka31 not found in PATH, continuing without propka")

    shutil.copy2(propka_input, os.path.join(tleap_dir, "input.pdb"))
    log(f"Solvation mode: solvateOct")
    log(f"Solvent padding: {args.solvent_padding}")
    if args.no_neutralize:
        log("Neutralization: disabled")
    else:
        log(f"Neutralization: enabled with {args.neutralize_with}")
    if args.add_ion:
        log(
            "Extra ions: "
            + ", ".join(f"{ion} x{count}" for ion, count in args.add_ion)
        )
    write_tleap_input(
        os.path.join(tleap_dir, "tleap.in"),
        os.path.basename(args.name),
        args.solvent_padding,
        neutralize=not args.no_neutralize,
        neutralize_with=args.neutralize_with,
        extra_ions=args.add_ion,
    )

    log("Running tleap")
    run_command(
        ["tleap", "-f", "tleap.in"],
        cwd=tleap_dir,
        outfile=os.path.join(tleap_dir, "tleap.log"),
    )

    top_file = os.path.join(tleap_dir, f"{os.path.basename(args.name)}.top")
    rst_file = os.path.join(tleap_dir, f"{os.path.basename(args.name)}.rst")
    if not os.path.isfile(top_file) or not os.path.isfile(rst_file):
        fail(f"tleap did not generate expected outputs. Check {os.path.join(tleap_dir, 'tleap.log')}")

    with open(os.path.join(tleap_dir, "params"), "w") as handle:
        json.dump(
            {
                "solvation_mode": "oct",
                "solvent_padding": args.solvent_padding,
                "neutralized": not args.no_neutralize,
                "neutralize_with": args.neutralize_with,
                "extra_ions": args.add_ion,
            },
            handle,
        )

    shutil.copy2(top_file, args.name)
    shutil.copy2(rst_file, args.name)
    log("Finished apo PREP protocol.")


if __name__ == "__main__":
    main()
