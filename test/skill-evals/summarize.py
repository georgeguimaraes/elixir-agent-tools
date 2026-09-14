#!/usr/bin/env python3
"""Summarize completed skill-eval records without treating missing trials as failures."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from statistics import median


CONDITIONS = ("baseline", "corrected", "pruned")


def read_json(path):
    return json.loads(path.read_text())


def provenance(path):
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def metric(values):
    numbers = [v for v in values if type(v) in (int, float)]
    return {"median": median(numbers) if numbers else None, "samples": len(numbers)}


def aggregate(rows, expected=None):
    valid = [r for r in rows if r.get("valid_run") is True]
    usage = [r.get("usage", {}) for r in valid]
    tokens = [u["input_tokens"] + u["output_tokens"]
              for u in usage if type(u.get("input_tokens")) is int and type(u.get("output_tokens")) is int]
    return {
        "observed": len(rows), "expected": expected,
        "missing": expected - len(rows) if expected is not None else None,
        "valid": len(valid), "invalid_or_unknown_validity": len(rows) - len(valid),
        "passed": sum(r.get("passed") is True for r in valid),
        "agent_seconds": metric(r.get("agent_seconds") for r in valid),
        "input_tokens": metric(u.get("input_tokens") for u in usage),
        "cached_input_tokens": metric(u.get("cached_input_tokens") for u in usage),
        "output_tokens": metric(u.get("output_tokens") for u in usage),
        "total_tokens": metric(tokens),
    }


def display(value):
    return "n/a" if value is None else f"{value:,.1f}".removesuffix(".0")


def summarize(results_path, controls_path, output, protocol_path=None):
    rows, controls = read_json(results_path), read_json(controls_path)
    if not isinstance(rows, list) or not isinstance(controls, list):
        raise ValueError("Results and controls must be JSON arrays")
    protocol = read_json(protocol_path) if protocol_path and protocol_path.exists() else {}
    identifiers = [(r["case"], r["condition"], r["repeat"]) for r in rows]
    if len(set(identifiers)) != len(identifiers):
        raise ValueError("Duplicate trial records")
    if any(r["condition"] not in CONDITIONS for r in rows):
        raise ValueError("Unknown condition")
    if any(r.get("passed") is True and r.get("valid_run") is not True for r in rows):
        raise ValueError("A passing record must explicitly be valid")
    planned = [tuple(t) for t in protocol.get("trials", [])]
    if len(set(planned)) != len(planned):
        raise ValueError("Duplicate trials in protocol")
    if planned and not set(identifiers).issubset(planned):
        raise ValueError("Observed trial absent from protocol")
    control_ids = [(r["case"], r["reference"]) for r in controls]
    if len(set(control_ids)) != len(control_ids):
        raise ValueError("Duplicate control records")

    cases = sorted({r["case"] for r in rows + controls} | {t[0] for t in planned})
    planned_counts = Counter((case, condition) for case, condition, _ in planned)
    cells = {case: {condition: aggregate(
        [r for r in rows if r["case"] == case and r["condition"] == condition],
        planned_counts[case, condition] if planned else None,
    ) for condition in CONDITIONS} for case in cases}
    totals = {condition: aggregate(
        [r for r in rows if r["condition"] == condition],
        sum(t[1] == condition for t in planned) if planned else None,
    ) for condition in CONDITIONS}
    control_summary = {}
    for case in cases:
        records = [r for r in controls if r["case"] == case]
        control_summary[case] = {
            "complete": {r["reference"] for r in records} == {False, True},
            "expected_outcomes": all(type(r.get("tests")) is int and r["tests"] > 0
                                     and r.get("passed") is r["reference"] for r in records),
            "records": records,
        }
    inputs = {"results": provenance(results_path), "controls": provenance(controls_path)}
    for label, path in (
        ("protocol", protocol_path),
        ("frozen_inputs", results_path.with_name("manifest.json")),
        ("control_inputs", controls_path.with_name("controls_manifest.json")),
    ):
        if path and path.exists():
            inputs[label] = provenance(path)
    limitations = [
        "Six audit-selected tasks and three planned repetitions per condition give limited evidence, not a held-out generalization result.",
        "Guidance was loaded explicitly. These trials do not measure skill discovery or routing.",
        "Baseline has common task and verification instructions. It is not an instruction-free model.",
        "Missing records are not counted as failures. Invalid agent runs are reported separately from valid-run pass counts.",
        "Time and token medians use valid runs with available metrics, including valid runs that failed grading. Total tokens are input plus output, without subtracting cached input. They are not a billing estimate.",
        "Hidden checks cover the stated cases, not every possible implementation defect. Controls establish that these checks distinguish the seed from the reference.",
    ]
    evidence = {"inputs": inputs, "protocol": protocol, "per_case": cells, "totals": totals,
                "controls": control_summary, "limitations": limitations, "trials": rows}
    output.mkdir(parents=True, exist_ok=True)
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")

    lines = ["# Astra skill evaluation", "",
             f"Observed {len(rows)} trial records. Planned total: {len(planned) if planned else 'unknown'}. "
             f"Model: {protocol.get('model', 'not recorded in protocol')}. "
             f"Reasoning: {protocol.get('reasoning_effort', 'not recorded in protocol')}.", ""]
    retries = sum(r.get("source_phase") == "retry" for r in rows)
    if retries:
        lines += [f"This accepted sample includes {retries} separate retries of invalid original runs. "
                  "The [original records](original-results.json) and [retry records](retry-results.json) "
                  "are preserved separately. The table below describes the accepted sample only.", ""]
    lines += ["Each cell is **passed / observed (valid runs)**. Missing runs are shown below.", "",
             "| Case | Baseline | Corrected | Pruned |", "|---|---:|---:|---:|"]
    for case in cases:
        values = [f"{cells[case][c]['passed']}/{cells[case][c]['observed']} ({cells[case][c]['valid']} valid)" for c in CONDITIONS]
        lines.append(f"| {case} | " + " | ".join(values) + " |")
    lines += ["", "Medians below include valid runs only. Metric sample counts and per-case medians are in [evidence.json](evidence.json).", "",
              "| Condition | Passed / valid | Invalid or unknown | Missing | Median seconds | Median input tokens | Median output tokens | Median total tokens |",
              "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for condition, stats in totals.items():
        values = [f"{stats['passed']}/{stats['valid']}", str(stats['invalid_or_unknown_validity']), display(stats['missing'])]
        values += [display(stats[key]["median"]) for key in ("agent_seconds", "input_tokens", "output_tokens", "total_tokens")]
        lines.append(f"| {condition} | " + " | ".join(values) + " |")
    lines += ["", "Controls:", "", "| Case | Seed failed and reference passed with tests observed |", "|---|---|"]
    for case, record in control_summary.items():
        status = "yes" if record["complete"] and record["expected_outcomes"] else "not established"
        lines.append(f"| {case} | {status} |")
    lines += ["", "Limitations:", ""] + [f"- {text}" for text in limitations]
    lines += ["", "Input provenance:", ""]
    for label, info in inputs.items():
        path = Path(info["path"])
        link = path.name if path.parent == output.resolve() else info["path"]
        lines.append(f"- [{label}](<{link}>) SHA-256 `{info['sha256']}`")
    lines += ["", "[Machine-readable evidence](evidence.json) includes individual trial records, control records, and the recorded protocol.", ""]
    (output / "summary.md").write_text("\n".join(lines))
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", required=True, type=Path)
    parser.add_argument("--controls", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--protocol", type=Path)
    args = parser.parse_args()
    summarize(args.results, args.controls, args.output,
              args.protocol or args.results.with_name("protocol.json"))
    print(args.output / "summary.md")
    print(args.output / "evidence.json")


if __name__ == "__main__":
    main()
