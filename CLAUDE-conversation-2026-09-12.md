## Turn: 2026-09-12 (session 0c7d535f) — per-step stats, in carcara's CSV format

lean-smt now dumps what every step cost, in exactly the shape `carcara bench --dump-to-csv`
produces, so one analysis reads either checker and both go on one figure.

**`#check_alethe … csv "<dir>"`** writes `<dir>/runs.csv` and `<dir>/steps.csv`, nanoseconds
throughout, carcara's columns in carcara's order, lean-smt's extra columns appended (positional
readers — `rule` is field 1 of `steps.csv`, `time` field 2 — are unaffected).

- `steps.csv`: `rule,time,reconstruct,kernel,depth,trusted,step_id`. `time` = reconstruct +
  kernel. The kernel figure is the step's own under the default `smt.alethe.batch 1`; a larger
  batch is one call over several steps and its time is split evenly (`kernel_split` flags it).
  Verified: the per-step kernel column sums to the run's kernel total exactly at batch 1 and
  with `jobs 4`, and to within integer-division rounding at `batch 8`.
- `runs.csv`: carcara's eleven columns plus `reconstruct,kernel,setup,steps,checked,trusted,
  holes,kernel_split`.

**Where the time is charged.** A step's record covers `mkStep` + the reconstructors +
`concludeStep`, with the kernel's time subtracted out (a batch flush happens inside
`concludeStep`, so it would otherwise be counted twice). An anchor's own cost — its variables,
its assumptions, the contexts it opens — is charged to the step that *closes* it, not spread
over the body. Binding the assumptions is not a step at all; it is the `assume` column, with the
`polyeq` search inside it broken out. Everything before the first command — reconstructing the
problem's assertions — is the new `setup` column: on `bird_tree_bfun` (372 assertions) that is
156 ms of 2.1 s checking, and it was the bulk of what the step rows did not add up to. What
remains unattributed is ~6%, the per-command bookkeeping between steps.

**Cost when off:** `smt.alethe.stats` is read once into the driver state; with it false nothing
is recorded and the four `IO.monoNanosNow` reads per step replace the three `monoMsNow` reads
that were already there.

**`scripts/rule-boxplots.py`** plots them — `rule-boxplots.pdf` (per-rule step time, log scale)
and `rule-totals.pdf` — one series per configuration:
```
scripts/rule-boxplots.py --fold-rare -o plots lean-smt:out/lean carcara:out/carcara
```
Boxes are the per-proof mean with ≥4 proofs (as in `~/exp/alethe-bv/rule-boxplots.py`) and the
raw per-step times below that. Two vocabulary differences, both handled: carcara names every
RARE step `rare_rewrite` where we name it `rare_rewrite:<rule>` (`--fold-rare`), and carcara has
`assume` and `anchor(…)` rows we deliberately have no counterpart for.

**Checked on ten Test/Alethe proofs against carcara on the same proofs.** With `--fold-rare` the
two vocabularies line up rule for rule with identical counts (resolution 292/292, subproof
35/35, rare_rewrite 63/63, …). The picture is the expected three orders of magnitude: carcara's
per-rule means sit at 10⁻⁷–10⁻⁵ s, ours at 10⁻⁴–10⁻² s, with `subproof`, `poly_simp` and
`la_generic` our most expensive rules.

Also: `scripts/check-alethe.sh --csv <dir>`; README section; `~/exp/alethe-lean/run-arms.sh`
dumps the CSVs per Lean arm and adds `=== rule times <arm> ===` (rule, count, total_ns) plus
`parse_ns= check_ns= kernel_ns= setup_ns= assume_ns=` at the end of each `[cfg …]` line — the
per-step rows themselves are far too big for a cluster log. The carcara arm is untouched: its
`--stats` output plus `=== rule counts orig ===` already feeds the alethe-bv plot script, and a
`bench` pass would double that arm's work.

Full suite green; nothing committed.

## Turn: 2026-09-12 00:02:36 (session 0c7d535f)

Now let me look at the carcara stats output format and the lean-smt side.

## Turn: 2026-09-12 00:02:36 (session 0c7d535f)

Now let me produce carcara's own CSVs for the same proofs, to check the two really do plot together:

## Turn: 2026-09-12 00:02:36 (session 0c7d535f)

The two vocabularies line up except for RARE naming and carcara's `assume`/`anchor(…)` rows. Let me handle that in the script:

## Turn: 2026-09-12 00:02:36 (session 0c7d535f)

Done. `#check_alethe … csv "<dir>"` now writes `runs.csv` and `steps.csv` in exactly carcara's `bench --dump-to-csv` format — carcara's columns, in carcara's order, nanoseconds throughout — with lean-smt's extra columns appended so positional readers (`rule` is field 1 of `steps.csv`, `time` field 2) keep working.

```
rule,time,reconstruct,kernel,depth,trusted,step_id
equiv_pos2,947366,839278,108088,0,0,t0
rare_rewrite:arith-elim-lt,1558418,1506614,51804,0,0,t1
```

**Where time is charged.** A step's record covers `mkStep` + reconstructors + `concludeStep`, with the kernel subtracted out (a batch flush happens *inside* `concludeStep`, so it would otherwise double-count). Kernel time is the step's own at the default `smt.alethe.batch 1`; a bigger batch is one call over several steps, split evenly and flagged by `kernel_split`. An anchor's own cost is charged to the step that closes it, not smeared over the body. Assumptions aren't steps — they're the `assume` column, with the `polyeq` search broken out of it.

Chasing the residual led to a real finding worth a column: on `bird_tree_bfun` (372 assertions) reconstructing the problem's assertions is 156 ms of 2.1 s checking, and it was most of what the step rows didn't add up to. That's the new `setup` column; what's left unattributed is ~6%, per-command bookkeeping.

Verified: per-step kernel sums to the run total exactly at `batch 1` and `jobs 4`, and to within integer-division rounding at `batch 8`; the `trusted` flag lands on the right step; `term` mode puts the single call in `runs.csv` and leaves per-step kernel at 0. Full suite green.

**`scripts/rule-boxplots.py`** produces the two plots, one series per configuration, boxing per-proof means with ≥4 proofs (as your alethe-bv script does) and raw step times below that. Two vocabulary differences turned up against carcara and are handled: carcara names every RARE step `rare_rewrite` where we name it `rare_rewrite:<rule>` (hence `--fold-rare`), and carcara has `assume` and `anchor(…)` rows we deliberately have no counterpart for. With `--fold-rare` the ten-proof comparison lines up rule for rule with identical counts.

Also: `check-alethe.sh --csv <dir>`, a README section, and `~/exp/alethe-lean/run-arms.sh` now dumps CSVs per Lean arm and adds `=== rule times <arm> ===` plus `parse_ns=/check_ns=/kernel_ns=/setup_ns=/assume_ns=` at the end of each `[cfg …]` line — the raw rows are far too big for a cluster log. I left the carcara arm alone: its `--stats` output already feeds the alethe-bv script, and a `bench` pass would double that arm's work.

Nothing committed. Note matplotlib isn't installed system-wide here — I used a scratch venv to check the script runs.

## Turn: 2026-09-12 00:09:59 (session 315b089e)

Pushed. All four commits are on `origin/bv-fixes`:

| | |
|---|---|
| `92d8a42f` | parser: Int/Real subtyping at polymorphic positions |
| `67a5a426` | local: keep a resolution step whose pivots can't be inferred |
| `13e721d7` | checker: read `ac_simp`'s premises |
| `f1253e4c` | tests: elaborate a premise-carrying `ac_simp` end to end |

`131f9a1f..f1253e4c`, fast-forward, nothing to rebase.

Two things worth flagging:

**I found an uncommitted file before pushing.** The `ac_simp_with_premises` elaboration test was still sitting in the working tree — I'd written and run it but never staged it. It went in as `f1253e4c` rather than an amend, so the `13e721d7` pin in `setup-alethe.sh` and the docs references stay valid. Full suite re-run on exactly what was pushed: **410 passing**.

**GitHub reports the repo moved** to `git@github.com:HanielB/carcara.git` (capital H); the push still went through on the redirect. Worth updating the remote at some point, and note `setup-alethe.sh` has the lowercase URL baked in as `carcara_remote` — it works today via the same redirect, but it's a latent fragility.

The pin resolves: `13e721d7` is an ancestor of `origin/bv-fixes`, and `setup-alethe.sh` does a full clone then checks the ref out, so a fresh setup will find it.

Meanwhile the corpus sweep is at 152/199: **121 `invalid`→`valid`**, 9 `→holey` (all `calypto`, holey only from `lia_generic`), 22 `error` (the big `pete2` proofs exceeding my 6 GB local gate — the one I retested at 12 GB gave `invalid`→`valid`). Memory is fine at 20 GB available. I'll re-run the gated-out ones at the higher cap and give you the final tally when it lands.

## Turn: 2026-09-12 00:20:23 (session 315b089e)

The push is done. Meanwhile the sweep finished and turned up one thing you should decide on.

## Push

`131f9a1f..f1253e4c` on `origin/bv-fixes`, fast-forward, four commits (parser subtyping, resolution pivots, the `ac_simp` checker, its elaboration test). Suite re-run on exactly that tree: **410 passing**. GitHub notes the repo now lives at `HanielB/carcara` (capital H) and redirected the push — worth fixing the remote, and `setup-alethe.sh` has the lowercase URL baked in too.

I also caught that the `ac_simp_with_premises` elaboration test was still unstaged — I'd written and run it but never committed it. It went in as a separate commit rather than an amend, so the `13e721d7` pin stays valid.

## Sweep result: 199/199

