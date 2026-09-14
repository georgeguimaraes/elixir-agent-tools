#!/usr/bin/env python3
"""Run isolated, paired skill evaluations with executable hidden checks."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import random
import re
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parent
CASES = {
    "refactor": ["elixir"],
    "otp": ["elixir", "otp"],
    "sandbox": ["elixir", "ecto"],
    "channel": ["elixir", "phoenix"],
    "polling": ["elixir", "oban"],
    "chaining": ["elixir", "ecto", "oban"],
}
COMMON = """Work in the current project only. Implement the requested change in lib/.
Preserve the public interfaces except where the task requests a change. Do not change
the existing tests, dependency sources, or build configuration. Dependencies are already
downloaded. Run relevant checks using unbuffer mix. You may consult installed dependency
source or public documentation when useful. Do not install or read global agent skills.
No git operations are needed. Finish with a concise description of the change and checks.
"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, cwd, env, output, timeout=120):
    started = time.monotonic()
    with output.open("w") as log:
        proc = subprocess.Popen(args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                start_new_session=True, stdin=subprocess.DEVNULL)
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            code = 124
    return code, round(time.monotonic() - started, 3)


def prepare(args, name, case, reference=False):
    run = args.output / name
    run.mkdir(parents=True)
    work = run / "project"
    subprocess.run(["cp", "-cR", str(args.base), str(work)], check=True)
    source = ROOT / "cases" / case
    shutil.copytree(source / "lib", work / "lib", dirs_exist_ok=True)
    if reference:
        ref = source / "reference"
        if (ref / "lib").exists():
            ref = ref / "lib"
        shutil.copytree(ref, work / "lib", dirs_exist_ok=True)
    (work / "test").mkdir(exist_ok=True)
    helper = source / "test_helper.exs"
    if helper.exists():
        shutil.copy2(helper, work / "test/test_helper.exs")
    else:
        (work / "test/test_helper.exs").write_text("ExUnit.start()\n")
    shutil.copy2(source / "public_test.exs", work / "test/public_test.exs")
    (work / ".formatter.exs").write_text('[inputs: ["mix.exs", "{lib,test}/**/*.{ex,exs}"]]\n')
    db = "eval_" + hashlib.sha256(str(run).encode()).hexdigest()[:16]
    env = dict(os.environ, MIX_ENV="test", HEX_HOME=str(args.output.parent / "hex"),
               ERL_FLAGS="+S 4:4", ASDF_ELIXIR_VERSION="1.20.1-otp-28", ASDF_ERLANG_VERSION="28.5.0.2",
               EVAL_DATABASE_URL=f"postgres://skill_eval@127.0.0.1:55439/{db}")
    runtime_bins = [str(Path(subprocess.check_output(["asdf", "where", tool, version], text=True).strip()) / "bin")
                    for tool, version in [("elixir", env["ASDF_ELIXIR_VERSION"]), ("erlang", env["ASDF_ERLANG_VERSION"])]]
    env["PATH"] = os.pathsep.join(runtime_bins + [env["PATH"]])
    if case in {"sandbox", "chaining"}:
        subprocess.run(["createdb", "-h", "127.0.0.1", "-p", "55439", "-U", "skill_eval", db],
                       check=True, capture_output=True)
    return run, work, env


