#!/bin/bash

# Usage: ./pdbqt2pdb.sh input.pdbqt
# Output: input_model1.pdb, input_model2.pdb, ...

input="$1"
base=$(basename "$input" .pdbqt)

awk -v base="$base" '
    /^MODEL/ { model++; next }

    /^(ATOM|HETATM)/ {
        # Determine element symbol as first letter of atom name
        element = substr($3,1,1)

        if ($4 == "LIG") {
            # LIG atoms: residue number = 172
            formatted = sprintf("%-6s%5d %-4s %-3s %1s%4d    %8.3f%8.3f%8.3f %4.2f %5.2f      %1s    %1s",
                                $1, $2, $3, $4, "A", 172, $6, $7, $8, $9, $10, "A", element)
            lig_atoms[$2] = formatted
            lig_ids[++lig_count] = $2
        } else {
            # Residue atoms: keep original residue number ($6) but set last column
            formatted = sprintf("%-6s%5d %-4s %-3s %1s%4d    %8.3f%8.3f%8.3f %4.2f %5.2f      %1s    %1s",
                                $1, $2, $3, $4, "A", $6, $7, $8, $9, $10, $11, "A", element)
            res_atoms[++res_count] = formatted
        }
        next
    }

    /^ENDMDL/ {
        outfile = sprintf("%s_model%d.pdb", base, model)

        # sort LIG atoms by atom serial number
        asort(lig_ids, sorted)
        for (i=1; i<=lig_count; i++) {
            id = sorted[i]
            print lig_atoms[id] >> outfile
        }

        # then print residues in original order
        for (i=1; i<=res_count; i++) {
            print res_atoms[i] >> outfile
        }

        close(outfile)

        # cleanup
        delete lig_atoms
        delete lig_ids
        delete res_atoms
        lig_count = res_count = 0
    }
' "$input"