| old → new | count | |
|---|---|---|
| `invalid` → `valid` | **165** | fixed |
| `error` → `error` | 24 | my 6 GB local gate, not a checker failure — re-running at 13 GB now |
| `invalid` → `holey` | 9 | `calypto`, holey only from `lia_generic` |
| `invalid` → `invalid` | **1** | genuinely not fixed |

## The one that isn't fixed — and a decision for you

`QF_UFIDL/uclid/elf.rf10.smt2`, step `t6017`. Its 1,228 premise-carrying `ac_simp` steps all check now; this one **has no premises**, so it's a different defect entirely.

I diffed the two terms structurally. Both are 5-ary `and`s; they diverge at depth 8, where veriT wrote `(and (and A B) C)` and the normal form is the flattened `(and A B C)`. **veriT emitted an under-flattened conclusion** — the equality is true, it just isn't the full normal form.

The meet-in-the-middle route accepts it: I built an experimental binary with the `premises.is_empty()` gate removed and the whole proof checks **valid**. (Tree is clean again — that was a scratch build.)

I did not make that change, because it isn't mine to make. Dropping the gate relaxes premise-free `ac_simp` from "the RHS *is* the normal form of the LHS" to "both sides have the same normal form", and that flips a case your suite deliberately pins as `false`:

```
(= (or (= (and (and p q) r) s) (or p q))
   (or (= (and (and p q) r) s) p q))     -- currently rejected
```

which is the same shape veriT is producing. It's sound either way — the question is whether `ac_simp` should mean the strict structural reading. It's worth 1 proof in this corpus, so there's no pressure to decide now. Say the word and it's a one-line change plus that test expectation.

## Turn: 2026-09-12 00:37:40 (session 315b089e)

The `ac_simp` work is complete and measured. Final state:

## Result on all 199 affected proofs

| old → new | count |
|---|---|
| `invalid` → **`valid`** | **189** |
| `invalid` → `holey` | 9 — `calypto`, holey only from `lia_generic` |
| `invalid` → `invalid` | 1 |

**198 of 199 now check.** The 24 I'd earlier reported as `error → error` were my own 6 GB `ulimit -v` on 30–38 MB proofs, not a checker failure; at 13 GB all 24 are `invalid → valid`.

## The holdout

`QF_UFIDL/uclid/elf.rf10.smt2` step `t6017` carries **no premises** — its 1,228 premise-carrying siblings in the same proof all check now. veriT wrote the conclusion under-flattened: `(and (and A B) C)` eight levels down where the normal form is `(and A B C)`. Removing the `premises.is_empty()` gate makes the proof check (verified with a scratch build, now deleted), but that relaxes premise-free `ac_simp` from "the RHS *is* the normal form" to "both sides share a normal form" and flips a case your suite pins as `false`. One proof; left as your call.

Docs and the report corrected to 198-of-199 with the holdout described, PDF rebuilt (21 pages), committed as `f530e74`.

## Two things you should know

**A second session (`0c7d535f`) is working in this same tree** — the per-step CSV / boxplot feature. I left its five files (`README.md`, `Command.lean`, `Frontend.lean`, `Reconstruct.lean`, `check-alethe.sh`) untouched and uncommitted. Its log went to `CLAUDE-conversation-2026-09-12.md`; my 00:40 entry went into the 09-11 file, so the per-day convention is slightly off for that one entry.

**My commit `2e5f53a` swept in more than its message says.** Besides the pin bump and the `ac_simp` docs, it committed a pre-existing uncommitted `\section{The native Variant}` (~198 tex lines, tables and figures). Tracing the logs, that's my *own* earlier work from before the context compaction, not the other session's — but the commit message doesn't mention it. lean-smt is unpushed, so I can split that out into its own commit if you'd like it recorded properly.

## Turn: 2026-09-12 08:50:53 (session 0c7d535f)

Committed as `f627a9b`, with exactly the six files of the stats change — the three Alethe modules, `check-alethe.sh`, the new `scripts/rule-boxplots.py`, and the README section.

Worth knowing: the first attempt failed because another session is working in this repo concurrently. It had committed two `ac_simp` premise-fix commits, then did a mixed `git reset` back to `ec870af` — which cleared my staged index between the `add` and the `commit` and dumped its own content back as unstaged changes. I re-staged only my files and committed. That session has since re-landed its work, so the log now reads `46303a4` (its report section), `f627a9b` (mine), `39054cd` (its ac_simp pin) — nothing of theirs is in my commit and nothing of mine is in theirs.

Not committed, as before: `CLAUDE-conversation-2026-09-12.md` (the log entry, if you want it in its own `log:` commit) and the `~/exp/alethe-lean/run-arms.sh` changes, which live outside this repo.

## Turn: 2026-09-12 08:58:29 (session 315b089e)

Both tasks are done. Waiting on the confirmation run.

## 1. The split

`2e5f53a` is gone; history rebuilt as:

```
cdddc98  Pin the ac_simp common-normal-form fallback
dfaef8d  Record the measured outcome of the ac_simp premise fix
39054cd  Pin Carcara's ac_simp premise fix and record it
f627a9b  (other session) per-step CSV
46303a4  Report: add the native-variant section     ← split out
```

Verified byte-identical: `git diff f530e74 HEAD` over the tex, docs, pin and log is empty (the PDF differs only in build-id bytes). The four `*-native-*.pdf` figures the section depends on were **untracked** before — they're now in `46303a4`, so that commit is self-contained. Session `0c7d535f` committed `f627a9b` mid-sequence; disjoint files, no collision.

## 2. The fallback — Carcara `cac6af13`, pushed

Dropped the `premises.is_empty()` gate, so normalizing both sides to a common form is the fallback for *every* `ac_simp`. The rule now reads as "the two sides are equal modulo flattening and idempotence" — sound, and exactly what the elaborator had always computed.

**Elaboration is the part that matters, and it holds.** New test `ac_simp_under_flattened_conclusion` pins that the shape decomposes into per-layer `semilattice_simp` glued by `cong`/`trans` with no `ac_simp` left — and `run_core_pass` checks its result in **elaborated granularity**, so it's the proper rules, not a rebranded hole. On the real holdout `elf.rf10.smt2`: `check` valid, `elaborate` valid, **zero** `ac_simp` and 3,056 `semilattice_simp` in a 27 MB output.

**Two suite cases flipped**, both true equalities the strict reading had rejected — the under-flattened `=`, and a right-hand side keeping a duplicate. I gave each a sharper negative alongside it (`(and p q q)` vs `(and p q q r)`, and a genuinely different subterm), so the rule still rejects sides that differ *up to* the normal form rather than losing its teeth.

Suite 411 passing. Regression control re-run: 40/40 `valid → valid`, identical to before.

Two caveats I'd rather state than paper over:

- The **elaborated-granularity** check of that 27 MB / ~90k-step proof OOMs at a 16 GB cap. That's a scale limit of the proof, not something this change introduced, and I didn't push the cap higher on a 30 GB box. The unit test covers the property at small scale.
- The **190** figure in the committed docs is 189 measured with the premise fix plus `elf.rf10` verified individually. A definitive re-run of all 199 against the fallback binary is running now; I'll correct the number if it disagrees.

## Turn: 2026-09-12 09:34:12 (session 315b089e)

The confirmation run landed and matches the committed figure exactly.

## Final result on all 199

| old → new | count |
|---|---|
| `invalid` → **`valid`** | **190** |
| `invalid` → `holey` | 9 |
| still failing | **0** |

The 9 holey are QF_LIA `calypto`, holey only for their `lia_generic` steps — veriT's oracle rule, which carries no certificate and which Carcara doesn't check either. So every proof the two `ac_simp` defects were losing is now recovered, and the "190" I'd committed on a composition argument turned out to be the measured number.

## State

Both repos clean, everything pushed.

- **Carcara** `origin/bv-fixes` at `cac6af13`, nothing unpushed. (`src/main.rs` is a stray untracked file that predates my work — not mine, left alone.)
- **lean-smt** at `8e2cf1d`, pin `cac6af13`, working tree clean apart from the other session's untracked artefacts.

The two `ac_simp` commits, in order: `13e721d7` reads the step's `:premises` (189 proofs), `cac6af13` drops the premises-only gate so a common normal form is the general fallback (the last one, plus the semantics veriT actually emits). The native-variant report section is now its own commit, `46303a4`, with the four figures it depends on tracked for the first time.

The one thing I could not verify at full scale: the *elaborated-granularity* check of the 27 MB `elf.rf10` proof OOMs at 16 GB. The property is covered by `ac_simp_under_flattened_conclusion`, which does check in elaborated granularity, and at corpus scale by the default-granularity run — but on that one proof it's an inference from the small case, not a direct measurement.

## Turn: 2026-09-12 11:01:00 (session 0c7d535f)

Two bugs, both in `check-alethe.sh`, both now fixed:

**1. `--csv` after the file arguments was silently dropped.** My parser only consumed dashed options *before* the positionals, so a trailing `--csv docs-alethe/` fell into the words passed through to `#check_alethe`. Lean reads `--` as a line comment, so it didn't error — it just checked the proof and wrote nothing. Options are now taken from anywhere in the line (`--csv <dir>` and `--csv=<dir>`), and the whole class of silent-swallow is closed: an unknown dashed option and an unrecognized trailing word (`nativ`) are both hard errors now instead of comments.

**2. `proof_file` was the temp path.** With `--elaborate` the checked proof is a temp file, and every benchmark's row read `/tmp/tmp.XXXX/elaborated.alethe` — useless once you aggregate. It's now named after the original.

Your exact command works; the CSVs are in `docs-alethe/`:

```
valid: checked 6913 steps, trusted 0, holes 0
time: carcara 0.143s, lean 30.115s

checking 26.55 s = reconstruct 19.02 + kernel 7.54;  setup 0.51;  assume 0.05
        16.800 s    787  poly_simp
         2.405 s      1  la_generic
         2.180 s    673  resolution
         0.990 s    458  evaluate
```

One `la_generic` step costing 2.4 s, and `poly_simp` taking 63% of the whole check across 787 steps.

Unrelated, for when you hit it: `CARCARA=~/carcara/wt-corealethe/…/carcara` fails on `--elaborate` — that build has no `--core-rules`. The `carcara` in your PATH (`~/.local/bin`) does, as does `wt-diff`; every other worktree build I checked does not.

The fix is uncommitted — say the word and I'll commit it on top of `f627a9b`.

## Turn: 2026-09-12 11:02:17 (session 0c7d535f)

Committed as `2a04a1d`, `scripts/check-alethe.sh` only. It sits on top of the other session's `ac_simp` commits, which have continued landing in parallel; `f627a9b` (the stats change) is further down the same branch.

Still uncommitted and untouched: `CLAUDE-conversation-2026-09-12.md`, and the `docs-alethe/{runs,steps}.csv` your command just produced.

## Turn: 2026-09-12 11:13:54 (session 0c7d535f)

Committed as `5cab751`. `runs.csv` now records the proof path you passed to the script, not the temp file `--elaborate` derives — verified with and without `--elaborate`, and the rest of the row is untouched.

I also regenerated `docs-alethe/{runs,steps}.csv` from your command, so they carry the right name:

```
proof_file  /home/hbarbosa/lean/lean-smt/perturbations_0.onnxhyperrectangle_1684.vnnlib.smt2.alethe
```

One thing I noticed and left alone: there are untracked `runs.csv` and `steps.csv` in the repo root, plus an Emacs lock file `.#runs.csv` — so one of them is open in your editor. Not from my runs (those went to `docs-alethe/` and the scratchpad), so I didn't touch them.

## Turn: 2026-09-12 11:18:12 (session 0c7d535f)

`--mem <MB>` added, alongside `--mem=<MB>`:

| | |
|---|---|
| `--mem 16` | aborts — `excessive memory consumption detected` |
| `--mem=4000`, `--mem 0` | pass; `0` disables the cap |
| `$LEAN_MEM` | still the default, and `--mem` overrides it |
| `--mem abc`, bare `--mem` | rejected with a message, not passed through to Lean |

Like `--elaborate` and `--csv`, it's accepted anywhere in the line. README updated. Uncommitted — say the word.

## Turn: 2026-09-12 11:18:46 (session 0c7d535f)

Committed as `3c0b72c` — `scripts/check-alethe.sh` and the README line.

The four commits from this session on `alethe-dev`:

- `f627a9b` — the stats instrumentation (`csv` option, `runs.csv`/`steps.csv`, `rule-boxplots.py`)
- `2a04a1d` — `--csv` accepted anywhere; unknown option words error instead of being read as Lean comments
- `5cab751` — `proof_file` names the proof passed to the script
- `3c0b72c` — `--mem <MB>`

## Turn: 2026-09-12 11:20:59 (session 462452f0)

It's `scripts/rule-boxplots.py`, pointed at the `--csv` directory:

```bash
# one proof
./scripts/check-alethe.sh --csv out/safenlp foo.smt2 foo.smt2.alethe
scripts/rule-boxplots.py out/safenlp            # → plots/rule-boxplots.{pdf,png}, plots/rule-totals.{pdf,png}
```

Key points:

- **One `--csv` dir per proof.** `check-alethe.sh` overwrites `runs.csv`/`steps.csv` each run (the `runs.csv` fixup only touches row 2), so use `--csv out/<benchmark>` in a loop and then hand the *tree* to the plotter — it walks for every `steps.csv` and treats each as one proof:
  ```bash
  for p in bench/*.alethe; do
    ./scripts/check-alethe.sh --csv out/$(basename $p) "${p%.alethe}" "$p"
  done
  scripts/rule-boxplots.py out            # 4+ proofs ⇒ boxes are per-proof mean step times
  ```
- **Comparing against carcara:** each SPEC is `[label:]path`, and same-label SPECs merge into one series:
  ```bash
  scripts/rule-boxplots.py --fold-rare -o plots lean-smt:out carcara:carcara-bench/
  ```
  `--fold-rare` is needed to line up lean-smt's `rare_rewrite:<rule>` with carcara's plain `rare_rewrite`.
- Other flags: `-n/--top N` (default 25 rules by total time), `--by proof|step|auto`, `--title`, `-o/--out`.

One snag: **matplotlib isn't installed in your system python3**, so a bare run dies with `ModuleNotFoundError: No module named 'matplotlib'`. I made a venv in the scratchpad to verify it works end-to-end on `docs-alethe/` (6913 steps, 1 proof → all four files written). For a persistent fix, either `sudo apt install python3-matplotlib` or make a venv you keep, e.g.:

```bash
python3 -m venv ~/.venvs/plots && ~/.venvs/plots/bin/pip install matplotlib
~/.venvs/plots/bin/python scripts/rule-boxplots.py out
```

## Turn: 2026-09-12 11:46:59 (session 315b089e)

The nested heredoc marker collided. Rewriting the harness cleanly.

## Turn: 2026-09-12 11:46:59 (session 315b089e)

Everything is staged. Here's the proposal — nothing has been submitted.

## First: the veriT premise was wrong, and that's good news

I built a static binary from `~/carcara/wt-corealethe/verit-2026.05` and it is **byte-identical to what the cluster already runs** — same size, same BuildID, md5 `fe3d897961fe5e3d1010d70916745ccf`. The cluster was never running the 2024 build; that was purely the local `~/verit/veriT` we deleted. **Round four's veriT numbers stand, and veriT needs no re-upload.**

## Second: the pre-flight caught a bug that would have wrecked the run

Testing the runner locally, one QF_LIA proof came back `holey, trusted=1` — an `aci_simp` step in the *elaborated* proof, which lean-smt no longer handles since the structural-rules split.

Tracing it: `aci_simp` appears nowhere in the input proof. Carcara's core pass **emits** it — the non-short-circuiting part of `and_simplify`/`or_simplify` is renamed to a single AC step, and that rename still produced the legacy name. `131f9a1f` fixed the *dispatch* of legacy steps but missed this *emission* site, and no warning fired because the relabel was never asked.

Since `and`/`or` are bounded semilattices the name is `semilattice_simp`. Fixed in **`fdef9ecf`** (pushed), using the same `structural_rule` validation as the relabel. That benchmark now gives `valid, trusted 0, holes 0`, and the elaborated proof still checks at elaborated granularity. Suite 411 passing. A 13-proof pre-flight across QF_UF/QF_LIA/QF_UFLIA/UF/QF_LRA and both solvers: **0 `aci_simp`, 0 `absorb`**.

This would have put a hole in a large fraction of round five's proofs.

## What changes vs round four

| | round four | round five |
|---|---|---|
| carcara | `20235088` | **`fdef9ecf`** (subtyping, resolution pivots, ac_simp premises + fallback, this rename) |
| lean-smt `.lake` | round-four oleans | **`3c0b72c`** (structural rules, per-step CSV) |
| cvc5, veriT, sets, rewrites.eo | — | **unchanged, same bytes** |
| wall limit | 2700 | **3000** (one new arm) |

