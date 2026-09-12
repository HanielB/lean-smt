#!/usr/bin/env python3
"""Box plots of per-rule step times, from the CSVs `#check_alethe … csv "<dir>"` writes.

Those files are carcara's (`carcara bench --dump-to-csv`): `steps.csv` is one row per step with
the rule in field 1 and the nanoseconds it took in field 2, `runs.csv` one row for the whole run.
So the same plots serve either checker, and both can go on one figure.

  rule-boxplots.pdf/.png   distribution of the per-rule step time, log scale, for the top rules
                           by total time; total step count annotated above each box
  rule-totals.pdf/.png     aggregate time per rule

With four or more proofs per configuration each box is the distribution over proofs of the
per-proof *mean* step time, as in ~/exp/alethe-bv/rule-boxplots.py; with fewer there is nothing
to average over and each box is the distribution over the individual steps. `--by` overrides.

Two things to know before reading a lean-smt series against a carcara one. carcara names every
RARE step `rare_rewrite`, where lean-smt names it `rare_rewrite:<rule>` — `--fold-rare` drops the
suffix so that the two line up. And carcara has rows lean-smt has no counterpart for: `assume`
(lean-smt reports binding the assumptions in the `assume` column of runs.csv, not as steps) and
`anchor(…)` (lean-smt charges opening a subproof to the step that closes it).

Usage:
  scripts/rule-boxplots.py [options] SPEC [SPEC ...]

    SPEC        [label:]path — a directory holding steps.csv, a directory tree searched for them
                (one proof each), or a steps.csv itself. SPECs sharing a label are one
                configuration, drawn as one series; the default label is the path's basename.

  -o, --out DIR   where to write the plots (default: plots)
  -q, --quiet     only warnings: no step counts, no list of what was written
  -n, --top N     rules to show, by total time (default: 25)
  --by {proof,step,auto}
  --title TEXT    replaces the generated title
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# the house colours: ~/exp/alethe-bv/rule-boxplots.py's blue first
COLORS = ['#2a78d6', '#d6572a', '#2ab07a', '#8c5ad6', '#b0982a']


def find_steps(path):
    """The steps.csv files under `path`, one per proof."""
    if os.path.isfile(path):
        return [path]
    direct = os.path.join(path, 'steps.csv')
    if os.path.isfile(direct):
        return [direct]
    found = []
    for root, _, files in os.walk(path):
        if 'steps.csv' in files:
            found.append(os.path.join(root, 'steps.csv'))
    return sorted(found)


def fold(rule, fold_rare):
    return rule.split(':', 1)[0] if fold_rare and rule.startswith('rare_rewrite:') else rule


def read_steps(path):
    """(rule, nanoseconds) of every step, by field position: the trailing columns lean-smt adds
       to carcara's two are ignored here."""
    rows = []
    with open(path, newline='') as f:
        r = csv.reader(f)
        head = next(r, None)
        if head is None:
            return rows
        if head[:2] != ['rule', 'time']:          # headerless file: it was a row
            r = [head] + list(r)
        for row in r:
            if len(row) < 2:
                continue
            try:
                rows.append((row[0], int(row[1])))
            except ValueError:
                continue
    return rows


def load(specs, fold_rare):
    """{label: {proof: {rule: [times]}}}, in the order the labels first appear."""
    data = {}
    for spec in specs:
        label, _, path = spec.partition(':') if ':' in spec else ('', '', spec)
        if not label:
            label = os.path.basename(os.path.normpath(path)) or path
        files = find_steps(path)
        if not files:
            sys.exit(f'no steps.csv under {path}')
        proofs = data.setdefault(label, {})
        for f in files:
            by_rule = proofs.setdefault(f, defaultdict(list))
            for rule, ns in read_steps(f):
                by_rule[fold(rule, fold_rare)].append(ns)
    return data


def samples(proofs, rule, by):
    """The values one box is drawn from, in seconds."""
    if by == 'proof':
        return [sum(r[rule]) / len(r[rule]) / 1e9 for r in proofs.values() if rule in r]
    return [ns / 1e9 for r in proofs.values() for ns in r.get(rule, ())]


def style(ax):
    ax.spines[['top', 'right']].set_visible(False)
    ax.grid(axis='y', color='#dddddd', linewidth=0.6)
    ax.set_axisbelow(True)


def fmt_count(n):
    if n >= 1e6:
        return '%.0fM' % (n / 1e6)
    if n >= 1e3:
        return '%.0fk' % (n / 1e3)
    return str(n)


