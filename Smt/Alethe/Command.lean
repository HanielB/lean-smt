/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

module

public import Smt.Alethe.Frontend
public meta import Smt.Alethe.Frontend

public meta section

namespace Smt.Alethe

open Lean Elab Command

/-- `#check_alethe "problem.smt2" "proof.alethe"` checks an Alethe proof of the unsatisfiability
    of an SMT-LIB problem: every step is reconstructed and checked by the kernel, and the
    command reports how many steps were checked and how many had to be trusted. Paths are
    relative to the working directory. Options: `native` allows native evaluation, `lax` accepts
    assumptions that are not assertions of the problem, `timings` reports the time spent in each
    phase, `csv "<dir>"` writes `<dir>/runs.csv` and `<dir>/steps.csv` — what every step cost, in
    the format carcara's `bench --dump-to-csv` produces. -/
syntax (name := checkAletheCmd) "#check_alethe " str str (&"native")? (&"lax")? (&"term")? (&"timings")? (&"csv " str)? : command

@[command_elab checkAletheCmd] def elabCheckAlethe : CommandElab := fun stx => do
  let some problem := stx[1].isStrLit? | throwError "expected a string"
  let some proof := stx[2].isStrLit? | throwError "expected a string"
  let native := !stx[3].isNone
  let lax := !stx[4].isNone
  let term := !stx[5].isNone
  let timings := !stx[6].isNone
  let csv := if stx[7].isNone then none else stx[7][1].isStrLit?.map System.FilePath.mk
  liftTermElabM do
    let t₀ ← IO.monoMsNow
    let r ← checkAlethe problem proof native lax term csv
    let t₁ ← IO.monoMsNow
    let mut msg := m!"{r.verdict}: {r.stats.summary}"
    for (id, rule, m) in r.stats.failures do
      msg := msg ++ m!"\n  {id} ({rule}): {m}"
    if timings then
      for (l, ms) in r.timings do
        msg := msg ++ m!"\n[time] {l}: {ms} ms"
      msg := msg ++ m!"\n[time] total: {t₁ - t₀} ms"
    if let some dir := csv then
      msg := msg ++ m!"\n[csv] {dir}/runs.csv, {dir}/steps.csv: {r.stats.steps.size} steps"
    logInfo msg
    trace[smt.alethe] "statement: {r.type}"

end Smt.Alethe
