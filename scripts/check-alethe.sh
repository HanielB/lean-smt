#!/usr/bin/env bash
# Check an Alethe proof of an SMT-LIB problem's unsatisfiability from the command line.
#
# Usage: scripts/check-alethe.sh [--elaborate] <problem.smt2> <proof.alethe> [native] [lax] [term] [timings]
#
# --elaborate first runs the given proof through Carcara (as the `alethe` tactic does, with its
# default pipeline and core rules) and checks the elaborated result; use it when `<proof.alethe>`
# is a raw solver proof rather than one already elaborated by Carcara. Carcara is found through
# $CARCARA, or `carcara` in the PATH.
#
# The trailing words are the `#check_alethe` options (see README.md).

set -euo pipefail

elaborate=false
if [ "${1:-}" = "--elaborate" ]; then
  elaborate=true
  shift
fi

if [ $# -lt 2 ]; then
  echo "Usage: $(basename "$0") [--elaborate] <problem.smt2> <proof.alethe> [native] [lax] [term] [timings]" >&2
  exit 1
fi

smt2=$(realpath "$1")
alethe=$(realpath "$2")
shift 2
flags="$*"

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

if $elaborate; then
  carcara_exe="${CARCARA:-carcara}"
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
  alethe="$tmp/elaborated.alethe"
  printf '%s\n' "${out#*$'\n'}" > "$alethe"
fi

lean_file="$tmp/check.lean"
cat > "$lean_file" <<EOF
import Smt

#check_alethe "$smt2" "$alethe" $flags
EOF

cd "$repo_root"
exec lake env lean --plugin="$plugin" "$lean_file"