def grade(args, case, run, work, env):
    source = ROOT / "cases" / case
    protected = ["mix.exs", "mix.lock", "test/public_test.exs", "test/test_helper.exs", ".formatter.exs", ".tool-versions"]
    changed = []
    original = json.loads((run / "protected.json").read_text())
    for name in protected:
        if not (work / name).exists() or digest(work / name) != original[name]:
            changed.append(name)
    grader = run / "grader"
    subprocess.run(["cp", "-cR", str(args.base), str(grader)], check=True)
    shutil.copytree(work / "lib", grader / "lib", dirs_exist_ok=True)
    work = grader
    (work / "test").mkdir(exist_ok=True)
    env = dict(env)
    if case in {"sandbox", "chaining"}:
        db = env["EVAL_DATABASE_URL"].rsplit("/", 1)[1] + "_grade"
        subprocess.run(["createdb", "-h", "127.0.0.1", "-p", "55439", "-U", "skill_eval", db],
                       check=True, capture_output=True)
        env["EVAL_DATABASE_URL"] = f"postgres://skill_eval@127.0.0.1:55439/{db}"
    helper = source / "test_helper.exs"
    (work / "test/test_helper.exs").write_text(helper.read_text() if helper.exists() else "ExUnit.start()\n")
    for name in ["public_test.exs", "hidden_test.exs"]:
        shutil.copy2(source / name, work / "test" / name)
    code, elapsed = command(["unbuffer", "mix", "test", "--seed", "314159"], work, env,
                            run / "grade.log")
    clean = re.sub(r"\x1b\[[0-9;]*m", "", (run / "grade.log").read_text())
    counts = re.findall(r"(\d+) tests?, (\d+) failures?", clean)
    total, failures = map(int, counts[-1]) if counts else (None, None)
    if not counts:
        modern = re.findall(r"Result: (\d+)(?:/(\d+))? passed", clean)
        if modern:
            passed, all_tests = modern[-1]
            total = int(all_tests or passed)
            failures = total - int(passed)
    return {"grade_exit": code, "tests": total, "failures": failures,
            "protected_changes": changed, "passed": code == 0 and total is not None and total > 0 and not changed,
            "grade_seconds": elapsed}


def save_protected(run, work):
    files = ["mix.exs", "mix.lock", "test/public_test.exs", "test/test_helper.exs", ".formatter.exs", ".tool-versions"]
    (run / "protected.json").write_text(json.dumps({p: digest(work / p) for p in files}, indent=2))


