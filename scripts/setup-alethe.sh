#!/usr/bin/env bash
# Set up everything `scripts/check-alethe.sh` needs: the Lean toolchain, the lean-smt build (and
# so the cvc5 parser plugin), and a Carcara binary of the revision this branch expects.
#
# Usage: scripts/setup-alethe.sh [options]
#
#   --no-mathlib          build without Mathlib, by taking lakefile.lean and lake-manifest.json
#                         from the `no_mathlib` branch and marking them skip-worktree so they are
#                         never committed (this is what the Alethe work uses; Mathlib is only
#                         needed for the Real reconstruction and its tests)
#   --carcara-src DIR     build Carcara from an existing checkout instead of cloning
#   --carcara-remote URL  clone from this remote          (default $CARCARA_REMOTE, else origin below)
#   --carcara-ref REF     check out this branch or commit (default $CARCARA_REF, else the
#                         revision this branch was developed against)
#   --skip-lean           do not touch the Lean side
#   --skip-carcara        do not build Carcara
#   -h, --help
#
# On success it prints the line to add to your shell profile so that check-alethe.sh finds
# Carcara, and runs a smoke test of both of that script's modes.

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

no_mathlib=false
skip_lean=false
skip_carcara=false
carcara_src=""
carcara_remote=${CARCARA_REMOTE:-https://github.com/hanielb/carcara.git}
carcara_ref=${CARCARA_REF:-4bd5e9a9}
prefix="$repo/.lake/alethe"

while [ $# -gt 0 ]; do
  case $1 in
    --no-mathlib) no_mathlib=true; shift ;;
    --carcara-src) carcara_src=$(cd "$2" && pwd); shift 2 ;;
    --carcara-remote) carcara_remote=$2; shift 2 ;;
    --carcara-ref) carcara_ref=$2; shift 2 ;;
    --skip-lean) skip_lean=true; shift ;;
    --skip-carcara) skip_carcara=true; shift ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
have() { command -v "$1" > /dev/null 2>&1; }

# ------------------------------------------------------------------ the Lean side
if ! $skip_lean; then
  say "Lean toolchain"
  if ! have elan; then
    cat >&2 <<'EOF'
error: `elan` is not on the PATH. Install it with

    curl https://elan.lean-lang.org/elan-init.sh -sSf | sh

and open a new shell, or install Lean $(cat lean-toolchain) by hand.
EOF
    exit 1
  fi
  toolchain=$(cat lean-toolchain)
  elan toolchain install "$toolchain" > /dev/null
  echo "using $toolchain"

  if $no_mathlib; then
    say "no_mathlib build configuration"
    # the branch lives on the upstream remote; add it if the clone does not have it
    remote=smite
    git remote get-url $remote > /dev/null 2>&1 \
      || remote=$(git remote | grep -m1 . || true)
    git ls-remote --heads "$remote" no_mathlib | grep -q no_mathlib \
      || { echo "error: no \`no_mathlib\` branch on remote '$remote'" >&2; exit 1; }
    git fetch -q "$remote" no_mathlib
    for f in lakefile.lean lake-manifest.json; do
      git show FETCH_HEAD:$f > "$f"
      # never commit these: they differ from the branch only in the build configuration
      git update-index --skip-worktree "$f"
    done
    echo "lakefile.lean and lake-manifest.json taken from $remote/no_mathlib, marked skip-worktree"
  fi

  say "building lean-smt (this fetches the dependencies and a prebuilt cvc5)"
  lake build
  plugin="$repo/.lake/packages/cvc5/.lake/build/lib/libcvc5_cvc5.so"
  [ -f "$plugin" ] || { echo "error: the cvc5 plugin was not built at $plugin" >&2; exit 1; }
  echo "cvc5 plugin: $plugin"
fi

# ------------------------------------------------------------------ Carcara
if ! $skip_carcara; then
  say "Carcara"
  if ! have cargo; then
    cat >&2 <<'EOF'
error: `cargo` is not on the PATH. Install Rust with

    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
EOF
    exit 1
  fi

  if [ -z "$carcara_src" ]; then
    carcara_src="$prefix/carcara"
    mkdir -p "$prefix"
    if [ -d "$carcara_src/.git" ]; then
      echo "reusing the checkout at $carcara_src"
      git -C "$carcara_src" fetch -q origin
    else
      echo "cloning $carcara_remote"
      git clone -q "$carcara_remote" "$carcara_src"
    fi
    git -C "$carcara_src" checkout -q "$carcara_ref" 2>/dev/null \
      || git -C "$carcara_src" checkout -q "origin/$carcara_ref" \
      || { echo "error: no such revision '$carcara_ref' on $carcara_remote" >&2; exit 1; }
  else
    echo "building from $carcara_src"
  fi
  echo "at $(git -C "$carcara_src" log --oneline -1)"

  ( cd "$carcara_src" && cargo build --release )
  mkdir -p "$prefix/bin"
  install -m 755 "$carcara_src/target/release/carcara" "$prefix/bin/carcara"
  echo "installed $("$prefix/bin/carcara" --version)"
fi

# ------------------------------------------------------------------ smoke test
say "smoke test"
export CARCARA="$prefix/bin/carcara"
[ -x "$CARCARA" ] || CARCARA=$(command -v carcara || true)

t=Test/Alethe/QF_LIA/bounded_farkas
if [ -f "$t.smt2" ]; then
  echo "-- checking an elaborated proof"
  ./scripts/check-alethe.sh "$t.smt2" "$t.alethe"
fi
if [ -n "${CARCARA:-}" ] && [ -x "$CARCARA" ]; then
  echo "-- checking through Carcara (--elaborate)"
  ./scripts/check-alethe.sh --elaborate "$t.smt2" "$t.alethe"
else
  echo "-- skipping the --elaborate mode: no Carcara binary"
fi

say "done"
if [ -x "$prefix/bin/carcara" ]; then
  cat <<EOF
Add this to your shell profile so that scripts/check-alethe.sh finds Carcara:

    export CARCARA=$prefix/bin/carcara

Then check a proof with

    scripts/check-alethe.sh problem.smt2 problem.alethe
    scripts/check-alethe.sh --elaborate problem.smt2 raw-solver-proof.alethe
EOF
fi