def draw_box(ax, vals, pos, width, color):
    bp = ax.boxplot(vals, positions=[pos], widths=width,
                    whis=(5, 95), showfliers=False, patch_artist=True)
    bp['boxes'][0].set(facecolor=color + '55', edgecolor=color, linewidth=1.2)
    for el in ('whiskers', 'caps'):
        for a in bp[el]:
            a.set(color=color, linewidth=1.0)
    bp['medians'][0].set(color=color, linewidth=1.6)


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('specs', nargs='+', metavar='SPEC')
    ap.add_argument('-o', '--out', default='plots')
    ap.add_argument('-n', '--top', type=int, default=25)
    ap.add_argument('--by', choices=('proof', 'step', 'auto'), default='auto')
    ap.add_argument('--fold-rare', action='store_true',
                    help="count every rare_rewrite:<rule> as rare_rewrite, as carcara does")
    ap.add_argument('--title', default=None)
    ap.add_argument('-q', '--quiet', action='store_true',
                    help='only warnings: no step counts, no list of what was written')
    args = ap.parse_args()

    data = load(args.specs, args.fold_rare)
    labels = list(data)
    by = args.by
    if by == 'auto':
        by = 'proof' if min(len(p) for p in data.values()) >= 4 else 'step'

    for label, proofs in data.items():
        n = sum(len(v) for r in proofs.values() for v in r.values())
        if not args.quiet:
            print(f'{label}: {n} steps over {len(proofs)} proof(s)')
    if not args.fold_rare and len(labels) > 1:
        split = {l for l, ps in data.items()
                 if any(r.startswith('rare_rewrite:') for p in ps.values() for r in p)}
        if split and split != set(labels):
            print('note: %s name RARE steps rare_rewrite:<rule> and the rest name them '
                  'rare_rewrite; pass --fold-rare to line them up' % ', '.join(sorted(split)))

    # total time and step count per rule, over every configuration: what ranks the rules
    total = defaultdict(float)
    count = defaultdict(int)
    per_cfg_total = {l: defaultdict(float) for l in labels}
    per_cfg_count = {l: defaultdict(int) for l in labels}
    for label, proofs in data.items():
        for by_rule in proofs.values():
            for rule, times in by_rule.items():
                total[rule] += sum(times)
                count[rule] += len(times)
                per_cfg_total[label][rule] += sum(times)
                per_cfg_count[label][rule] += len(times)

    def counts(rule):
        """The step count shown above a rule: per configuration, in legend order."""
        if len(labels) == 1:
            return fmt_count(count[rule])
        return '/'.join(fmt_count(per_cfg_count[l][rule]) for l in labels)
    top = sorted(total, key=total.get, reverse=True)[:args.top]
    if not top:
        sys.exit('no steps found')

    os.makedirs(args.out, exist_ok=True)
    unit = ('mean step time per proof (s)' if by == 'proof' else 'step time (s)')

    # ---- box plot -------------------------------------------------------
    fig, ax = plt.subplots(figsize=(12, 5.5))
    k = len(labels)
    width = 0.8 / k
    for j, label in enumerate(labels):
        color = COLORS[j % len(COLORS)]
        offset = (j - (k - 1) / 2) * width
        for i, rule in enumerate(top):
            vals = samples(data[label], rule, by)
            if vals:
                draw_box(ax, vals, i + offset, width * 0.85, color)
        if k > 1:
            ax.plot([], [], color=color, linewidth=6, alpha=0.55, label=label)
    ax.set_yscale('log')
    ax.set_xticks(range(len(top)))
    ax.set_xticklabels(top, rotation=45, ha='right', fontsize=8)
    ax.set_xlim(-0.7, len(top) - 0.3)
    # total step count above each rule, at the 95th percentile of the highest series
    for i, rule in enumerate(top):
        ys = [v for label in labels for v in samples(data[label], rule, by)]
        if not ys:
            continue
        ys.sort()
        y = ys[min(len(ys) - 1, int(0.95 * len(ys)))]
        ax.annotate(counts(rule), (i, y), textcoords='offset points',
                    xytext=(0, 6), ha='center', fontsize=6.5, color='#555555')
    ax.set_ylabel(unit)
    ax.set_title(args.title or
                 ('per-rule step times, top %d rules by total time (boxes: 25-75%%, '
                  'whiskers: 5-95%%; labels: step count%s)'
                  % (len(top), ', per series' if len(labels) > 1 else '')), fontsize=10)
    if k > 1:
        ax.legend(frameon=False, fontsize=9)
    style(ax)
    fig.tight_layout()
    for ext in ('pdf', 'png'):
        fig.savefig(f'{args.out}/rule-boxplots.{ext}', dpi=200)
    plt.close(fig)

    # ---- bar chart: aggregate time by rule ------------------------------
    fig, ax = plt.subplots(figsize=(12, 5))
    for j, label in enumerate(labels):
        vals = [per_cfg_total[label][rule] / 1e9 for rule in top]
        xs = [i + (j - (k - 1) / 2) * width for i in range(len(top))]
        ax.bar(xs, vals, width=width * 0.85, color=COLORS[j % len(COLORS)],
               label=label if k > 1 else None)
    ax.set_yscale('log')
    ax.set_xticks(range(len(top)))
    ax.set_xticklabels(top, rotation=45, ha='right', fontsize=8)
    ax.set_xlim(-0.7, len(top) - 0.3)
    for i, rule in enumerate(top):
        ax.annotate(counts(rule), (i, total[rule] / 1e9),
                    textcoords='offset points', xytext=(0, 3),
                    ha='center', fontsize=6.5, color='#555555')
    ax.set_ylabel('total checking time (s)')
    ax.set_title(args.title or 'aggregate time by rule over all checked proofs '
                               '(labels: total step count)', fontsize=10)
    if k > 1:
        ax.legend(frameon=False, fontsize=9)
    style(ax)
    fig.tight_layout()
    for ext in ('pdf', 'png'):
        fig.savefig(f'{args.out}/rule-totals.{ext}', dpi=200)
    plt.close(fig)

    if not args.quiet:
        print('wrote', ', '.join(f'{args.out}/rule-{n}.{{pdf,png}}'
                                 for n in ('boxplots', 'totals')))


if __name__ == '__main__':
    main()
