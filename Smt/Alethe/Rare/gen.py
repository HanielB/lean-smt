#!/usr/bin/env python3
"""Generate `Rules.lean` (Lean statements and the dispatch table for the RARE rewrite rules used
by `rare_rewrite` steps) from a RARE rule file in Eunoia syntax (`declare-rare-rule`).

Usage: gen.py <rewrites.eo> [<Rules.lean>]

Every rule becomes one Lean theorem (two for rules polymorphic over Int/Real, one per sort),
whose explicit arguments are the rule's `:args` (list parameters as `List`s) followed by its
`:premises`, in that order. `Smt.Alethe.reconstructRareRule` instantiates the theorem with the
step's arguments, so the statement must translate terms exactly as `reconstructTerm` does.

Proofs are preserved across regenerations: the text after the statement of a theorem in the
existing output file is kept (`sorry` for a new rule). A theorem whose proof is `sorry` is
reported as a trusted step by the checker.
"""

import hashlib
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# ----------------------------------------------------------------------------------------------
# S-expressions

def tokenize(text):
    text = re.sub(r";[^\n]*", "", text)
    return re.findall(r"\(|\)|[^\s()]+", text)

def parse_sexps(tokens):
    stack = [[]]
    for tok in tokens:
        if tok == "(":
            stack.append([])
        elif tok == ")":
            top = stack.pop()
            stack[-1].append(top)
        else:
            stack[-1].append(tok)
    assert len(stack) == 1, "unbalanced parentheses"
    return stack[0]

def sexp_str(s):
    return s if isinstance(s, str) else "(" + " ".join(sexp_str(x) for x in s) + ")"

# ----------------------------------------------------------------------------------------------
# Rules

@dataclass
class Param:
    name: str
    sort: object   # "Bool" | "Int" | "Real" | "@Tk" | compound (unsupported)
    is_list: bool = False

@dataclass
class Rule:
    name: str
    type_vars: list
    params: list
    premises: list
    args: list
    concl: object
    unsupported: str = ""
    instances: list = field(default_factory=list)  # [(inst, lean theorem name, proved)]

def read_rules(path):
    rules = []
    for s in parse_sexps(tokenize(Path(path).read_text())):
        if not (isinstance(s, list) and s and s[0] == "declare-rare-rule"):
            continue
        name = s[1]
        type_vars, params = [], []
        for p in s[2]:
            if p[1] == "Type":
                type_vars.append(p[0])
            else:
                params.append(Param(p[0], p[1], len(p) > 2 and p[2] == ":list"))
        attrs = {}
        i = 3
        while i < len(s):
            attrs[s[i]] = s[i + 1]
            i += 2
        rules.append(Rule(name, type_vars, params, attrs.get(":premises", []),
                          attrs[":args"], attrs[":conclusion"]))
    return rules

ARITH_OPS = {"<", ">", "<=", ">=", "+", "-", "*", "/", "div", "mod", "abs",
             "to_real", "to_int", "is_int"}
UNSUPPORTED_OPS = {"select", "store", "concat", "extract", "divisible", "bvadd", "bvand"}
NUMERAL = re.compile(r"^-?\d+(/\d+)?$")
TYPE_VAR = re.compile(r"^@?T\d+$")

def symbols(t, acc):
    if isinstance(t, str):
        acc.add(t)
    else:
        for x in t:
            symbols(x, acc)
    return acc

def lean_ident(name):
    return re.sub(r"[^A-Za-z0-9_]", "_", name)

# ----------------------------------------------------------------------------------------------
# Term translation

