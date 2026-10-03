#!/usr/bin/env python3
"""Measure actual incremental checks and native workloads; never invent timings."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def measure_child(stats_path, command):
    """A fresh helper has one child, so its RSS high-water mark is per stage."""
    start = time.perf_counter()
    result = subprocess.run(command, cwd=ROOT)
    elapsed = time.perf_counter() - start
    try:
        import resource
        usage = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        rss = usage if platform.system() == "Linux" else None
    except ImportError:
        rss = None
    Path(stats_path).write_text(json.dumps({"seconds": elapsed, "peak_rss_kib": rss}))
    raise SystemExit(result.returncode)


def metadata():
    files = sorted(set(ROOT.glob("*.lean")) | set((ROOT / "Mathguard").glob("*.lean")) |
                   set((ROOT / "scripts").glob("*.py")) | set((ROOT / "scripts").glob("*.sh")) |
                   {ROOT / "lean-toolchain", ROOT / "lakefile.toml", ROOT / "lake-manifest.json"})
    return {
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "platform": platform.system(), "machine": platform.machine(),
        "logical_cpus": os.cpu_count(), "python": platform.python_version(),
        "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        "toolchain": (ROOT / "lean-toolchain").read_text().strip(),
        "mathlib_commit": next(p["rev"] for p in json.loads((ROOT / "lake-manifest.json").read_text())["packages"]
                               if p["name"] == "mathlib"),
        "build_mode": "existing dependency cache; two successive incremental Lake builds; no clean Mathlib build",
        "native_quantiles": "quantiles of 15 batch-mean per-operation times; not individual request latency quantiles",
        "rss_scope": "Linux child-command RSS high-water mark; not summed concurrent process-tree memory",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "performance-results")
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument("--lean-files", action="store_true", help="Check each production module with Lean's profiler")
    args = parser.parse_args()
    if not 1 <= args.iterations <= 10000:
        parser.error("iterations must be in 1..10000")
    if shutil.which("lake") is None:
        parser.error("Lake is required; no Lean/native timings collected")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"metadata": metadata(), "stages": [], "native_cases": []}
    report["metadata"]["lean_version"] = subprocess.check_output(["lake", "env", "lean", "--version"], cwd=ROOT, text=True).strip()
    report_file = output / "report.json"

    def stage(name, command):
        log = output / f"{name}.log"
        stats_file = output / f"{name}.stats.json"
        timed = [sys.executable, str(Path(__file__).resolve()), "__measure__", str(stats_file), *command]
        print(f"Measuring {name}: {' '.join(command)}", flush=True)
        with log.open("w") as stream:
            result = subprocess.run(timed, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
        stats = json.loads(stats_file.read_text()) if stats_file.exists() else {}
        report["stages"].append({"stage": name, "command": command,
                                 "seconds": stats.get("seconds"), "peak_rss_kib": stats.get("peak_rss_kib"),
                                 "exit_code": result.returncode})
        report_file.write_text(json.dumps(report, indent=2) + "\n")
        if result.returncode:
            print(log.read_text(), file=sys.stderr)
            raise SystemExit(result.returncode)
        return log

    stage("static_preflight", ["bash", "scripts/check-fast.sh"])
    stage("project_build", ["lake", "build"])
    stage("incremental_build", ["lake", "build"])
    axiom_log = stage("axioms", ["lake", "env", "lean", "scripts/Axioms.lean"])
    stage("fresh_audit", [sys.executable, "scripts/audit_sources.py", "--axioms", str(axiom_log), "--require-extra"])
    stage("demo", [str(ROOT / ".lake/build/bin/mathguard")])
    stage("native_tests", ["lake", "exe", "mathguard-tests"])
    if args.lean_files:
        for path in sorted((ROOT / "Mathguard").glob("*.lean")):
            stage(f"lean_{path.stem}", ["lake", "env", "lean", "-Dprofiler=true",
                                        "-Dprofiler.threshold=10", str(path.relative_to(ROOT))])
    stage("benchmark_build", ["lake", "build", "mathguard-bench"])
    log = stage("native_benchmarks", [str(ROOT / ".lake/build/bin/mathguard-bench"), str(args.iterations)])
    rows = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    if len(rows) != 40:
        raise ValueError(f"Expected 40 native measurements; received {len(rows)}")
    report["native_cases"] = rows
    report_file.write_text(json.dumps(report, indent=2) + "\n")
    with (output / "native.csv").open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Measured report: {report_file}")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "__measure__":
        measure_child(sys.argv[2], sys.argv[3:])
    else:
        main()
