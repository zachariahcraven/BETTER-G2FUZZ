#!/bin/bash
# Lists the phase B campaigns the analysis uses, one per line: "<name> <program> <arm> <rep>".
# Skips the damaged runs (*.damaged-*, see DRIFT.md 5.7). Program names may contain hyphens
# (gdk-pixbuf-pixdata), so the arm and rep are read from the end of the name.
# Usage: analysis/campaigns.sh [campaigns-dir]   (default: ../campaigns next to this script)
# Phase: G2F_PHASE=B (default) lists B-*; G2F_PHASE=C lists the phase C campaigns (C-*). The analysis scripts
# pass it through and write phase C into results/phase-C/.
E=${1:-$(cd "$(dirname "$0")/../campaigns" 2>/dev/null && pwd)}; P=${G2F_PHASE:-B}
[ -d "$E" ] || { echo "campaigns.sh: no campaigns folder: $E" >&2; exit 1; }
for d in "$E"/$P-*; do
  [ -e "$d" ] || continue
  n=$(basename "$d"); case $n in *.damaged-*) continue;; esac
  rep=${n##*-r}; rest=${n%-r*}; arm=${rest##*-}; prog=${rest#$P-}; prog=${prog%-$arm}
  echo "$n $prog $arm $rep"
done | sort -k2,2 -k4,4n -k3,3