class Translator:
    """Translates rule terms into Lean syntax for one instance of a rule.

    `tsub` maps type variables to "Int" / "Rat" / "α". Sorts of Lean terms are "Prop", "Int",
    "Rat", "α", or ("List", sort)."""

    def __init__(self, rule, tsub):
        self.rule = rule
        self.tsub = tsub
        self.env = {}
        for p in rule.params:
            sort = self.lean_sort(p.sort)
            self.env[p.name] = (lean_ident(p.name), ("List", sort) if p.is_list else sort)
        self.decidable = []   # Prop parameters used as `ite` conditions

    def lean_sort(self, sort):
        if sort == "Bool":
            return "Prop"
        if sort == "Int":
            return "Int"
        if sort == "Real":
            return "Rat"
        if isinstance(sort, str) and sort in self.tsub:
            return self.tsub[sort]
        if isinstance(sort, str) and TYPE_VAR.match(sort):
            # used but not declared (or declared without `@`): the same as the declared ones
            return next(iter(self.tsub.values())) if self.tsub else "α"
        raise ValueError(f"unsupported sort {sexp_str(sort)}")

    @staticmethod
    def paren(s):
        return s if re.fullmatch(r"[A-Za-z0-9_α.']+|\(.*\)", s) and balanced(s) else f"({s})"

    def cast(self, e, sort, target):
        """Coerce `(e : sort)` to `target` the way `reconstructTerm` does (Int → Rat casts)."""
        if sort == target or target is None:
            return e
        if sort == "Int" and target == "Rat":
            if re.fullmatch(r"\(?-?\d+\)?", e):
                return e   # integer literals become rational literals
            return f"(↑{self.paren(e)} : Rat)"
        raise ValueError(f"cannot cast {e} : {sort} to {target}")

    def numeral(self, tok):
        if "/" in tok:
            n, d = tok.split("/")
            return (n if d == "1" else f"{n} / {d}", "Rat")
        return (tok, "Int")

    def join_sort(self, sorts):
        if "Rat" in sorts:
            return "Rat"
        if "Int" in sorts:
            return "Int"
        return sorts[0]

    def list_expr(self, args, elem_sort):
        """`(op a xs b)` with list parameters: `a :: (xs ++ [b])` etc."""
        acc = None
        for a in reversed(args):
            e, s = self.tr(a)
            if isinstance(s, tuple):
                acc = e if acc is None else f"{e} ++ {self.paren(acc)}"
            else:
                e = self.paren(self.cast(e, s, elem_sort))
                acc = f"[{e}]" if acc is None else f"{e} :: {self.paren(acc)}"
        return acc

    def tr(self, t, want=None):
        """Returns (lean text, sort)."""
        if isinstance(t, str):
            if t == "true":
                return ("True", "Prop")
            if t == "false":
                return ("False", "Prop")
            if t in self.env:
                return self.env[t]
            if NUMERAL.match(t):
                return self.numeral(t)
            raise ValueError(f"unknown symbol {t}")
        op, args = t[0], t[1:]
        if op == "let":
            saved = dict(self.env)
            for x, d in args[0]:
                self.env[x] = self.tr(d)
            r = self.tr(args[1])
            self.env = saved
            return r
        if not isinstance(op, str):
            raise ValueError(f"higher-order application {sexp_str(t)}")
        if op in UNSUPPORTED_OPS:
            raise ValueError(f"unsupported operator {op}")
        has_list = any(isinstance(self.tr(a)[1], tuple) for a in args)
        if op == "not":
            e, _ = self.tr(args[0])
            return (f"¬{self.paren(e)}", "Prop")
        if op in ("and", "or"):
            if has_list:
                return (f"{'andN' if op == 'and' else 'orN'} {self.paren(self.list_expr(args, 'Prop'))}", "Prop")
            conn = " ∧ " if op == "and" else " ∨ "
            return (conn.join(self.paren(self.tr(a)[0]) for a in args), "Prop")
        if op == "=>":
            return (" → ".join(self.paren(self.tr(a)[0]) for a in args), "Prop")
        if op == "xor":
            assert len(args) == 2
            return (f"XOr {self.paren(self.tr(args[0])[0])} {self.paren(self.tr(args[1])[0])}", "Prop")
        if op in ("=", "distinct"):
            assert len(args) == 2 and not has_list, f"n-ary {op}"
            (a, sa), (b, sb) = self.tr(args[0]), self.tr(args[1])
            s = self.join_sort([sa, sb])
            sym = "=" if op == "=" else "≠"
            return (f"{self.paren(self.cast(a, sa, s))} {sym} {self.paren(self.cast(b, sb, s))}", "Prop")
        if op == "ite":
            c, _ = self.tr(args[0])
            if isinstance(args[0], str) and args[0] in self.env and args[0] not in self.decidable:
                self.decidable.append(args[0])
            (x, sx), (y, sy) = self.tr(args[1]), self.tr(args[2])
            s = self.join_sort([sx, sy])
            return (f"ite {self.paren(c)} {self.paren(self.cast(x, sx, s))} {self.paren(self.cast(y, sy, s))}", s)
        if op in ("<", "<=", ">", ">="):
            (a, sa), (b, sb) = self.tr(args[0]), self.tr(args[1])
            s = self.join_sort([sa, sb])
            sym = {"<": "<", "<=": "≤", ">": ">", ">=": "≥"}[op]
            return (f"{self.paren(self.cast(a, sa, s))} {sym} {self.paren(self.cast(b, sb, s))}", "Prop")
        if op == "-" and len(args) == 1:
            e, s = self.tr(args[0])
            return (f"-{self.paren(e)}", s)
        if op in ("+", "-", "*", "/"):
            if op == "/":
                s = "Rat"
            else:
                s = self.join_sort([self.tr(a)[1] if not isinstance(self.tr(a)[1], tuple)
                                    else self.tr(a)[1][1] for a in args])
            if has_list:
                assert op == "+", f"list arguments of {op}"
                return (f"{s}.addN {self.paren(self.list_expr(args, s))}", s)
            sym = {"+": "+", "-": "-", "*": "*", "/": "/"}[op]
            es = [self.cast(self.tr(a)[0], self.tr(a)[1], s) for a in args]
            return (f" {sym} ".join(self.paren(e) for e in es), s)
        if op == "div":
            (a, _), (b, _) = self.tr(args[0]), self.tr(args[1])
            return (f"{self.paren(a)} / {self.paren(b)}", "Int")
        if op == "mod":
            (a, _), (b, _) = self.tr(args[0]), self.tr(args[1])
            return (f"{self.paren(a)} % {self.paren(b)}", "Int")
        if op == "abs":
            e, s = self.tr(args[0])
            return (f"{self.paren(e)}.abs", s)
        if op == "to_real":
            e, s = self.tr(args[0])
            return (self.cast(e, s, "Rat"), "Rat")
        if op == "to_int":
            e, s = self.tr(args[0])
            return (f"{self.paren(self.cast(e, s, 'Rat'))}.floor", "Int")
        if op == "is_int":
            e, s = self.tr(args[0])
            e = self.paren(self.cast(e, s, "Rat"))
            return (f"{e} = ↑{e}.floor", "Prop")
        raise ValueError(f"unknown operator {op}")

