#!/bin/bash

input_file="$1"
tmp_file="$(mktemp)"

awk 'NR <= 50 && substr($0, 1, 6) == "ATOM  " && substr($0, 18, 3) == "LIG" {
    atom = substr($0, 13, 4)
    gsub(/ /, "", atom)
    count[atom]++
    new_atom = atom count[atom]
    formatted_atom = sprintf("%4s", new_atom)
    $0 = substr($0, 1, 12) formatted_atom substr($0, 17)
    print
    next
}
{ print }' "$input_file" > "$tmp_file" && mv "$tmp_file" "$input_file"
