#!/usr/bin/env bash
# Check an Alethe proof of an SMT-LIB problem's unsatisfiability from the command line.
#
# Usage: scripts/check-alethe.sh [--elaborate] [--csv <dir>] [--mem <MB>] <problem.smt2>
#            <proof.alethe> [native] [lax] [term] [timings]
#
# The dashed options may appear anywhere among the arguments.
#
# --csv <dir> writes <dir>/runs.csv and <dir>/steps.csv: what every step cost, in the format
# carcara's `bench --dump-to-csv` produces. `scripts/rule-boxplots.py <dir> …` plots them.
#
# --elaborate first runs the given proof through Carcara (as the `alethe` tactic does, with its
# default pipeline and core rules) and checks the elaborated result; use it when `<proof.alethe>`
# is a raw solver proof rather than one already elaborated by Carcara. Carcara is found through
# $CARCARA, or `carcara` in the PATH.
#
# The trailing words are the `#check_alethe` options (see README.md).
#
# The checker runs under a heap cap, so that a large proof cannot exhaust the machine:
# --mem <MB>, or $LEAN_MEM, default 8000; either as 0 disables the cap.
#
# The wall-clock time is reported at the end, as a `time:` line on stderr, split between the
# Carcara elaboration (with --elaborate) and the Lean check (which includes starting Lean and
# importing Smt).

set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [--elaborate] [--csv <dir>] [--mem <MB>] <problem.smt2> <proof.alethe> [native] [lax] [term] [timings]" >&2
}

# a heap cap in MB, or 0 for none
check_mem() {
  case "$1" in
    ''|*[!0-9]*) echo "error: --mem takes a size in MB, or 0 for no cap: $1" >&2; usage; exit 1 ;;
  esac
}

# The dashed options are taken from anywhere in the line, not only before the files: written
# after them they would end up among the `#check_alethe` words, where Lean reads `--` as the
# start of a comment and the option would be silently dropped.
elaborate=false
csv=""
lean_mem=${LEAN_MEM:-8000}
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --elaborate) elaborate=true; shift ;;
    --csv)
      if [ $# -lt 2 ]; then echo "error: --csv needs a directory" >&2; usage; exit 1; fi
      csv=$(realpath -m "$2"); shift 2 ;;
    --csv=*) csv=$(realpath -m "${1#--csv=}"); shift ;;
    --mem)
      if [ $# -lt 2 ]; then echo "error: --mem needs a size in MB" >&2; usage; exit 1; fi
      check_mem "$2"; lean_mem=$2; shift 2 ;;
    --mem=*) check_mem "${1#--mem=}"; lean_mem=${1#--mem=}; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; args+=("$@"); break ;;
    -*) echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

if [ $# -lt 2 ]; then
  usage
  exit 1
fi

smt2=$(realpath "$1")
alethe=$(realpath "$2")
given_alethe=$alethe   # what --csv should name, even when --elaborate checks a derived file
shift 2
flags="$*"

# the same reason: a word `#check_alethe` does not know is not an error to Lean, it is a comment
for w in $flags; do
  case "$w" in
    native|lax|term|timings) ;;
    *) echo "error: unknown option: $w (expected native, lax, term or timings)" >&2; usage; exit 1 ;;
  esac
done

for f in "$smt2" "$alethe"; do
  if [ ! -f "$f" ]; then
    echo "error: no such file: $f" >&2
    exit 1
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
plugin="$repo_root/.lake/packages/cvc5/.lake/build/lib/libcvc5_cvc5.so"
if [ ! -f "$plugin" ]; then
  echo "error: cvc5 plugin not found at $plugin (run 'lake build' in $repo_root first)" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

now() { printf '%s' "$EPOCHREALTIME"; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.3fs", b - a }'; }

carcara_time=""
if $elaborate; then
  carcara_exe="${CARCARA:-carcara}"
  t0=$(now)
  rare_file="$repo_root/Smt/Alethe/Rare/rewrites.eo"
  pipeline=(polyeq local core-simp-rare budget)
  core_rules=(ite_simplify eq_simplify not_simplify implies_simplify equiv_simplify bool_simplify
              comp_simplify and_simplify or_simplify prod_simplify sum_simplify minus_simplify
              unary_minus_simplify div_simplify ac_simp aci_simp absorb)
  if ! out=$("$carcara_exe" elaborate --expand-let-bindings --allow-int-real-subtyping \
       --rare-file "$rare_file" --pipeline "${pipeline[@]}" --core-rules "${core_rules[@]}" \
       -- "$alethe" "$smt2" 2>"$tmp/carcara.stderr"); then
    echo "error: could not run Carcara (\`$carcara_exe\`); set \$CARCARA or put it in the PATH" >&2
    cat "$tmp/carcara.stderr" >&2
    exit 1
  fi
  verdict="${out%%$'\n'*}"
  if [ "$verdict" != valid ] && [ "$verdict" != holey ]; then
    echo "error: Carcara does not accept the proof: $verdict" >&2
    cat "$tmp/carcara.stderr" >&2
    exit 1
  fi
  carcara_time=$(secs "$t0" "$(now)")
  alethe="$tmp/$(basename "$alethe").elaborated"
  printf '%s\n' "${out#*$'\n'}" > "$alethe"
fi

lean_file="$tmp/check.lean"
csv_clause=""
if [ -n "$csv" ]; then
  csv_clause="csv \"$csv\""
fi
cat > "$lean_file" <<EOF
import Smt

#check_alethe "$smt2" "$alethe" $flags $csv_clause
EOF

cd "$repo_root"
t0=$(now)
status=0
# Cap the checker's heap. A large proof can otherwise take the whole machine down: the kernel
# holds the step's proof term, and a single resolution over a few hundred premises has been seen
# to need tens of gigabytes. Set by --mem or $LEAN_MEM above; 0 disables the cap.
mem_flag=()
[ "$lean_mem" != 0 ] && mem_flag=(-M "$lean_mem")
lake env lean "${mem_flag[@]}" --plugin="$plugin" "$lean_file" || status=$?
lean_time=$(secs "$t0" "$(now)")

# The proof the checker was handed under --elaborate is a temp file, and it is that path the
# checker records. Name the run after the proof this script was given instead, which is the one
# the row is about — and the only name that tells two benchmarks' rows apart.
if [ -n "$csv" ] && [ "$alethe" != "$given_alethe" ] && [ -s "$csv/runs.csv" ]; then
  awk -v p="$given_alethe" 'BEGIN { FS = OFS = "," } NR == 2 { $1 = p } { print }' \
      "$csv/runs.csv" > "$csv/runs.csv.new" && mv "$csv/runs.csv.new" "$csv/runs.csv"
fi

if [ -n "$carcara_time" ]; then
  echo "time: carcara ${carcara_time}, lean ${lean_time}" >&2
else
  echo "time: lean ${lean_time}" >&2
fi
exit $status
