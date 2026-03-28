#!/bin/bash

input_file="$1"
tmp_file="$(mktemp)"

awk '
BEGIN { het_count=0 }
{
    record = substr($0, 1, 6)
    if (record == "ATOM  " && het_count < 49) {
        het_count++
        # Replace ATOM  (6 chars) with HETATM (6 chars), keeping exact width
        $0 = "HETATM" substr($0, 7)
    }
    print
}
' "$input_file" > "$tmp_file" && mv "$tmp_file" "$input_file"
