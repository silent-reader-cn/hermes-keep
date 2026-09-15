#!/usr/bin/env python3
"""Line-coverage summary and gate for the hermes-ui Flutter repo.

Reads `coverage/lcov.info` (produced by `flutter test --coverage`) and reports
line coverage for `lib/`, with generated sources excluded from both numerator
and denominator.

Why this script exists instead of a one-liner in CI:

* **Accounting rule.** `flutter test --coverage` instruments generated sources
  too (`*.g.dart`, `*.freezed.dart`, `l10n/app_localizations*.dart`). Those are
  machine-written and mostly hit as a side effect of widget tests, so counting
  them inflates or deflates the number at random as generators change. The gate
  must compare like with like, so the exclusions live here, in one place.
* **Unloaded files are invisible.** A source file that no test ever imports does
  not appear in lcov.info at all. Naively parsing the file therefore reports a
  *higher* coverage than reality, because those files count as zero lines rather
  than zero-covered lines. `--check-unloaded` compares the lcov contents against
  the files on disk and folds the missing ones into the denominator, so the gate
  cannot be gamed by simply deleting a test file.

Usage:
    python tools/coverage_summary.py                       # human report
    python tools/coverage_summary.py --check-unloaded      # + disk reconciliation
    python tools/coverage_summary.py --baseline tools/coverage_baseline.json
    python tools/coverage_summary.py --update-baseline tools/coverage_baseline.json
    python tools/coverage_summary.py --json coverage/summary.json

Exit code is non-zero when the gate fails (below `--min` or below the baseline).

Output is deliberately English-only: this runs on Windows runners whose Python
stdout defaults to cp1252, where printing CJK raises UnicodeEncodeError and
kills the job before it reports anything.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

# Generated sources are excluded from BOTH sides of the ratio.
GENERATED_SUFFIXES = (".g.dart", ".freezed.dart", ".mocks.dart", ".gr.dart")
GENERATED_MARKERS = ("l10n/app_localizations",)

# Files that legitimately never load in unit tests. Kept explicit (rather than
# a broad glob) so that anything else showing up as unloaded is a real finding
# the gate should surface.
EXPECTED_UNLOADED = (
    "lib/driver_main.dart",              # flutter_driver integration entrypoint
    "lib/core/cache/app_database_connection_web.dart",  # conditional-import stub
    "lib/core/cache/app_database_connection.dart",      # conditional-import stub
    # Pure top-level `const` library: Dart constant-folds it at compile time, so it
    # has no executable lines and can never appear in lcov. Counting it as uncovered
    # would punish code that has nothing to cover.
    "lib/app/theme/status_colors.dart",
)


def setup_stdout() -> None:
    """Force UTF-8 so Windows cp1252 stdout cannot crash the job."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):  # pragma: no cover - old runtimes
            pass


def rel_lib_path(sf: str) -> str | None:
    """Normalise an lcov `SF:` value to a repo-relative `lib/...` path."""
    p = sf.strip().replace("\\", "/")
    if p.startswith("lib/"):
        return p
    idx = p.find("/lib/")
    if idx >= 0:
        return p[idx + 1:]
    return None


def is_excluded(rel: str) -> bool:
    if rel.endswith(GENERATED_SUFFIXES):
        return True
    return any(marker in rel for marker in GENERATED_MARKERS)


def parse_lcov(path: str) -> dict[str, list[int]]:
    """Return {rel_path: [lines_hit, lines_found]} for lib/ sources."""
    files: dict[str, list[int]] = {}
    current: str | None = None
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("SF:"):
                rel = rel_lib_path(line[3:])
                current = rel
                if rel is not None:
                    files.setdefault(rel, [0, 0])
            elif line.startswith("DA:") and current is not None:
                parts = line[3:].split(",")
                if len(parts) < 2:
                    continue
                try:
                    hits = int(parts[1])
                except ValueError:
                    continue
                files[current][1] += 1
                if hits > 0:
                    files[current][0] += 1
            elif line == "end_of_record":
                current = None
    return files


