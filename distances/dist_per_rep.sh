#!/usr/bin/env bash
# calc_stats.sh
# Calculates mean and SD for 2nd and 3rd columns of each file.

for f in "$@"; do
  echo "File: $f"
  awk '
  {
    c2 += $2; c3 += $3
    s2 += $2 * $2; s3 += $3 * $3
    n++
  }
  END {
    if (n > 1) {
      m2 = c2 / n
      m3 = c3 / n
      sd2 = sqrt((s2 - n * m2 * m2) / (n - 1))
      sd3 = sqrt((s3 - n * m3 * m3) / (n - 1))
      printf "  Column 2: mean = %.4f, sd = %.4f\n", m2, sd2
      printf "  Column 3: mean = %.4f, sd = %.4f\n", m3, sd3
    } else {
      print "  Not enough data"
    }
  }' "$f"
  echo
done
