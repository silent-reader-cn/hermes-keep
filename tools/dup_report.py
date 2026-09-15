#!/usr/bin/env python3
"""Code duplication gate backed by jscpd.

Measures duplicated lines/tokens for a scope, compares the result against a
stored baseline, and exits non-zero when duplication grows past
baseline + tolerance.

Why this exists: duplication was never measured in this repo, so nobody could
tell whether a change made it worse. This turns that into a runnable gate.

Exit codes:
    0 = measured duplication within budget (or baseline just created/updated)
    1 = duplication exceeds baseline + tolerance
    2 = tooling problem (jscpd missing, no JSON report, bad input)

All output is ASCII only. CI windows runners use a cp1252 stdout and crash on
non-ASCII prints, so keep this file and its output plain ASCII.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

JSCPD_VERSION = "4.3.0"

# jscpd ignore globs shared by every scope.
# golden/ holds large reference screenshots and diagnostics, never source.
IGNORE_GLOBS = "**/golden/**,**/build/**,**/.dart_tool/**"

SCOPE_PATHS = {
    "lib": ["lib"],
    "lib+test": ["lib", "test"],
    "all": ["lib", "test", "tools", "scripts", "android/app/src"],
}

EXIT_OK = 0
EXIT_OVER_BUDGET = 1
EXIT_TOOLING = 2


def configure_stdout() -> None:
    """Force UTF-8 on stdout/stderr where possible (cp1252 safety net)."""
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is not None:
            try:
                reconfigure(encoding="utf-8", errors="replace")
            except (ValueError, OSError):
                pass


def find_npx() -> str | None:
    for name in ("npx", "npx.cmd", "npx.exe"):
        found = shutil.which(name)
        if found:
            return found
    return None


def run_jscpd(
    paths: list[str],
    min_lines: int,
    min_tokens: int,
    workdir: str,
    outdir: str,
) -> dict:
    """Run jscpd and return its parsed JSON report."""
    npx = find_npx()
    if npx is None:
        print(
            "ERROR: npx not found on PATH. jscpd needs Node.js installed.",
            file=sys.stderr,
        )
        sys.exit(EXIT_TOOLING)

    cmd = [
        npx,
        "--yes",
        "jscpd@%s" % JSCPD_VERSION,
        *paths,
        "--min-lines",
        str(min_lines),
        "--min-tokens",
        str(min_tokens),
        "--reporters",
        "json",
        "--output",
        outdir,
        "--ignore",
        IGNORE_GLOBS,
    ]

    try:
        proc = subprocess.run(
            cmd,
            cwd=workdir,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=1800,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print("ERROR: failed to run jscpd: %r" % (exc,), file=sys.stderr)
        sys.exit(EXIT_TOOLING)

    report_path = os.path.join(outdir, "jscpd-report.json")
    if not os.path.exists(report_path):
        tail = (proc.stdout or "").strip().splitlines()[-15:]
        errtail = (proc.stderr or "").strip().splitlines()[-15:]
        print("ERROR: jscpd produced no JSON report.", file=sys.stderr)
        print("--- jscpd stdout tail ---", file=sys.stderr)
        for line in tail:
            print(line, file=sys.stderr)
        print("--- jscpd stderr tail ---", file=sys.stderr)
        for line in errtail:
            print(line, file=sys.stderr)
        sys.exit(EXIT_TOOLING)

    with open(report_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def extract_stats(report: dict) -> dict:
    total = (report.get("statistics") or {}).get("total") or {}
    return {
        "duplicated_lines_pct": round(float(total.get("percentage", 0.0)), 2),
        "duplicated_tokens_pct": round(float(total.get("percentageTokens", 0.0)), 2),
        "clones": int(total.get("clones", 0)),
        "total_lines": int(total.get("lines", 0)),
        "total_tokens": int(total.get("tokens", 0)),
        "sources": int(total.get("sources", 0)),
        "duplicated_lines": int(total.get("duplicatedLines", 0)),
    }


def top_duplicates(report: dict, limit: int = 10) -> list[dict]:
    rows = []
    for dup in report.get("duplicates") or []:
        first = dup.get("firstFile") or {}
        second = dup.get("secondFile") or {}
        rows.append(
            {
                "lines": int(dup.get("lines", 0)),
                "tokens": int(dup.get("tokens", 0)),
                "a": "%s:%s" % (first.get("name", "?"), first.get("start", "?")),
                "b": "%s:%s" % (second.get("name", "?"), second.get("start", "?")),
            }
        )
    rows.sort(key=lambda row: (-row["lines"], -row["tokens"], row["a"]))
    return rows[:limit]


def worst_files(report: dict, limit: int = 10) -> list[tuple[str, int]]:
    agg: dict[str, int] = {}
    for dup in report.get("duplicates") or []:
        for key in ("firstFile", "secondFile"):
            name = (dup.get(key) or {}).get("name")
            if not name:
                continue
            agg[name] = agg.get(name, 0) + int(dup.get("lines", 0))
    return sorted(agg.items(), key=lambda item: (-item[1], item[0]))[:limit]


def load_baseline(path: str) -> dict | None:
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        print("ERROR: cannot read baseline %s: %r" % (path, exc), file=sys.stderr)
        sys.exit(EXIT_TOOLING)
    if not isinstance(data, dict):
        print("ERROR: baseline %s is not a JSON object." % path, file=sys.stderr)
        sys.exit(EXIT_TOOLING)
    return data


def baseline_entry(baseline: dict | None, scope: str) -> dict | None:
    if not baseline:
        return None
    scopes = baseline.get("scopes")
    if not isinstance(scopes, dict):
        return None
    entry = scopes.get(scope)
    return entry if isinstance(entry, dict) else None


def save_baseline(path: str, baseline: dict) -> None:
    directory = os.path.dirname(os.path.abspath(path))
    if directory and not os.path.isdir(directory):
        os.makedirs(directory, exist_ok=True)
    payload = json.dumps(baseline, indent=2, sort_keys=True) + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)


def print_measurement(scope: str, paths: list[str], stats: dict, min_lines: int, min_tokens: int) -> None:
    print("=" * 72)
    print("Code duplication report")
    print("=" * 72)
    print("scope              : %s (%s)" % (scope, ", ".join(paths)))
    print("threshold          : min-lines=%d min-tokens=%d" % (min_lines, min_tokens))
    print("jscpd version      : %s" % JSCPD_VERSION)
    print("-" * 72)
    print("files analyzed     : %d" % stats["sources"])
    print("total lines        : %d" % stats["total_lines"])
    print("duplicated lines   : %d" % stats["duplicated_lines"])
    print("duplicated lines %% : %.2f" % stats["duplicated_lines_pct"])
    print("duplicated tokens %%: %.2f" % stats["duplicated_tokens_pct"])
    print("clones found       : %d" % stats["clones"])
    print("-" * 72)


def print_top(report: dict) -> None:
    rows = top_duplicates(report, limit=10)
    if not rows:
        print("top clones         : none")
        return
    print("top 10 largest clones:")
    for row in rows:
        print(
            "  %4d lines / %5d tokens | %s  <->  %s"
            % (row["lines"], row["tokens"], row["a"], row["b"])
        )


def main(argv: list[str] | None = None) -> int:
    configure_stdout()

    parser = argparse.ArgumentParser(
        description="Measure code duplication with jscpd and compare against a baseline.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "exit codes: 0 = within budget, 1 = over budget, 2 = tooling error\n"
            "example: python tools/dup_report.py --scope lib --baseline tools/dup_baseline.json"
        ),
    )
    parser.add_argument("--scope", choices=sorted(SCOPE_PATHS), default="lib",
                        help="which source set to measure (default: lib)")
    parser.add_argument("--min-lines", type=int, default=5,
                        help="jscpd minimum clone size in lines (default: 5)")
    parser.add_argument("--min-tokens", type=int, default=50,
                        help="jscpd minimum clone size in tokens (default: 50)")
    parser.add_argument("--baseline", default="tools/dup_baseline.json",
                        help="baseline JSON path (default: tools/dup_baseline.json)")
    parser.add_argument("--tolerance", type=float, default=0.5,
                        help="allowed growth in percentage points (default: 0.5)")
    parser.add_argument("--json", dest="json_out", default=None,
                        help="optional path to write this run's summary as JSON")
    parser.add_argument("--update-baseline", action="store_true",
                        help="write this run's numbers into the baseline file")
    parser.add_argument("--workdir", default=".",
                        help="repository root to scan (default: current directory)")
    args = parser.parse_args(argv)

    workdir = os.path.abspath(args.workdir)
    paths = SCOPE_PATHS[args.scope]

    missing = [path for path in paths if not os.path.exists(os.path.join(workdir, path))]
    if missing:
        print("ERROR: scope path(s) not found under %s: %s"
              % (workdir, ", ".join(missing)), file=sys.stderr)
        return EXIT_TOOLING

    baseline = load_baseline(args.baseline)

    with tempfile.TemporaryDirectory(prefix="dup-report-") as outdir:
        report = run_jscpd(paths, args.min_lines, args.min_tokens, workdir, outdir)

    stats = extract_stats(report)
    print_measurement(args.scope, paths, stats, args.min_lines, args.min_tokens)
    print_top(report)

    if args.update_baseline:
        if baseline is None:
            baseline = {}
        baseline.setdefault("min_lines", args.min_lines)
        baseline.setdefault("min_tokens", args.min_tokens)
        baseline["min_lines"] = args.min_lines
        baseline["min_tokens"] = args.min_tokens
        baseline["generated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        scopes = baseline.setdefault("scopes", {})
        scopes[args.scope] = {
            "duplicated_lines_pct": stats["duplicated_lines_pct"],
            "duplicated_tokens_pct": stats["duplicated_tokens_pct"],
            "clones": stats["clones"],
            "total_lines": stats["total_lines"],
            "duplicated_lines": stats["duplicated_lines"],
            "sources": stats["sources"],
        }
        save_baseline(args.baseline, baseline)
        print("-" * 72)
        print("baseline updated   : %s (scope=%s -> %.2f%%)"
              % (args.baseline, args.scope, stats["duplicated_lines_pct"]))
        if args.json_out:
            write_json(args.json_out, args.scope, stats, None, args.tolerance, "baseline_updated")
        return EXIT_OK

    entry = baseline_entry(baseline, args.scope)

    summary = {
        "scope": args.scope,
        "threshold": {"min_lines": args.min_lines, "min_tokens": args.min_tokens},
        "jscpd_version": JSCPD_VERSION,
        "measured": stats,
    }

    if entry is None:
        print("-" * 72)
        print("baseline           : none for scope=%s (%s)" % (args.scope, args.baseline))
        print("status             : BASELINE CREATED (nothing to compare against yet)")
        print("                     rerun with --update-baseline to persist it")
        summary["status"] = "baseline_missing"
        if args.json_out:
            write_json(args.json_out, args.scope, stats, None, args.tolerance, "baseline_missing")
        return EXIT_OK

    baseline_pct = float(entry.get("duplicated_lines_pct", 0.0))
    allowed = baseline_pct + args.tolerance
    delta = round(stats["duplicated_lines_pct"] - baseline_pct, 2)

    summary["baseline"] = entry
    summary["tolerance"] = args.tolerance
    summary["allowed_max_pct"] = round(allowed, 2)
    summary["delta_pct"] = delta

    print("-" * 72)
    print("baseline (%s)      : %.2f%%  (clones=%s, recorded %s)"
          % (args.scope, baseline_pct, entry.get("clones", "?"),
             entry.get("generated_at", entry.get("recorded_at", "unknown"))))
    print("current  (%s)      : %.2f%%  (clones=%d)"
          % (args.scope, stats["duplicated_lines_pct"], stats["clones"]))
    print("tolerance          : %.2f pts -> allowed max %.2f%%"
          % (args.tolerance, allowed))
    print("delta              : %+.2f pts" % delta)

    if stats["duplicated_lines_pct"] > allowed:
        print("status             : FAIL - duplication grew past budget")
        print("-" * 72)
        print("files contributing the most duplicated lines:")
        for name, lines in worst_files(report, limit=10):
            print("  %5d lines  %s" % (lines, name))
        print("-" * 72)
        print("Either refactor the duplication above, or (if the growth is")
        print("intentional) refresh the baseline with --update-baseline.")
        summary["status"] = "fail"
        if args.json_out:
            write_json(args.json_out, args.scope, stats, entry, args.tolerance, "fail")
        return EXIT_OVER_BUDGET

    print("status             : PASS")
    summary["status"] = "pass"
    if args.json_out:
        write_json(args.json_out, args.scope, stats, entry, args.tolerance, "pass")
    return EXIT_OK


def write_json(path: str, scope: str, stats: dict, entry: dict | None,
               tolerance: float, status: str) -> None:
    payload = {
        "scope": scope,
        "status": status,
        "tolerance": tolerance,
        "measured": stats,
        "baseline": entry,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    directory = os.path.dirname(os.path.abspath(path))
    if directory and not os.path.isdir(directory):
        os.makedirs(directory, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    sys.exit(main())
