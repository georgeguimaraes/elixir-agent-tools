Independent isolation audit of `/private/tmp/astra-skill-eval/runs-pinned` and `/private/tmp/astra-skill-eval/runs-retries`, September 5, 2026.

This is the historical audit report. The raw event logs and per-run workspaces were not retained, so the paths below identify the original evidence locations and can no longer be inspected.

The final audit covers all 54 original trials and all three replacement trials, including the completed `otp-pruned-3` replacement. That is 57 attempts, with 54 valid runs retained after excluding three original sessions with provider errors. The earlier `runs-final` batch with shell runtime drift is excluded.

No personal-skill, memory, hidden-test, reference-solution, or cross-trial solution access was found in the inspected event logs. The audit covered 386 completed shell commands and 57 file-change events, with targeted checks of command text and paths. Reported file edits were confined to each trial's `project/lib/`.

Protected-file checks were clean in all 57 attempts. Hash comparisons against the base project found no changes to any of the 645 dependency files outside dependency `_build` directories. No additional configuration or other files appeared outside `lib/`, `test/`, dependencies, and build output. The generated Telemetry compiler cache changed during normal compilation and was excluded from the dependency-source comparison.

Every trial's injected developer guidance matched its condition snapshot exactly. Baseline inputs had no injected guidance. Inputs disabled personal skill instructions, memories, login shells, and shell snapshots. Sixteen commands explicitly printed Elixir or Mix 1.20.1 with OTP 28. In particular, `otp-corrected-2/events.jsonl:21` printed `Elixir 1.20.1, OTP 28.5.0.2`. No command switching runtimes was observed. This confirms the recorded checks without assuming that every trial independently printed its runtime version.

Representative access checks, with paths relative to `runs-pinned`:

- `channel-pruned-1/events.jsonl:13` reads the trial's installed Phoenix usage rules and channel source, both allowed by the common prompt.
- `refactor-baseline-2/events.jsonl:10` looks for `.agents` and `.codex` inside its project. This did not read personal configuration or skills.
- `chaining-pruned-2/events.jsonl:8` searches its containing run directory for `AGENTS.md`. No hidden tests, references, or another trial's solution were read.

Three trials contain recovered provider errors and remain invalid under the frozen protocol even though their submitted code passed grading:

| Trial | Exact error evidence |
|---|---|
| `otp-pruned-3` | `events.jsonl:23` and `:24`: reconnecting after request timeouts |
| `polling-pruned-1` | `events.jsonl:26`: reconnecting after a request timeout |
| `sandbox-baseline-1` | `events.jsonl:5`: reconnecting after a request timeout |

All three replacements under `runs-retries` completed without provider errors and passed the same isolation checks. Their `result.json` records have `valid_run: true`, empty `errors`, and empty `protected_changes`. The retained comparison therefore has 54 protocol-valid trials. The provider failures remain separate from model or skill correctness. No frozen inputs, grading behavior, or production skills were changed by this audit.