def balanced(s):
    if not (s.startswith("(") and s.endswith(")")):
        return True
    depth = 0
    for i, ch in enumerate(s):
        depth += ch == "("
        depth -= ch == ")"
        if depth == 0 and i < len(s) - 1:
            return False
    return True

# ----------------------------------------------------------------------------------------------
# Statements

def instances(rule):
    syms = symbols(rule.concl, set())
    for p in rule.premises:
        symbols(p, syms)
    arith = bool(syms & ARITH_OPS) or any(NUMERAL.match(x) for x in syms)
    base = lean_ident(rule.name)
    type_vars = list(rule.type_vars)
    for p in rule.params:
        if isinstance(p.sort, str) and TYPE_VAR.match(p.sort) and p.sort not in type_vars:
            type_vars.append(p.sort)
    rule.type_vars = type_vars
    if rule.type_vars and arith:
        return [("int", base + "_int", {tv: "Int" for tv in rule.type_vars}),
                ("rat", base + "_rat", {tv: "Rat" for tv in rule.type_vars})]
    if rule.type_vars:
        return [("mono", base, {tv: "α" for tv in rule.type_vars})]
    return [("mono", base, {})]

def statement(rule, thm, tsub):
    """Returns the theorem header (up to and including `:=`)."""
    tr = Translator(rule, tsub)
    concl, _ = tr.tr(rule.concl)
    hyps = [tr.tr(p)[0] for p in rule.premises]
    binders = []
    if "α" in tsub.values():
        binders.append("{α : Sort u}")
    # explicit parameters in `:args` order, grouped by type; `[Decidable c]` right after `c`
    groups = []
    for a in rule.args:
        n, s = tr.env[a]
        ty = f"List {s[1]}" if isinstance(s, tuple) else s
        if groups and groups[-1][1] == ty and a not in tr.decidable:
            groups[-1][0].append(n)
        else:
            groups.append(([n], ty))
        if a in tr.decidable:
            groups.append(([], f"Decidable {n}"))
    for names, ty in groups:
        binders.append(f"[{ty}]" if not names else f"({' '.join(names)} : {ty})")
    for i, h in enumerate(hyps):
        binders.append(f"(h{i + 1} : {h})")
    head = f"theorem {thm} {' '.join(binders)} :" if binders else f"theorem {thm} :"
    return f"{head}\n    {concl} :="

