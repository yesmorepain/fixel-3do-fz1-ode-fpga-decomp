#!/bin/sh
# Timing sweep over tool settings only (yosys synth_ice40 options x nextpnr options x seeds); the HDL is not changed.
# Usage: [GOLDEN=1] [JOBS=4] [NAME=x] [YS="a|b"] [NS="c|d"] [SEEDS="1 2 3"] sh tools/build/sweep.sh  -> build/sweep[_golden]/results.tsv (fmax of the PLL clock, MHz)
# YS / NS: |-separated yosys / nextpnr option sets (defaults below; "-dff" fails: async-reset FFs).
# Estimates from nextpnr's u4k timing model only. NOT TESTED ON HARDWARE.
cd "$(dirname "$0")/../.."
S=build/sweep${GOLDEN:+_golden}${NAME:+_$NAME}; rm -rf $S; mkdir -p $S; : > $S/jobs
YS=${YS-"|-device u|-device u -nocarry"}
NS=${NS-"|--placer sa|--opt-timing|--router router2 --tmg-ripup"}
IFS='|'; set -f
for y in $YS; do
  for n in $NS; do
    unset IFS
    for seed in ${SEEDS:-1 2 3}; do
      printf '%s|%s --seed %s\n' "$y" "$n" "$seed" >> $S/jobs
    done
    IFS='|'
  done
done
unset IFS; set +f
k=0
while IFS='|' read -r y n; do
  k=$((k + 1))
  printf '%s\t%s\t%s\n' "$k" "$y" "$n"
done < $S/jobs > $S/index.tsv
cut -f1 $S/index.tsv | xargs -P ${JOBS:-4} -I{} sh -c '
  line=$(sed -n "{}p" '"$S"'/index.tsv); y=$(echo "$line" | cut -f2); n=$(echo "$line" | cut -f3)
  OUT='"$S"'/run{} YOSYS_ARGS="$y" NEXTPNR_ARGS="$n" sh tools/build/build.sh >/dev/null 2>&1
  f=$(grep -E "Max frequency for clock +.(clk|n5).:" '"$S"'/run{}/nextpnr.log | tail -1 | sed -E "s/.*: ([0-9.]+) MHz.*/\1/")
  lc=$(grep -oE "ICESTORM_LC: +[0-9]+" '"$S"'/run{}/nextpnr.log | tail -1 | grep -oE "[0-9]+$")
  printf "%s\t%s\t%s\t%s\n" "${f:-FAIL}" "$lc" "$y" "$n"'  > $S/results.tsv
sort -rn $S/results.tsv | head -8