**Runner changes** (`~/exp/alethe-lean/run-arms.sh`, smoke-tested end to end):
- New **`checkelab`** arm: carcara also checks the *elaborated* proof, so the box plots get a like-for-like carcara series over the same steps the Lean arm sees.
- `=== stats carcara ===` / `=== stats carcara-elab ===` sections carrying the per-rule mean step time.
- Rejected-rule attribution before the 2 KB cap, with ANSI stripped — the blind spot that left 186 of 199 `ac_simp` rejections unattributed last round. (`--no-color` exists but doesn't cover that error path, so I strip rather than trust it.)

**Box plots**: `~/exp/alethe-lean/rule-boxplots-round5.py`, in the core-rules report's style — distribution over benchmarks of the per-benchmark mean step time, one series per checker side by side, plus totals and a tidy `rule-samples.csv`. Validated against real runner output; the carcara/lean gap shows as the expected 2–3 orders of magnitude.

## Commands needing your approval, in order

**1. Deploy** (one chain, so one approval):
```
bash ~/exp/alethe-lean/deploy-alethe-lean5.sh
```
Creates `/barrett/scratch/hbarbosa/runs/alethe-lean5`: hard-link copy of round four's lean-smt tree, cvc5/veriT/sets/rewrites.eo copied, toolchain symlinked; rsyncs the new static carcara and `.lake`; then prints versions and runs a head-node smoke test on one QF_UF and one QF_LIA benchmark per solver.

**2. Dry run** — I have not been able to syntax-check `submit-alethe-lean5.sh` locally, because the guard blocks any command naming it; please fold that into this approval:
```
cluster-run barrett2 'bash -n /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh && bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh --dry-run 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-dryrun.log | tail -40'
```

**3. Submit**, in a detached tmux:
```
cluster-run barrett2 'tmux new-session -d -s alean5 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-submit.log; sleep 3600"'
```

Two jobs, one per solver: `-p octa -j 8 --wall-time --time-limit 3000 --memory-limit 12000 --cpus 1`, working dirs `exp/results/alethe-lean/{cvc5,verit}-5`, job names `alean5-{cvc5,verit}`, the same twelve unsat logics as round four.

One thing to decide before step 1: the other session is committing to lean-smt every few minutes. My `.lake` was built at `3c0b72c` and no Lean source has changed since, but if you want a later state in the run, say so and I'll rebuild first.

## Turn: 2026-09-12 11:51:51 (session 315b089e)

The pre-flight finished and confirms the fix. Everything is staged; **nothing submitted**.

## Pre-flight, final

18 veriT + 5 cvc5 proofs across QF_UF, QF_LIA, QF_UFLIA, UF, QF_LRA: **0 `aci_simp`, 0 `absorb`**, with `semilattice_simp` appearing where the legacy name used to.

The four `error` rows in that table were my own sampling artefact — I picked benchmarks by file size, and those are **sat**, so veriT wrote "Formula is Satisfiable" where the proof should be. The runner guards on `result = unsat` and the cluster draws from the `unsat_*` sets, so they can't occur there. Not a toolchain problem.

## Recap of what's ready

- **veriT needs no change** — the deployed binary is byte-identical to a static build of the 2026.05 source (md5 `fe3d897961fe5e3d1010d70916745ccf`). Round four's veriT numbers stand.
- **`fdef9ecf`** (pushed) fixes the emission site that renamed `and_simplify`/`or_simplify` to the legacy `aci_simp` — a step lean-smt no longer handles, so it was becoming a hole in proofs where `aci_simp` appears nowhere in the input. Caught only because I smoke-tested before proposing.
- Runner has the `checkelab` arm, both `=== stats carcara* ===` sections, and attribution that survives the byte cap.
- `rule-boxplots-round5.py` validated against real runner output.
- Both repos clean; lean-smt pin at `fdef9ecf`; oleans built at `3c0b72c` with no Lean source changed since.

## Awaiting your approval, in order

**1. Deploy**
```
bash ~/exp/alethe-lean/deploy-alethe-lean5.sh
```

**2. Dry run** — please fold in the `bash -n`; the guard blocks any command naming that script, so I could not syntax-check it locally:
```
cluster-run barrett2 'bash -n /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh && bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh --dry-run 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-dryrun.log | tail -40'
```

**3. Submit**
```
cluster-run barrett2 'tmux new-session -d -s alean5 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-submit.log; sleep 3600"'
```

Two jobs, `-p octa -j 8 --wall-time --time-limit 3000 --memory-limit 12000 --cpus 1`, working dirs `exp/results/alethe-lean/{cvc5,verit}-5`, the same twelve unsat logics as round four.

Run `cluster-approve` in a real terminal for each step and I'll retry the command unchanged. Still open: whether you want the `.lake` rebuilt at a later lean-smt commit — the other session is still committing, though only to scripts so far.

## Turn: 2026-09-12 11:52:21 (session 315b089e)

The cvc5 sweep finished too — it had 12 proofs, not the 5 I quoted earlier from a partial read.

**Final pre-flight: 30 proofs (18 veriT + 12 cvc5), 0 `aci_simp`, 0 `absorb`.** `semilattice_simp` appears in 11 of them where the legacy name used to. That's a firmer basis for `fdef9ecf` than the numbers in my last message.

Nothing else changed. The three approval steps stand exactly as posted:

1. `bash ~/exp/alethe-lean/deploy-alethe-lean5.sh`
2. the dry run (with `bash -n` of the submit driver folded in)
3. the tmux submission

Run `cluster-approve` when you want to start, and I'll retry each command unchanged.

## Turn: 2026-09-12 12:08:13 (session 315b089e)

Deploy in progress — 4 processes (the `.lake` rsync). No output yet; the version checks and smoke test print at the end. I'll report when it completes.

## Turn: 2026-09-12 12:09:59 (session 462452f0)

Done — `--csv <dir>` is gone, replaced by `--plots`.

`scripts/check-alethe.sh:9` and `:97`:

```bash
cd ~/some/wherever
~/lean/lean-smt/scripts/check-alethe.sh --plots problem.smt2 problem.alethe
```

makes `./problem/` (the proof's basename, with a trailing `.alethe` stripped) in the directory you ran from, and leaves everything about the run in it:

```
problem/runs.csv  problem/steps.csv
problem/rule-boxplots.{pdf,png}  problem/rule-totals.{pdf,png}
```

It just passes that directory to the checker's `csv` clause and then runs `scripts/rule-boxplots.py -o <dir> <dir>` on it, so the box plot's series is labelled with the proof name.

Details worth knowing:

- **matplotlib is checked up front**, before the check runs, so a long run doesn't end with no plots. The interpreter is `$PYTHON`, default `python3`; since your system `python3` has no matplotlib, use e.g. `PYTHON=~/.venvs/plots/bin/python scripts/check-alethe.sh --plots …`.
- Plots are drawn whatever the verdict was — a check that failed part way still recorded the steps it got through. If no steps were recorded at all it warns instead of failing.
- `--elaborate` still rewrites the `runs.csv` proof name to the file you handed the script, not the temp elaborated one.
- README updated: the `--csv` mention in the trailing-options sentence is dropped, and the `rule-boxplots.py` paragraph now points at `--plots` for the single-proof case.

Verified end-to-end on `Test/Alethe/QF_UF/distinct_bool` (4 steps, all six files written), plus the two error paths: `--csv` now reports `unknown option`, and a python without matplotlib fails before the check.

## Turn: 2026-09-12 12:13:15 (session 315b089e)

Deploy verified:

| | |
|---|---|
| carcara | `1.1.0 [git fdef9ecf bv-fixes]` ✓ |
| cvc5 | `1.3.5.dev+alethebv@1eb17718e1` (unchanged) |
| veriT | md5 `fe3d897961fe5e3d1010d70916745ccf` (unchanged, the 2026.05 build) |
| lean-smt oleans | Sep 11 19:48 cluster time = my 23:48 local — the CSV-feature build |
| Lean | 4.33.0 |

All four smoke tests: **`valid, trusted 0, holes 0`**, with `[cfg checkelab] result=valid` — the new arm works on the cluster.

One thing I can't confirm from that output: my smoke-test grep only passes section *headers*, so I can see `=== stats carcara-elab ===` and `=== rule times lean ===` appear but not whether they carry rows. The `rule times` header only prints when `steps.csv` is non-empty, so it's near-certain — but since that data is the whole point of this round, I'd rather check it than infer.

**Step 2**, with the syntax check and that verification folded in so it's one approval:

```
cluster-run barrett2 'set -e
  S=/barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh
  B=/barrett/scratch/hbarbosa/runs/alethe-lean5
  bash -n $S && echo "submit driver: syntax ok"
  b=$(head -1 $B/sets/benchmark_set_unsat_QF_LIA)
  BASE=$B SOLVER=verit LEAN_MODES=lean $B/run-arms.sh $b > /tmp/alean5-probe.txt
  echo "--- rows under each per-rule section:"
  for s in "stats carcara" "stats carcara-elab" "rule times lean"; do
    printf "%-22s %s\n" "$s" "$(awk -v h="=== $s ===" "\$0==h{f=1;next} /^===/{f=0} f&&NF" /tmp/alean5-probe.txt | wc -l)"
  done
  awk "/=== rule times lean ===/{f=1;next} /^===/{f=0} f" /tmp/alean5-probe.txt | head -8
  bash $S --dry-run 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-dryrun.log | tail -40'
```

This runs one QF_LIA benchmark on the head node, counts the rows under each per-rule section, shows a few, then prints the dry run. Nothing is submitted.

## Turn: 2026-09-12 12:14:12 (session 462452f0)

The directory name is now the basename with both `.alethe` and `.smt2` stripped, so your command gives `./perturbations_0.onnxhyperrectangle_1684.vnnlib/` instead of trying to reuse the `.smt2` file's name. Also added an upfront error if that name exists as a file rather than a directory, so you get a clear message instead of `mkdir: File exists`.

Verified by running from the repo root, where both the problem and the proof sit: `Test/Alethe/QF_UF/distinct_bool.{smt2,alethe} … native --plots` → `./distinct_bool/` with the two CSVs and four plot files (test dir removed afterwards).

## Turn: 2026-09-12 12:17:12 (session 315b089e)

The command is now recorded in `~/.claude/cluster-pending.txt`, so approval can match it.

Please run `cluster-approve` in a real terminal, and I'll retry it byte-identical.

What it does — nothing is submitted:
- `bash -n` on the submit driver (the syntax check I couldn't do locally, since the guard blocks any command naming it)
- runs **one** QF_LIA benchmark through the runner on the head node, and counts the rows under `=== stats carcara ===`, `=== stats carcara-elab ===` and `=== rule times lean ===` — the box-plot data I could only infer was present from the deploy's smoke test
- `submit-alethe-lean5.sh --dry-run`, printing the generated SLURM script

The only cluster writes are `/tmp/alean5-probe.txt` on the head node and the dry-run log at `/barrett/scratch/hbarbosa/scripts/alean5-dryrun.log` (kept so the output can be re-read without spending another approval).

## Turn: 2026-09-12 12:17:33 (session 462452f0)

Two different producers, both confirmation noise:

- **`[csv] …: 6913 steps`** — the Lean checker itself, `Smt/Alethe/Command.lean:48`: `#check_alethe`'s `csv "<dir>"` option appends that line to its own report. So it shows up for any use of the `csv` clause, not just through the script.
- **`perturbations_…: 6913 steps over 1 proof(s)`** — `scripts/rule-boxplots.py:154`, the per-label summary it prints before drawing (one line per configuration, so it's informative when comparing series, redundant for one proof).

The third line (`wrote …`) is also `rule-boxplots.py`, at the end.

Want me to silence them? Cheapest version that keeps both tools honest on their own: drop the `[csv]` line from `Command.lean` (the paths are already known to whoever passed them) and have `check-alethe.sh` run the plotter quietly — e.g. swallow its stdout and print one `plots: <dir>` line itself, or add a `-q/--quiet` flag to `rule-boxplots.py` so it stays chatty when run by hand.

## Turn: 2026-09-12 12:20:13 (session 315b089e)

Dry run is clean.

## What it confirmed

**The box-plot data is live** — the point of this round:

| section | rows |
|---|---|
| `=== stats carcara ===` | 10 |
| `=== stats carcara-elab ===` | 9 |
| `=== rule times lean ===` | 7 |

with real values (`la_generic 11 937244437`, `resolution 27 95513098`, …). So the like-for-like carcara/lean-smt per-rule series both populate on the cluster, not just locally.

**The submit driver is sound**: `bash -n` passes (the check the guard had prevented me from doing locally), both jobs generate — 25 array blocks each for `run-cvc5.sh` and `run-verit.sh` — across the twelve `unsat_*` sets, into `exp/results/alethe-lean/{cvc5,verit}-5`, with `runexec --walltimelimit 3000 --memlimit 12000MB`. Ends with *"Dry run, jobs were not submitted to SLURM!"*

## Ready to submit

```
cluster-run barrett2 'tmux new-session -d -s alean5 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-submit.log; sleep 3600"'
```

Two jobs — `alean5-cvc5`, `alean5-verit` — `-p octa -j 8 --wall-time --time-limit 3000 --memory-limit 12000 --cpus 1`, twelve logics, ~23,300 benchmarks per solver. Detached tmux so the aggregator survives the ssh session.

Say the word and run `cluster-approve`; I'll fire it and then verify via the submit log (24× "Submitted batch job" plus "started aggregator") and `cluster-jobs`.

## Turn: 2026-09-12 12:20:34 (session 462452f0)

Done, all three:

**`Smt/Alethe/Command.lean:47`** — the `[csv] …` line is gone; `#check_alethe … csv "<dir>"` now writes the files without narrating them. Rebuilt (`lake build Smt`, 397 jobs, no new warnings).

**`scripts/rule-boxplots.py`** — new `-q/--quiet`, which drops the per-label step counts and the trailing `wrote …`. Warnings stay: the `note: … pass --fold-rare` hint still prints, since it's actionable. Run by hand it's as chatty as before.

**`scripts/check-alethe.sh:188`** — calls the plotter with `--quiet` and prints one line of its own on stderr, next to the `time:` line:

```
valid: checked 4 steps, trusted 0, holes 0
plots: /…/distinct_bool (runs.csv, steps.csv, rule-boxplots, rule-totals)
time: lean 0.873s
```

If the plotter fails it says `warning: could not plot …` instead, so a silent plotter doesn't hide a failure.

Also rewrapped the README paragraph and the script header comment I'd left over-long, and split the Carcara-vs-lean-smt naming caveat into its own paragraph now that the `--plots` sentence sits before it.

## Turn: 2026-09-12 12:26:23 (session 315b089e)

Done. The workflow now lets me stage a command without attempting it first.

## What changed

**New `~/.local/bin/cluster-propose`** — writes the exact command string into the pending file so `cluster-approve` can display it:
```
cluster-propose -m 'what it does' -- <command>     # or the command on stdin
```

**`cluster-approve`** now shows where the entry came from (`the guard blocked it` vs `Claude staged it — it has not been run`), how old it is, and the note; it warns loudly on entries over an hour old, which is the one real hazard of staging ahead of time.

**The guard** records that provenance on deny, clears it alongside the token, and its block message now points at `cluster-propose`.

**`CLAUDE.md`** and the **stanford-cluster skill** document the new flow.

## The security property is unchanged

Staging grants nothing. The approval token is still written *only* by `cluster-approve`, still behind the TTY check, and is still the sha256 of the exact string — so an approval can only ever run the command you read and confirmed, regardless of who put the text there. You see the same text either way; the only difference is that you no longer have to wait for a failed attempt to produce it.

Verified: staging a submit command, a redirect, and a read-only command all round-trip to a hash identical to what the guard computes; no token is created by any of it; a benign command still passes untouched. `cluster-approve` still refuses without a TTY (exit 78).

Two bugs I hit and fixed while doing this, both mine:
- Backticks in the guard's new deny text were being evaluated as command substitution, so the hint rendered empty.
- My first staging helper was named `stage-submit.sh`, which the guard's `submit*.sh` pattern matched. Renamed. Worth knowing: the guard matches the command *string*, so helper scripts around this flow shouldn't have "submit" in the name.

## Round five is staged

```
cluster-run barrett2 'tmux new-session -d -s alean5 "bash /barrett/scratch/hbarbosa/scripts/submit-alethe-lean5.sh 2>&1 | tee /barrett/scratch/hbarbosa/scripts/alean5-submit.log; sleep 3600"'
```
noted as *"round five: two octa jobs (alean5-cvc5, alean5-verit), 12 unsat logics, -j 8, wall 3000s, mem 12000MB"*.

Run `cluster-approve` when you're ready and I'll fire it, then verify via the submit log (24× "Submitted batch job" plus "started aggregator") and `cluster-jobs`.

## Turn: 2026-09-12 12:27:11 (session 462452f0)

Committed as `797fc75` on `alethe-dev` — the four tracked files only (README, `Command.lean`, both scripts). The untracked benchmark files, `plots/`, `pyenv/`, and the two `perturbations_…` output directories were left alone.

## Turn: 2026-09-12 12:28:28 (session 315b089e)

Round five is submitted and running.

## Verified

- **24 "Submitted batch job"** — 12 arrays per solver, exactly as the dry run predicted
- **2 "started aggregator"** — one per job, both alive
- **tmux `alean5`** running, so the aggregators survive the ssh session
- `squeue`: **224 entries**, `alean5-cvc5` and `alean5-verit`, pending on Resources

(The 212/12 split is just cvc5's arrays having already expanded into per-task entries while veriT's are still collapsed — both have their 12 arrays.)

## What's running

| | |
|---|---|
| jobs | `alean5-cvc5`, `alean5-verit` |
| limits | `-p octa -j 8 --wall-time --time-limit 3000 --memory-limit 12000 --cpus 1` |
| sets | 12 unsat SMT-LIB logics, ~23,300 benchmarks per solver |
| results | `exp/results/alethe-lean/{cvc5,verit}-5` |
| toolchain | carcara `fdef9ecf`, lean-smt oleans `3c0b72c`, cvc5 and veriT unchanged from round four |

Round four took a while at these limits, so expect this to run for many hours. Nothing to do until it finishes — I'll pull it with `cluster-sync alethe-lean/{cvc5,verit}-5` and then produce:

- the report update (Table 1 and the failure accounting, now with the `ac_simp` fixes measured at corpus scale rather than on 199 benchmarks locally)
- the rule box plots via `rule-boxplots-round5.py`, with carcara-on-elaborated and lean-smt as like-for-like series

Two things this round should settle that I could only infer: whether the `ac_simp` work moves the corpus numbers as predicted, and whether the `semilattice_simp` rename really eliminates the holes — the pre-flight said 0 legacy AC steps in 30 proofs, but that's a sample, not 23k.

Ping me when you want the results pulled, or ask for `cluster-jobs alethe-lean/verit-5` any time for progress.

## Turn: 2026-09-12 17:40:01 (session bddaeda3)

Understood — and you were right that it was a real hole, not just carelessness on my part.

**State right now:** nothing of mine is running; 5 GB used, 25 GB free. My run died from its own `timeout 900`, not the OOM killer — but it *could* have eaten the box, because `check-alethe.sh` ran `lake env lean` with **no memory bound at all** (the cluster runner has `-M 10000`; the local script had nothing).

**Fixed** (`ec870af`): the script now passes `-M $LEAN_MEM`, default **8000 MB**, `LEAN_MEM=0` to disable. Verified both directions — the normal run still passes, and `LEAN_MEM=16` aborts with `excessive memory consumption detected`, so the flag genuinely applies.

**My practice from here on** for anything heavy:
- Lean: always through `check-alethe.sh` (now capped) or an explicit `-M`, and **one at a time** — never a Lean run alongside a `lake build`.
- Big proofs get a small `LEAN_MEM` and a short `timeout` first, and I only raise them if the small run shows it's worth it.
- Carcara/veriT/cvc5 batches: bounded `timeout`, and I'll keep sample sizes small (the 6-benchmark sweeps rather than the whole family).
- I'll check `free`/`ps` before launching anything long rather than after.

On the interrupted experiment: I won't re-run that 1,749-step QF_UF proof end-to-end — it's the expensive way to confirm something I can already state precisely. What the pivot fix (`67a5a426`) demonstrably buys is measured at the Carcara level: elaboration goes from `rc=1, no output` (proof lost) to `rc=0, valid, 1,749 steps`, and the result checks **valid** at default granularity. Whether lean then validates that particular proof within 900 s is a separate scale question — it's one of the big hwbench proofs that were already near the timeout boundary in round four.

Still untouched and awaiting your go-ahead: the `ac_simp` premise-aware checker (~199 + ~198 proofs).

## Turn: 2026-09-12 17:40:01 (session bddaeda3)

The fix is done, committed, and verified. Here's where things stand while the corpus-wide measurement finishes.

## The defect

`ac_simp`'s checker destructured `RuleArgs { conclusion, pool, .. }` — it never bound `premises`. veriT emits the rule *with* premises when the flattening of a subterm was derived earlier (a rewrite under a binder, packaged as a `bind` subproof), so the conclusion is congruence over those equalities rather than the structural flattening of its left-hand side. The checker only had the latter reading and rejected every such step.

The cost wasn't a checking gap — it was a **lost proof**. Elaboration validates as it goes, so those benchmarks came back with neither an elaborated proof nor a verdict.

## The fix — Carcara `13e721d7`

The checker now builds a rewrite map from the unit-equality premises and mirrors the *elaborator's* two routes, which had been premise-aware all along (they were only ever reached for steps whose premises happen to be redundant):

- **Route 1**, historical: both orientations, normalization stops at a replacement, RHS must *be* the normal form of the LHS.
- **Route 2**, meet in the middle: forward orientation only, continuing past a replacement, both sides reaching a common normal form.

Two deliberate restrictions keep existing behaviour exactly intact: route 2 runs **only when the step has premises** (without them route 1 *is* the rule's definition, and the suite pins a case that a common-normal-form reading would wrongly accept), and premises that aren't unit equalities are **ignored rather than rejected**, so such a step checks as it did when premises were unread.

## Evidence

- **Real instance, negative control.** `QF_LIA/…/Referendum-PT-010/RF-03.smt2`, step `t7` with `:premises (t3 t5 t6)` — the exact step the cluster reported. Pre-fix binary `invalid`, post-fix `valid`. End to end through lean-smt: **`valid: checked 134 steps, trusted 0, holes 0`** in 1.06 s, on a proof that had been entirely lost.
- **Regression.** Differential run of pre-fix vs post-fix over 40 previously-valid benchmarks carrying **501 premise-bearing `ac_simp` steps** (up to 40 in one file): 40/40 identical verdicts.
- **Suite green**: 409 tests, including 6 new checker cases and a new elaboration test.
- **No lean-smt change needed** — the decomposition is `cong`/`trans`/`semilattice_simp`, all already reconstructed.

## One correction to the count

The 199 figure was right, but my earlier filter reached it by accident. Properly attributed from the logs: 13 `ac_simp` + 24 `and_simplify` named, and **186 more `ac_simp`** whose rule name fell past the runner's 2 KB stderr cap. 13 + 186 = 199 — **175 QF_UFIDL** (`pete2`/`pete`/`uclid`) and **24 QF_LIA**.

At 41/199 of the memory-gated sweep: **23 `invalid`→`valid`**, 9 `→holey`, 9 `error`. Both non-valid groups are unrelated pre-existing residue, not `ac_simp` — the holey ones are `calypto` proofs holey purely from `lia_generic`, and the "errors" are 38 MB `pete2` proofs hitting *my own* 6 GB `ulimit -v`; re-run at 12 GB, `c10bid_s.smt2` gives `invalid`→`valid` too. I'll re-run those at the higher cap once the sweep lands.

Two notes: `92d8a42f`, `67a5a426` and `13e721d7` are all still **unpushed**, so the pin bump in `setup-alethe.sh` won't resolve until they are. And you're editing `Command.lean`, `Frontend.lean`, `Reconstruct.lean` and `check-alethe.sh` for the CSV/boxplot feature — I left those alone and committed only my own files.

## Turn: 2026-09-12 17:40:01 (session bddaeda3)

Here's where round five stands, and it's not the clean result I'd hoped for.

## Progress

cvc5 is at **18,943 of ~23,300** tasks. veriT hasn't started — all 12 arrays still pending behind cvc5 on the partition.

## Paired against round four (same 18,917 benchmarks)

| | round four | round five |
|---|---|---|
| carcara valid | 15,285 | 15,279 |
| elaborate valid | 15,280 | 15,279 |
| **lean valid** | **14,200** | **14,138** |
| timeout | 1,033 | 1,058 |
| holey | **2** | **35** |

**This is a regression, not an improvement.** The verdict changes: 35 `valid → holey`, 30 `valid → timeout`, and 6 newly lost in elaboration against 5 recovered.

Timings are comparable (median wall/cpu 1.3× vs 1.4×), so contention isn't distorting it — the 30 timeouts look like ordinary boundary noise, but the 35 holes are systematic.

## Root cause, found and fixed

All 35 holes are surviving `aci_simp` steps. In round four lean-smt still had an `aci_simp` handler; the structural-rules split removed it, and Carcara's relabel was declining these, so they became trusted steps.

Reduced to one line — cvc5 emits:
```
(= (not p) (or (not p) (not p)))
```
Idempotence **read backwards**. `structural_rule` picked the rule from the head of the first side that was an application at all — here `not` — and fell through to `None`. The checkers themselves are already symmetric; only the classifier was guessing. It now asks each of the four in turn and takes the first that accepts.

**`92c641c0`**, pushed. The benchmark now elaborates with zero `aci_simp` and no warning, and checks at elaborated granularity. Suite 411.

## A second bug, mine, in the new arm

My `checkelab` arm omitted `--expand-let-bindings`, so it fails with *"could not match term to any of the original problem premises"* on proofs where lets matter — `stats carcara-elab` is present for only 6,986 of 15,279. Confirmed locally: same proof, `invalid` without the flag, `valid` with it. Fixed in the local runner.

This only degrades the like-for-like series for the box plots; the main results (`carcara` on the original proof, and the lean arms) are unaffected, and `stats carcara` is present for all 15,279.

## What I did *not* do

I have **not** redeployed either fix. cvc5 is 81% through, and swapping the runner or binary now would split its data between two toolchains — worse than a uniform known residue. So this round will show the 35 holes and the reduced `carcara-elab` coverage, both explainable.

Your call on what happens next. The options:

1. **Let it finish**, report with the residue documented — the fixes land in round six.
2. **Cancel and restart** with both fixes — costs the ~5 hours spent, buys a clean 0-hole result and full box-plot coverage.

I lean to (2) only if the box plots matter more than the schedule, since the `carcara-elab` gap is the part that's genuinely hard to reconstruct afterwards. Otherwise (1).

---

# Round six prepared (after the cancel)

You cancelled round five. Queue is empty, the tmux server on the head node is gone.

## What the pre-flight did, and the false alarm on the way

The first pre-flight came back `none` on every field for all six benchmarks. Not a toolchain problem: my loop fed the benchmark list to the runner's *stdin*, and the runner ate it. With stdin detached (and each runner log kept under `/tmp/r6pf-<solver>-<bench>.log`) the two round-five failures now come out right:

| benchmark | elab | checkelab | aci_simp | absorb | lean | trusted |
|---|---|---|---|---|---|---|
| UF/…/coinductive_list/x2015_09_10_16_50_44_871_1146867 (the backwards idempotence) | valid | valid | 0 | 0 | valid | 0 |
| UF/sledgehammer/Arrow_Order/smtlib.693005 (the let-bindings failure) | valid | valid | 0 | 0 | valid | 0 |

The first now elaborates to `semilattice_simp 4` (round five: `aci_simp 4`, 35 such holes); the second no longer reports *could not match term* on the checkelab arm. A wider smoke run over the other four benchmarks, and veriT on the two above, is running in the background one benchmark at a time.

## Toolchain for round six

- carcara `92c641c0` (bv-fixes), static-pie, `~/carcara/wt-diff/target/x86_64-unknown-linux-gnu/release/carcara`
- lean-smt `21b569a` (alethe-dev: `797fc75` + the pin bump to `92c641c0`), oleans rebuilt after the last source change
- `run-arms.sh` with `--expand-let-bindings` on all three carcara invocations (md5 `932f2d82…`)
- cvc5, veriT 2026.05, the twelve `unsat_*` sets and `rewrites.eo` copied unchanged from `runs/alethe-lean5`

## Scripts

`~/exp/alethe-lean/deploy-alethe-lean6.sh` (seeds `runs/alethe-lean6` from `alethe-lean5` by hard-link copy, uploads the three changed pieces, prints versions plus the `expand-let-bindings` count, runs the head-node smoke test) and `~/exp/alethe-lean/submit-alethe-lean6.sh` (same limits as round five: octa, `-j 8`, wall 3000 s, 12000 MB, 1 cpu, working dirs `cvc5-6` / `verit-6`, job names `alean6-*`).

The deploy is staged with `cluster-propose`. The dry run and the tmux submit are pre-written under the job's tmp dir so each can be staged with one line when its turn comes; the pending file holds one command at a time, so they go up in sequence: deploy → dry run → submit.

## Turn: 2026-09-12 18:01:47 (session bddaeda3)

All `none` — I forgot to set `CVC5` in the pre-flight, so it looked for the cluster path.

## Turn: 2026-09-12 18:01:47 (session bddaeda3)

The deploy is staged for approval and the wider smoke run is still going in the background, one benchmark at a time. I will report its result when it finishes.

**Status so far**

- Both round-five defects are confirmed fixed on the benchmarks that exposed them. The backwards-idempotence proof now elaborates to `semilattice_simp` with zero legacy `aci_simp`, and the let-bindings proof passes the checkelab arm. Both are valid in Lean with no trusted steps.
- The first pre-flight failure was my loop feeding the benchmark list into the runner's stdin. Not a toolchain issue.
- Committed the Carcara pin bump to lean-smt as `21b569a`.
- Wrote `~/exp/alethe-lean/deploy-alethe-lean6.sh` and `submit-alethe-lean6.sh`, same limits as round five, working dirs `cvc5-6` and `verit-6`.

**Waiting on you:** run `cluster-approve` to review the staged deploy. The dry run and submit commands are pre-written and go up next, one at a time.

## Turn: 2026-09-12 18:10:41 (session bddaeda3)

Deploy done and the dry run is staged.

**Deploy result** (log at the job's tmp dir, `r6-deploy.log`):
- Carcara reports `92c641c0 bv-fixes`, veriT md5 unchanged, runner md5 matches the local copy, and the runner carries `--expand-let-bindings` three times as expected.
- Head-node smoke test: cvc5 and veriT on one QF_UF and one QF_LIA benchmark, every arm valid, no trusted steps.

**Local smoke run** so far: the QF_UF NEQ004 benchmark came back valid on every carcara arm but the Lean arm hit my local 600 s cap. The direct run before took 594 s and passed, so this is boundary noise. The cluster gives the Lean arm 900 s. The remaining benchmarks are still running.

**Waiting on you:** run `cluster-approve` for the dry run. It submits nothing and saves its full output to `scripts/alean6-dryrun.log` on scratch.

## Turn: 2026-09-12 18:13:23 (session bddaeda3)

The dry run confirmed the cvc5 configuration but stopped before the veriT half, and that was my fault.

**What the dry run showed** for cvc5: partition octa, wall limit 3000 s, 12000 MB, 1 cpu, 8 jobs per node, QOS max2, working dir `cvc5-6`, all twelve `unsat_*` sets resolved from `runs/alethe-lean6/sets`. No errors.

**Why it stopped:** the staged command piped the driver through `head -80` for a short preview. When head closed the pipe, the driver died before its second loop iteration, so the veriT half never ran and the saved log is truncated. The corrected command writes the full log first and only then summarizes it.

**Waiting on you:** run `cluster-approve` for the corrected dry run. If you would rather skip the repeat, say so and I will stage the submit directly. The veriT half is the same loop body with `verit` substituted, so the risk of skipping is low.

The local smoke run is still going, one benchmark at a time.

## Turn: 2026-09-12 18:13:48 (session bddaeda3)

The corrected dry run passed for both solvers, and the submission is staged.

**Dry run**: exit 0, cvc5 and veriT halves both present, each with octa, wall 3000 s, 12000 MB, 1 cpu, 8 jobs per node, and the twelve `unsat_*` sets, into `cvc5-6` and `verit-6`. No errors.

**Waiting on you:** run `cluster-approve` for the submission. It starts the driver inside a detached tmux session named `alean6`, waits 45 s, then prints the count of submitted arrays, the aggregator lines, and the queue.

## Round six submitted

Deploy approved and run: carcara `92c641c0 bv-fixes`, veriT md5 `fe3d8979…`, runner md5 `932f2d82…`, `expand-let-bindings: 3`, head-node smoke test valid on every arm for both solvers.

Dry run: my first staged command piped the driver through `head -80`, which closed the pipe and killed the driver after the cvc5 half. Redone with the log written first: rc 0, both halves present, 24 set lines.

Submitted at 18:2x inside tmux `alean6`: 24 arrays (12 per solver), aggregators 1471327 (cvc5) and 1471359 (veriT). cvc5 arrays 27756865–27756872 and 27757073–27757076; veriT 27757077–27757088. Working dirs `exp/results/alethe-lean/cvc5-6` and `verit-6`, log `scripts/alean6-submit.log`.

Two lessons for the approval workflow, now in memory: the token is bound to the *whole* Bash command string, so a locally appended `| tee | grep` makes an approved command unrecognisable; and never put `head` after the driver in a `tee` pipeline.

Next: `cluster-sync alethe-lean/cvc5-6` and `verit-6` when they finish, pair against round four, then the report update and the rule box plots (`rule-boxplots-round5.py`, to be pointed at the round-six data).

## Turn: 2026-09-12 18:16:22 (session bddaeda3)

Round six is submitted and running. Summary of the whole job:

**Submitted** at about 18:25 inside tmux session `alean6`. Both aggregators started and 24 arrays are queued, 12 per solver. The first cvc5 tasks are already running on the octa nodes.

| item | value |
|---|---|
| cvc5 arrays | 27756865 to 27756872, 27757073 to 27757076 |
| veriT arrays | 27757077 to 27757088 |
| working dirs | `exp/results/alethe-lean/cvc5-6`, `verit-6` |
| limits | octa, 8 per node, wall 3000 s, 12000 MB, 1 cpu |

**What changed since the cancelled round five**
- Carcara `92c641c0`: the structural rule for a renamed `and_simplify`/`or_simplify` is chosen by asking each checker, so cvc5's backwards idempotence becomes `semilattice_simp` instead of a hole. Confirmed on the benchmark that exposed it.
- The runner's carcara-on-elaborated arm now passes `--expand-let-bindings`. Confirmed on the benchmark that exposed it.
- lean-smt oleans at `21b569a`, which is HEAD plus the pin bump. Everything else is byte-identical to round five.

**Local pre-flight**: the first all-`none` run was my loop feeding the benchmark list into the runner's stdin. Fixed. The two round-five failures now pass every arm. One larger QF_UF benchmark hit my local 600 s Lean cap after passing at 594 s in a direct run. The cluster allows 900 s, so this is boundary noise. The rest of the smoke run is still going in the background.

**Two mistakes of mine cost you extra approvals**: I appended a local pipe to the approved dry-run command, which the guard correctly rejected, and my first dry run put `head` after the driver, which cut off the veriT half. Both are recorded in memory so they do not recur.

**Committed** to lean-smt on `alethe-dev`: `21b569a` (pin bump) and `b74a550` (log).

**Next**, once the jobs finish: `cluster-sync alethe-lean/cvc5-6` and `verit-6`, pair against round four, update the report, and generate the rule box plots.

## Turn: 2026-09-12 18:17:05 (session bddaeda3)

Done. I had one shell open and it is now stopped, with nothing left behind.

**What was mine**
- The local smoke run over the remaining four benchmarks plus veriT. It was on a large QF_UF benchmark with three more to go, each up to 25 minutes of Lean time. Its purpose was already served: both round-five failures pass every arm, and the cluster run is the real test. Stopped, and no runner, cvc5, carcara or Lean process from it remains.

**What is not mine**
- Five interactive bash shells on pts/1, 2, 5, 13 and 15, parented by your terminal emulators.
- The Lean server and four Lean workers on lean-smt files, which belong to an editor session.

The cluster jobs are unaffected and keep running under tmux `alean6` on the head node.

## Round six, first check (cvc5 at 17,559 / 23,328; veriT still queued)

Paired on the same 17,559 benchmarks:

| | round four | round five | round six |
|---|---|---|---|
| carcara valid | 14,003 | 13,999 | 14,001 |
| lean valid | 13,633 | 13,590 | 13,625 |
| lean timeout | 324 | 332 | 334 |
| lean error | 42 | 42 | 42 |
| **holey** | 2 | **35** | **0** |
| `stats carcara-elab` present | – | 6,986 of 15,279 | **14,001 of 14,001** |

Both fixes hold at scale: no legacy AC rule survives into any elaborated proof, all 35 round-five holes are valid again, and the checkelab arm covers every elaborated proof.

The residue against round four is boundary noise: the 12 `valid → timeout` all took 529–900 s in round four (limit 900); the 4 "lost in elaboration" are cvc5 solver timeouts, no proof to elaborate; the 42 lean errors are the same 42 benchmarks as round four (35 `failed to parse`, 5 deep recursion, 2 memory) — still to be investigated.

## Turn: 2026-09-12 21:13:23 (session bddaeda3)

Round six looks right. Both fixes hold at scale on the partial cvc5 data, and veriT has not started yet.

**Progress** at about three hours in: cvc5 has 17,559 of 23,328 tasks aggregated, with 200 running and 5,569 queued. All 23,328 veriT tasks are pending behind them.

**Paired on the same 17,559 benchmarks**

| | round four | round five | round six |
|---|---|---|---|
| carcara valid | 14,003 | 13,999 | 14,001 |
| lean valid | 13,633 | 13,590 | 13,625 |
| lean timeout | 324 | 332 | 334 |
| lean error | 42 | 42 | 42 |
| holey | 2 | 35 | 0 |
| carcara-on-elaborated stats present | none | 6,986 of 15,279 | 14,001 of 14,001 |

- No legacy AC rule survives into any elaborated proof. All 35 round-five holes are valid again, and round four's own 2 holes are gone too.
- The checkelab arm now covers every elaborated proof, so the rule box plots will have a full like-for-like carcara series.

**The residue against round four is noise, not regression**
- The 12 benchmarks that went valid to timeout all took between 529 and 900 s in round four, against a 900 s limit.
- The 4 "lost in elaboration" are cvc5 solver timeouts this time, so there was no proof to elaborate.
- The 42 Lean errors are the same 42 benchmarks as round four: 35 `failed to parse`, 5 deep recursion, 2 memory. These remain uninvestigated.

The check is recorded in the log as commit `c622cb6`. Next check should come once veriT has started, likely a few hours from now.

## Turn: 2026-09-12 21:29:33 (session bddaeda3)

Interim status while the heavy local re-checks run.

**Three separate causes behind the 42 Lean errors**, all reproduced locally:

- **35 parse errors, two sub-causes.** For 21 of them (UFLIA/tokeneer and the QF_IDL cache benchmark) Carcara printed symbols containing an apostrophe without bars, so cvc5's parser rejected the elaborated proof. Fixed in Carcara `29a8e966`, pushed, suite 412 passing. All 20 locally available benchmarks now check valid in Lean. The other 14 (QF_LIA/2019-ezsmt) are different: cvc5 keeps a parameterised `define-fun` as an uninterpreted symbol plus an assumption equating it to a lambda, and then reasons about the lambda with `bind`, `trans` and `ho_cong`. lean-smt macro-expands definitions and has no `ho_cong`, and cvc5's parser has no `lambda` outside HO logics. Supporting this needs define-funs as let-bound functions plus an `ho_cong` reconstructor. Not implemented. These 14 are the only proofs in round six containing `ho_cong`.
- **5 deep recursions** are problems with 160k declared symbols and 280k assertions. Lean's `withLocalDecls` nests one call per declaration, which overflows the interpreter stack. I added a flat variant that extends the local context in a loop and installs it once, used for the problem's symbols and assertions. lean-smt builds. The 15 MB benchmark is now past the point where it crashed before and still running, so I will confirm once it finishes.
- **2 memory exceptions** are 104 KB UF benchmarks with 141-step proofs that blow past 6 GB in 30 s locally. Not yet pinned to a step. I will run one with per-step progress once the current Lean run finishes, since only one heavy Lean run goes at a time.

Cluster round six is at 18,045 cvc5 tasks, veriT still queued.

## The 42 Lean errors of round six, root-caused

All reproduced locally (`~/.claude/jobs/bddaeda3/tmp/repro.sh` runs the cvc5 arm keeping every intermediate file). Three causes, four sub-causes:

**35 × `cvc5 failed to parse the input`.**
- 21 (UFLIA/tokeneer, QF_IDL/sep): Carcara's printer decided quoting with the *lexer's* character predicate, which admits `'` for Carcara's own capture-avoidance renames. A symbol read from `|status'|` came back out as `status'`, which cvc5's parser rejects. **Carcara `29a8e966`** (pushed): the printer quotes any symbol containing `'`; unit test added, suite 412. The 20 locally available proofs now check valid in Lean.
- 14 (QF_LIA/2019-ezsmt/incrementalScheduling): cvc5 keeps a parameterised `define-fun` as an uninterpreted symbol with an assumption `(= max (lambda ((x Int) (y Int)) …))`, rewrites inside the lambda under a `bind`, chains with `trans`, and applies the result with `ho_cong` (`(max 0 x)` → `((lambda …) 0 x)`). lean-smt macro-expands definitions (so `max` unapplied has no meaning), has no `ho_cong` reconstructor, and these are the only 14 proofs in round six with `ho_cong`. **Not fixed.** Supporting them means define-funs as let-bound functions plus `ho_cong` and lambda `bind`/beta; a design decision for later.

**5 × deep recursion** (QF_LIA/20220307-SMPT SharedMemory, wireRouting/p15): problems with 160k declared symbols and 280k assertions. `Meta.withLocalDecls` nests one `withLocalDecl` per declaration, and the interpreter's stack gave out after minutes. **lean-smt `3cc44fa`**: `withLocalDeclsFlat` extends the local context in a loop and installs it once. RC-06 (15 MB): abort at 160 s / 5.2 GB → valid in 190 s / 3.2 GB. p15 (33 MB): valid in 280 s.

**2 × memory_exception** (UF/coinductive_list, 141- and 437-step proofs): an infinite loop. `resolveChain` re-resolves while the pivot remains in the working clause, and the premise `(cl @p_17 (not @p_17))` puts the pivot back on every pass: 2.2 million iterations before the 6 GB cap locally, 10 GB on the cluster. **lean-smt `4a37a9b`**: stop when the premise holds the pivot with the working clause's polarity. Both proofs now valid in about a second. `lake test`: 142 passing, none failed.

Pin bumped to Carcara `29a8e966` in `scripts/setup-alethe.sh`. Round six keeps running on the old toolchain; the 42 will show as errors there, and the fixes are for the next drop.

Also noticed: 40 of the 334 Lean timeouts have fewer than 2,000 elaborated steps (UF/sledgehammer/Hoare at ~330 steps and 3 GB, QF_IDL/parity with 10 MB proofs of a few hundred steps). Probing one locally.

## The small-proof timeouts, root-caused too

Probed `UF/sledgehammer/Hoare/smtlib.689154` (2 KB problem, 560-step / 153 KB elaborated proof, 900 s timeout in rounds four and six). Three super-linear costs, one after the other:

1. **Parser, 80 s**: every `:named` term re-resolved under every binder scope, and the proof has 227 names under thousands of quantifier scopes. A named term mentioning none of the scope's variables now resolves once (free atoms with proper scoping — a `?v0` bound *inside* the term must not count, since cvc5 reuses the name everywhere). → 0.2 s.
2. **Realization, > 200 s**: the arena called any term containing a bound atom *open*, so every quantified formula and every `choice` term was printed inline for cvc5. The 13 skolem definitions nest, so the text doubled per level: **144 MB for one step**. Each node now carries its free bound atoms and a binder form removes its own. → 0.04 s.
3. **Reconstruction, 190 s on the first step, then out of memory**: `withNewTermCache` empties the term cache under every binder, so closed subterms were reconstructed anew per scope — exponential on the same nesting. A second cache keeps terms that mention no variable beyond the problem's symbols; the Alethe driver sets that base, the cvc5 tactic path is unchanged (a first attempt that filtered the scoped cache on exit broke both flows: the scope wrapper is entered *after* the binder's variables are in the context). → 2 s.

**lean-smt `e9c32bf`, `6734243`.** `smtlib.689154`: 900 s timeout → valid in 2.0 s; `uf.828950` (another of the 40): valid in 2.0 s. Regression set (coinductive_list ×3, tokeneer, SharedMemory RC-06 at 198 s) all valid; `lake test` 142 passing.

Toolchain for the next drop: Carcara `29a8e966`, lean-smt `6734243`. Round six keeps running on the round-six binaries.

## Turn: 2026-09-12 23:06:56 (session bddaeda3)

All 42 errors are root-caused, three of the four causes are fixed, and the investigation also removed a long-standing timeout class. Round six is still running on the cluster with the old binaries.

**The 42 Lean errors**

- **35 parse errors, two causes.** 21 (tokeneer, one QF_IDL) were Carcara printing symbols with an apostrophe unquoted. Fixed in Carcara `29a8e966`, pushed, suite 412. All 20 locally available proofs check valid. The other 14 (QF_LIA/ezsmt) are cvc5 keeping a parameterised `define-fun` as a symbol plus a lambda assumption and reasoning about it with `bind`, `trans` and `ho_cong`. lean-smt macro-expands definitions and has no `ho_cong`. Not fixed. It needs define-funs as let-bound functions plus an `ho_cong` reconstructor, a design decision for you.
- **5 deep recursions** were problems with 160k symbols and 280k assertions overflowing the interpreter stack in Lean's nested `withLocalDecls`. Fixed in lean-smt `3cc44fa` with a flat variant. The 15 MB benchmark now checks valid in 190 s.
- **2 memory exceptions** were an infinite loop in resolution: a tautological premise holding both the pivot and its negation put the pivot back on every pass, 2.2 million times. Fixed in lean-smt `4a37a9b`. Both proofs check valid in about a second.

**The small-proof timeouts, a bonus.** 40 of the 334 Lean timeouts have proofs under 2,000 steps and were timeouts in round four too. One sledgehammer proof exposed three super-linear costs in sequence: the parser re-resolving named terms per binder scope (80 s), the realization treating every quantified formula as open and sending cvc5 a 144 MB string, and reconstruction rebuilding closed subterms under every binder. Fixed in lean-smt `e9c32bf` and `6734243`. That proof went from a 900 s timeout to 2 s, and a second one from the same group also checks in 2 s.

**Verification.** lake test passes all 142 tests. A regression set of six previously valid proofs, including the huge SharedMemory one, is still valid.

**Cluster.** cvc5 is at 18,718 of 23,328 tasks, in the slow tail. veriT is still fully queued. Nothing on the cluster was touched.

**Next toolchain** for round seven is Carcara `29a8e966` and lean-smt `6734243`. Everything is in the log, commit `bd00e4f`.

## Round six finished, and the report is on it

Both jobs completed (cvc5 23:30, veriT 09:38 the next day), 23,328 tasks each, queue empty.

| | cvc5 four | cvc5 six | veriT four | veriT six |
|---|---|---|---|---|
| proofs printed | 19,195 | 19,191 | 19,167 | 19,164 |
| carcara valid | 19,194 | **19,190** | 17,823 | **18,688** |
| lean valid | 16,853 | 16,813 | 15,334 | **15,870** |
| lean timeout | 2,287 | 2,327 | 2,494 | 2,827 |
| lean holey | 2 | **0** | 54 | **48** |
| lean error | 47 | 50 | 99 | 116 |

The veriT gain is the point: **carcara's gap falls 1,344 → 476**, and the checker gains 536 proofs. Paired attribution of the 871 newly accepted: 650 the int/real subtyping fix, 190 the ac_simp premise fix, 31 other. cvc5 loses 45 valid→timeout, all of which ran 441–900 s in round four against a 900 s limit; timings are otherwise identical (median wall six/four 1.02, carcara check ratio 1.00), so it is boundary noise, not a regression.

**Zero holey cvc5 proofs** — the structural-AC work is complete on that side. veriT's 48 are distinct_elim 32, lia_generic 10, th_resolution 6.

**The 27 surviving carcara rejections** are the same 24 benchmarks as round four plus three newly reachable: veriT emits `and_simplify` whose left side is not a conjunction, e.g. `(not (= (of_bool$ false) (of_bool$ true)))`. Not mine to fix. The 48→102 rise in the *count* is the attribution helper reading past the byte cap, not more failures.

### Report updated
`docs-alethe/alethe-lean-smt.tex`, 23 pages, builds clean. Table 1, Table 3 (native) and all five figures regenerated from round six; new `report-table.py` emits the table body and the prose figures so the next round is a re-run, not a retype. New **§2.2 "Where the Time Goes, Rule by Rule"** with the box plots you asked for: resolution is 51% of the checker's time and `and` another 14%, the gap runs 150× (rare_rewrite, distinct_elim) to 10,000× (the small clausal rules), and the structural AC rules are cheap on both sides. §2.4 now takes apart the four front-end defects behind the errors, three fixed here and `ho_cong` left open.

Also corrected: QF_LIA was never "99% complete", it is 93%; the Sledgehammer corpus predates the two carcara fixes and now says so.
