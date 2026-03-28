#!/usr/bin/env python3
"""
mmgbsa_means_per_run_commented.py

Purpose:
--------
Extracts "DELTA TOTAL" values from an Amber MMGBSA output file,
splits them into runs (e.g. 100 frames per run),
and computes the mean binding energy per run.

Usage example:
--------------
python mmgbsa_means_per_run_commented.py path/to/MMGBSA_output.txt --block 100

Output:
-------
A CSV file named like: DELTA_TOTAL_per_run_block100.csv
with two columns:
    run, Mean_DELTA_TOTAL

Each row represents the mean binding energy for one run.
"""

# ------------------ IMPORTS ------------------
import argparse     # for command-line argument parsing
import io            # to read string data as if it were a file
import re            # for regular expressions (pattern matching)
import sys           # for error handling and exiting
from pathlib import Path  # for safe file path handling
import pandas as pd       # for convenient CSV parsing and analysis

# ------------------ CONSTANTS ------------------
# This is the text marker that appears before the data table
HEADER_MARK = "DELTA Energy Terms"


# ------------------ FUNCTIONS ------------------
def find_header_index(lines):
    """
    Find the line index where the 'DELTA Energy Terms' section begins.

    Parameters
    ----------
    lines : list[str]
        The entire file, split line-by-line.

    Returns
    -------
    int
        The index (0-based) of the line starting with HEADER_MARK,
        or -1 if not found.
    """
    for i, ln in enumerate(lines):
        if ln.strip().startswith(HEADER_MARK):
            return i
    return -1


def read_block_after_header(lines, header_idx):
    """
    Reads the CSV-like block of data that follows the 'DELTA Energy Terms' header.

    The Amber MMGBSA output file typically looks like:
        ... (some text)
        DELTA Energy Terms
        Frame #,VDWAALS,EEL,EGB,ESURF,DELTA G gas,DELTA G solv,DELTA TOTAL
        0,-48.8457,-24.9501,39.6917,-6.6072,-73.7958,33.0845,-40.7113
        1, ...

    This function will extract that block into a string suitable for pandas.read_csv().

    Parameters
    ----------
    lines : list[str]
        Full file lines.
    header_idx : int
        The index where 'DELTA Energy Terms' was found.

    Returns
    -------
    str
        A string containing the header and data lines.
    """
    if header_idx < 0 or header_idx + 1 >= len(lines):
        return None

    # The line immediately after the marker is the column header
    header_line = lines[header_idx + 1].rstrip("\n")

    # We'll include all subsequent lines that start with a frame number (integer followed by comma)
    data_lines = [header_line]
    pattern = re.compile(r'^\s*\d+\s*,')  # e.g. "0," or "123,"

    for ln in lines[header_idx + 2:]:
        if pattern.match(ln):
            # This looks like a data line (starts with an integer and a comma)
            data_lines.append(ln.rstrip("\n"))
        else:
            # Stop reading when we hit a non-data line (end of the table)
            break

    return "\n".join(data_lines)


# ------------------ MAIN SCRIPT ------------------
def main():
    # ---- Argument parser ----
    parser = argparse.ArgumentParser(description="Compute mean DELTA TOTAL per run from Amber MMGBSA output.")
    parser.add_argument("infile", help="Path to MMGBSA output file")
    parser.add_argument("--block", type=int, default=100, help="Frames per run (default 100)")
    args = parser.parse_args()

    # ---- Verify file exists ----
    fpath = Path(args.infile)
    if not fpath.exists():
        print(f"❌ Input file not found: {args.infile}", file=sys.stderr)
        sys.exit(2)

    # ---- Read the entire file ----
    lines = fpath.read_text().splitlines()

    # ---- Locate the start of the DELTA Energy Terms section ----
    header_idx = find_header_index(lines)
    if header_idx == -1:
        print(f"❌ Could not find a line starting with '{HEADER_MARK}' in {args.infile}", file=sys.stderr)
        sys.exit(3)

    # ---- Extract the data block that follows the header ----
    block_text = read_block_after_header(lines, header_idx)
    if block_text is None:
        print("❌ No data found after header marker.", file=sys.stderr)
        sys.exit(4)

    # ---- Read only the two relevant columns: Frame # and DELTA TOTAL ----
    # Using pandas' usecols argument to read only what we need.
    df = pd.read_csv(io.StringIO(block_text), usecols=["Frame #", "DELTA TOTAL"])
    df.columns = ["Frame", "DELTA_TOTAL"]  # rename to simpler names

    # ---- Assign each frame to a 'run' based on the frame number ----
    # Frames 0–99 → run 0, 100–199 → run 1, etc.
    df["run"] = (df["Frame"] // args.block).astype(int)

    # ---- Compute the mean DELTA TOTAL for each run ----
    run_means = df.groupby("run")["DELTA_TOTAL"].mean().reset_index()
    run_means.rename(columns={"DELTA_TOTAL": "Mean_DELTA_TOTAL"}, inplace=True)

    # ---- Save results to a CSV file ----
    out_csv = f"DELTA_TOTAL_per_run_block{args.block}.csv"
    run_means.to_csv(out_csv, index=False)

    # ---- Print results to screen ----
    print(f"✅ Wrote per-run means to: {out_csv}\n")
    print(run_means.to_string(index=False))


# ---- Run the script ----
if __name__ == "__main__":
    main()