def count_executable_lines(path: str) -> int:
    """Heuristic count of executable Dart lines in one file.

    Used only for sources that never load in tests, where lcov has no entry to
    read. Strips blanks, comments, imports/parts and lone closing braces. This
    is an upper-bound-ish estimate and is reported as such; it exists so that
    wholly untested files cost the gate *something* instead of nothing.
    """
    total = 0
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                s = raw.strip()
                if not s:
                    continue
                if s.startswith(("//", "*", "/*")):
                    continue
                if s.startswith(("import ", "export ", "part ", "library ")):
                    continue
                if s in ("}", "};", ")", ");", "});", "],", "),"):
                    continue
                total += 1
    except OSError:
        return 0
    return total


def find_unloaded(files: dict[str, list[int]], repo_root: str) -> list[tuple[str, int]]:
    """Sources on disk that lcov never mentioned -> (rel_path, exec_lines).

    Generated sources are skipped here too: they are excluded from the ratio on
    the lcov side, so folding them into the denominator just because no test
    happened to import one would contradict the accounting rule and silently
    depress the number (a generated file can be thousands of lines).
    """
    lib_root = os.path.join(repo_root, "lib")
    missing: list[tuple[str, int]] = []
    for dirpath, _dirnames, filenames in os.walk(lib_root):
        for name in filenames:
            if not name.endswith(".dart"):
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, repo_root).replace("\\", "/")
            if rel in files or is_excluded(rel):
                continue
            missing.append((rel, count_executable_lines(full)))
    missing.sort(key=lambda item: -item[1])
    return missing


def bucket_of(rel: str) -> str:
    """Group a lib path into a reporting area (features/<x>, core/<x>, ...)."""
    parts = rel.split("/")
    if len(parts) < 2:
        return "(root)"
    if parts[1] in ("features", "core") and len(parts) >= 3:
        return f"{parts[1]}/{parts[2]}"
    return parts[1]