def run_trial(args, trial):
    case, condition, repeat = trial
    name = f"{case}-{condition}-{repeat}"
    existing = args.output / name / "result.json"
    if existing.exists():
        return json.loads(existing.read_text())
    run, work, env = prepare(args, name, case)
    save_protected(run, work)
    prompt = COMMON + "\nTask:\n" + (ROOT / "cases" / case / "prompt.md").read_text()
    guidance = ""
    if condition != "baseline":
        guidance = "\n\n".join((ROOT / "conditions" / condition / f"{skill}.md").read_text()
                                  for skill in CASES[case])
    settings = {
        "model_reasoning_effort": "high", "skills.include_instructions": False,
        "skills.bundled.enabled": False, "project_doc_max_bytes": 0,
        "features.memories": False, "features.apps": False, "features.external_migration": False,
        "features.shell_snapshot": False, "allow_login_shell": False,
        "shell_environment_policy.set.PATH": env["PATH"],
        "sandbox_workspace_write.network_access": True, "web_search": "live",
        "sqlite_home": str(run / "state"), "log_dir": str(run / "logs"),
    }
    if guidance:
        settings["developer_instructions"] = guidance
    argv = ["codex", "exec", "--ignore-user-config", "--ephemeral", "--skip-git-repo-check",
            "--sandbox", "workspace-write", "--model", "gpt-6-astra", "--json", "-C", str(work)]
    for k, v in settings.items():
        argv.extend(["-c", f"{k}={json.dumps(v)}"])
    argv.extend(["-o", str(run / "answer.md"), prompt])
    (run / "input.json").write_text(json.dumps({"prompt": prompt, "settings": settings}, indent=2))
    print(f"START {name}", flush=True)
    code, elapsed = command(argv, work, env, run / "events.jsonl", timeout=args.timeout)
    usage, messages, tools, errors = {}, [], 0, []
    for line in (run / "events.jsonl").read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "turn.completed":
            usage = event.get("usage", {})
        item = event.get("item", {})
        if event.get("type") == "item.completed":
            if item.get("type") == "agent_message":
                messages.append(item.get("text", ""))
            else:
                tools += 1
        if event.get("type") in {"turn.failed", "error"}:
            errors.append(event)
    shutil.copytree(work / "lib", run / "solution")
    result = {"case": case, "condition": condition, "repeat": repeat,
              "model": "gpt-6-astra", "reasoning": "high", "agent_exit": code,
              "agent_seconds": elapsed, "tool_events": tools, "usage": usage,
              "errors": errors, "guidance_bytes": len(guidance.encode()), **grade(args, case, run, work, env)}
    result["valid_run"] = code == 0 and bool(usage) and not errors
    result["passed"] = result["passed"] and result["valid_run"]
    (run / "result.json").write_text(json.dumps(result, indent=2))
    print(f"DONE {name} passed={result['passed']} failures={result['failures']} seconds={elapsed}", flush=True)
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["controls", "run"])
    p.add_argument("--base", type=Path, default=Path("/private/tmp/astra-skill-eval/base"))
    p.add_argument("--output", type=Path, default=Path("/private/tmp/astra-skill-eval/runs"))
    p.add_argument("--repeats", type=int, default=3)
    p.add_argument("--workers", type=int, default=3)
    p.add_argument("--timeout", type=int, default=240)
    p.add_argument("--controls", type=Path, default=Path("/private/tmp/astra-skill-eval/controls-v4/controls.json"))
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.mode == "controls":
        control_manifest = {str(f.relative_to(ROOT)): digest(f)
                            for f in sorted((ROOT / "cases").rglob("*")) if f.is_file()}
        (args.output / "controls_manifest.json").write_text(json.dumps(control_manifest, indent=2))
        results = []
        for case in CASES:
            for ref in [False, True]:
                name = f"control-{case}-{'reference' if ref else 'seed'}"
                run, work, env = prepare(args, name, case, reference=ref)
                save_protected(run, work)
                result = {"case": case, "reference": ref, **grade(args, case, run, work, env)}
                (run / "result.json").write_text(json.dumps(result, indent=2))
                results.append(result)
                print(json.dumps(result), flush=True)
        (args.output / "controls.json").write_text(json.dumps(results, indent=2))
        assert all(r["passed"] == r["reference"] and r["tests"] for r in results), "Invalid controls"
        return
    controls = json.loads(args.controls.read_text())
    assert len(controls) == len(CASES) * 2 and all(r["passed"] == r["reference"] and r["tests"] for r in controls)
    checked_cases = json.loads(args.controls.with_name("controls_manifest.json").read_text())
    assert all((ROOT / name).is_file() and digest(ROOT / name) == value for name, value in checked_cases.items()), "Cases changed since controls"
    assert all((ROOT / "conditions" / c / f"{s}.md").exists()
               for c in ["corrected", "pruned"] for s in ["elixir", "ecto", "otp", "phoenix", "oban"])
    manifest = {str(f.relative_to(ROOT)): digest(f) for d in ["cases", "conditions"]
                for f in sorted((ROOT / d).rglob("*")) if f.is_file()}
    manifest["run.py"] = digest(Path(__file__))
    manifest["mix.lock"] = digest(args.base / "mix.lock")
    manifest_path = args.output / "manifest.json"
    if manifest_path.exists():
        assert json.loads(manifest_path.read_text()) == manifest, "Inputs changed after freezing"
    else:
        manifest_path.write_text(json.dumps(manifest, indent=2))
    trials = [(case, condition, repeat) for repeat in range(1, args.repeats + 1)
              for case in CASES for condition in ["baseline", "corrected", "pruned"]]
    random.Random(20260905).shuffle(trials)
    (args.output / "protocol.json").write_text(json.dumps({
        "model": "gpt-6-astra", "reasoning_effort": "high", "repeats": args.repeats,
        "workers": args.workers, "timeout_seconds": args.timeout, "shuffle_seed": 20260905,
        "trials": trials, "controls": str(args.controls),
        "scope": "Loaded guidance, not skill discovery. Six selected audit-related tasks, no held-out generalization claim.",
        "tools": "Codex shell, file editing, live web search. Personal plugins, skills, memories, and project-doc auto-loading disabled.",
    }, indent=2))
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda t: run_trial(args, t), trials))
    (args.output / "results.json").write_text(json.dumps(results, indent=2))
    for condition in ["baseline", "corrected", "pruned"]:
        rows = [r for r in results if r["condition"] == condition]
        print(condition, sum(r["passed"] for r in rows), "/", len(rows), flush=True)


if __name__ == "__main__":
    main()
