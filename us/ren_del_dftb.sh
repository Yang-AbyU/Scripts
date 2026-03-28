#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

prefix="US"

if [[ "$#" -eq 0 ]]; then
    echo "Usage: $0 <number> [number ...]"
    exit 1
fi

for n in "$@"; do
    dir="${prefix}${n}"
    if [[ -d "$dir" ]]; then
        echo "Deleting $dir"
        rm -rf -- "$dir"
    else
        echo "Skipping $dir (not found)"
    fi
done

# Collect existing numbers
mapfile -t nums < <(
  for d in ${prefix}[0-9]*/; do
    d=${d%/}
    echo "${d#$prefix}"
  done | sort -n
)

# Separate low (<=10) and high (>=11)
low=()
high=()

for n in "${nums[@]}"; do
  if (( n <= 10 )); then
    low+=("$n")
  else
    high+=("$n")
  fi
done

# Find missing numbers between 1 and 10
missing=()
for ((i=1; i<=10; i++)); do
  if [[ ! " ${low[*]} " =~ " $i " ]]; then
    missing+=("$i")
  fi
done

# Map high numbers → missing gaps
declare -A map
for i in "${!missing[@]}"; do
  (( i < ${#high[@]} )) || break
  map["${high[$i]}"]="${missing[$i]}"
done

# First pass: move to temp names
for old in "${!map[@]}"; do
  mv "${prefix}${old}" "__tmp__${prefix}${map[$old]}"
done

# Second pass: finalize
for d in __tmp__${prefix}*; do
  mv "$d" "${d#__tmp__}"
done

# Step 1: collect directories with number ≥11
dirs=()
for d in ${prefix}[0-9]*/; do
    d=${d%/}
    num=${d#$prefix}
    (( num >= 11 )) && dirs+=("$d")
done

# Step 2: sort numerically by suffix
IFS=$'\n' sorted=($(for d in "${dirs[@]}"; do
    echo "$d"
done | sort -n -k1.3))
unset IFS

# Step 3: rename to temporary names to avoid collisions
next=11
for d in "${sorted[@]}"; do
    mv "$d" "__tmp__${prefix}${next}"
    ((next++))
done

# Step 4: finalize renames
for d in __tmp__${prefix}*; do
    mv "$d" "${d#__tmp__}"
done