def main() -> int:
    setup_stdout()

    ap = argparse.ArgumentParser(description="hermes-ui line coverage summary and gate")
    ap.add_argument("--lcov", default=os.path.join("coverage", "lcov.info"))
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--min", type=float, default=None,
                    help="Hard floor in percent; below it the gate fails.")
    ap.add_argument("--baseline", default=None,
                    help="JSON baseline; gate fails if coverage falls below it.")
    ap.add_argument("--tolerance", type=float, default=0.0,
                    help="Allowed slack in percentage points when comparing to the baseline.")
    ap.add_argument("--update-baseline", default=None, metavar="PATH",
                    help="Write current coverage to PATH as the new baseline.")
    ap.add_argument("--check-unloaded", action="store_true",
                    help="Also scan lib/ for sources lcov never loaded.")
    ap.add_argument("--json", dest="json_out", default=None,
                    help="Also write a machine-readable summary to PATH.")
    ap.add_argument("--top", type=int, default=15, help="Rows in the gap tables.")
    args = ap.parse_args()

    if not os.path.exists(args.lcov):
        print(f"ERROR: lcov file not found: {args.lcov}")
        print("       Run `flutter test --coverage` first.")
        return 2

    files = parse_lcov(args.lcov)
    counted = {k: v for k, v in files.items() if not is_excluded(k)}

    hit = sum(v[0] for v in counted.values())
    found = sum(v[1] for v in counted.values())

    unloaded: list[tuple[str, int]] = []
    unloaded_exec = 0
    if args.check_unloaded:
        unloaded = find_unloaded(files, args.repo_root)
        # Only files OUTSIDE the expected list are folded into the denominator:
        # the listed ones have no executable lines for tests to reach.
        unloaded_exec = sum(
            n for rel, n in unloaded if rel not in EXPECTED_UNLOADED
        )
        found += unloaded_exec

    pct = (100.0 * hit / found) if found else 0.0

    print("=" * 72)
    print("hermes-ui line coverage (lib/, generated sources excluded)")
    print("=" * 72)
    print(f"  lines hit          : {hit}")
    print(f"  lines countable    : {found}")
    print(f"  coverage           : {pct:.2f}%")
    print(f"  files measured     : {len(counted)}")

    if args.check_unloaded:
        print(f"  never loaded       : {len(unloaded)} files "
              f"(+{unloaded_exec} est. lines folded into denominator)")
        for rel, n in unloaded[: args.top]:
            flag = "expected" if rel in EXPECTED_UNLOADED else "REVIEW"
            print(f"      [{flag:8}] {rel} (~{n} lines)")
        if len(unloaded) > args.top:
            print(f"      ... and {len(unloaded) - args.top} more "
                  f"(raise --top to list them all)")

    buckets: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for rel, (h, t) in counted.items():
        b = buckets[bucket_of(rel)]
        b[0] += h
        b[1] += t

    print()
    print("by area (worst first):")
    for name in sorted(buckets, key=lambda k: (buckets[k][0] / buckets[k][1]) if buckets[k][1] else 1.0):
        h, t = buckets[name]
        if t < 40:
            continue
        print(f"  {name:<28} {h:6d}/{t:<6d} {100.0 * h / t:6.1f}%")

    gaps = sorted(((t - h, t, h, rel) for rel, (h, t) in counted.items()), reverse=True)
    print()
    print(f"largest gaps (top {args.top} of {sum(1 for g in gaps if g[0] > 0)} files with gaps):")
    for miss, t, h, rel in gaps[:args.top]:
        print(f"  {miss:5d} uncovered / {t:5d} lines  {100.0 * h / t:5.1f}%  {rel}")

    # ---- gate -------------------------------------------------------------
    failures: list[str] = []
    if args.min is not None and pct < args.min:
        failures.append(f"coverage {pct:.2f}% is below the hard floor {args.min:.2f}%")

    baseline_pct = None
    if args.baseline and os.path.exists(args.baseline):
        try:
            with open(args.baseline, "r", encoding="utf-8") as fh:
                base = json.load(fh)
            baseline_pct = float(base.get("line_coverage_pct"))
        except (OSError, ValueError, TypeError) as exc:
            failures.append(f"baseline {args.baseline} is unreadable: {exc}")
        else:
            floor = baseline_pct - args.tolerance
            if pct < floor:
                failures.append(
                    f"coverage {pct:.2f}% fell below baseline {baseline_pct:.2f}% "
                    f"(tolerance {args.tolerance:.2f})"
                )
            else:
                print()
                print(f"baseline check: {pct:.2f}% >= {baseline_pct:.2f}% "
                      f"(tolerance {args.tolerance:.2f}) OK")
    elif args.baseline:
        print()
        print(f"baseline check: SKIPPED ({args.baseline} not found)")

    if args.update_baseline:
        payload = {
            "line_coverage_pct": round(pct, 2),
            "lines_hit": hit,
            "lines_countable": found,
            "files_measured": len(counted),
            "note": "Ratchet this upward as tests are added; never lower it silently.",
        }
        if args.check_unloaded:
            payload["never_loaded_files"] = [rel for rel, _n in unloaded]
        tmp = args.update_baseline + ".tmp"
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, args.update_baseline)
        print()
        print(f"baseline written: {args.update_baseline} -> {pct:.2f}%")

    if args.json_out:
        payload = {
            "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "line_coverage_pct": round(pct, 2),
            "lines_hit": hit,
            "lines_countable": found,
            "files_measured": len(counted),
            "gate_min": args.min,
            "gate_baseline_pct": baseline_pct,
            "gate_failures": failures,
            "areas": {
                name: {
                    "lines_hit": v[0],
                    "lines_countable": v[1],
                    "pct": round(100.0 * v[0] / v[1], 2) if v[1] else 0.0,
                }
                for name, v in sorted(buckets.items())
            },
            "worst_files": [
                {"path": rel, "uncovered": miss, "lines": t, "pct": round(100.0 * h / t, 2)}
                for miss, t, h, rel in gaps[: args.top]
            ],
            "never_loaded_files": [rel for rel, _n in unloaded],
        }
        os.makedirs(os.path.dirname(os.path.abspath(args.json_out)), exist_ok=True)
        with open(args.json_out, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, indent=2, ensure_ascii=False)
            fh.write("\n")
        print(f"json written: {args.json_out}")

    print()
    if failures:
        print("COVERAGE GATE FAILED:")
        for item in failures:
            print(f"  - {item}")
        return 1
    print("COVERAGE GATE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