def existing_proofs(path):
    """Map from block key (`name` or `name (inst)`) to (statement, proof) in the current file."""
    proofs = {}
    if not path.exists():
        return proofs
    text = path.read_text()
    blocks = re.split(r"^-- rare: ", text, flags=re.M)[1:]
    for b in blocks:
        key, _, body = b.partition("\n")
        body = body.split("\n-- end rare-rules")[0]
        stmt, sep, proof = body.partition(":=\n")
        if sep:
            stmt = "\n".join(l for l in stmt.split("\n")
                             if not (l.startswith("/--") or l.startswith("-- NOTE")))
            proofs[key.strip()] = (stmt.strip() + " :=", proof.strip())
    return proofs

HEADER = """/-
Copyright (c) 2021-2026 by the authors listed in the file AUTHORS and their
institutional affiliations. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Haniel Barbosa
-/

-- GENERATED by `Smt/Alethe/Rare/gen.py` from `{src}` (sha256 {sha}).
-- Regenerate after changing the rule file; the proofs below are preserved, everything else is
-- overwritten. A theorem proved by `sorry` makes the checker report its rule as trusted.

module

public import Smt.Alethe.Rare.Basic
public import Smt.Alethe.Lemmas
public import Smt.Reconstruct.Prop.Rewrites
public import Smt.Reconstruct.Builtin.Rewrites
public import Smt.Reconstruct.UF.Rewrites
public import Smt.Reconstruct.Int.Rewrites
public import Smt.Reconstruct.Rat.Rewrites

@[expose] public section

-- premises a proof does not need
set_option linter.unusedVariables false

namespace Smt.Alethe.Rare

open Smt.Reconstruct

universe u

"""

def main():
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name("Rules.lean")
    rules = read_rules(src)
    old = existing_proofs(out)
    sha = hashlib.sha256(src.read_bytes()).hexdigest()[:12]
    lines = [HEADER.format(src=src.name, sha=sha)]
    changed, new, unsupported = [], [], []
    for r in rules:
        try:
            insts = instances(r)
            stmts = [(inst, thm, statement(r, thm, tsub)) for inst, thm, tsub in insts]
        except (ValueError, AssertionError) as e:
            r.unsupported = str(e)
            unsupported.append(r)
            continue
        for inst, thm, stmt in stmts:
            key = r.name if inst == "mono" else f"{r.name} ({inst})"
            lines.append(f"-- rare: {key}")
            lines.append(f"/-- `{sexp_str(r.concl)}` -/")
            proof = "sorry"
            if key in old:
                old_stmt, proof = old[key]
                if old_stmt.strip() != stmt.strip() and proof != "sorry":
                    lines.append("-- NOTE: the statement changed since this proof was written")
                    changed.append(key)
            else:
                new.append(key)
            lines.append(stmt)
            lines.append("  " + proof)
            lines.append("")
            r.instances.append((inst, thm, proof != "sorry"))
    lines.append("-- end rare-rules")
    lines.append("")
    if unsupported:
        lines.append("/-! Rules without a Lean statement (reported as trusted):")
        for r in unsupported:
            lines.append(f"  - `{r.name}`: {r.unsupported}")
        lines.append("-/")
        lines.append("")
    lines.append("/-- The rule table, in the order of the rule file. -/")
    lines.append("def rules : Array RareRule := #[")
    entries = []
    for r in rules:
        args = ", ".join(".list" if next(p for p in r.params if p.name == a).is_list else ".term"
                         for a in r.args)
        thms = ", ".join(f"⟨.{inst}, ``{thm}, {str(proved).lower()}⟩"
                         for inst, thm, proved in r.instances)
        entries.append(f'  {{ name := "{r.name}", args := #[{args}], premises := {len(r.premises)},'
                       f" thms := #[{thms}] }}")
    lines.append(",\n".join(entries))
    lines.append("]")
    lines.append("")
    lines.append("end Smt.Alethe.Rare")
    out.write_text("\n".join(lines))
    sorries = sum(1 for r in rules for _, _, proved in r.instances if not proved)
    print(f"{out}: {len(rules)} rules, {len(unsupported)} without statement, "
          f"{len(new)} new theorems, {sorries} theorems still `sorry`, "
          f"{len(changed)} statements changed under an existing proof")
    if changed:
        print("  changed:", ", ".join(changed))

if __name__ == "__main__":
    main()
