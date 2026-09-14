# Astra skill screening: September 5, 2026

Astra passed every behavioral check with no extra domain skills. Corrected full skills and pruned skills also passed. This experiment found no correctness benefit from the additional guidance on these six tasks.

| Condition | Valid passes | Median seconds | Median reported total tokens |
|---|---:|---:|---:|
| No domain skills | 18/18 | 66.8 | 93,117 |
| Corrected full skills | 18/18 | 86.3 | 145,310 |
| Pruned skills | 18/18 | 103.5 | 151,319 |

The pruned snapshots contain 872 words and 6,276 bytes versus 4,913 words and 35,719 bytes in the corrected snapshots. That's about 82% less skill text. It did not produce lower median total token usage in this run. Token totals accumulate input and output across tool interactions, including cached input. They aren't a billing estimate. Timing and usage are descriptive measurements affected by model variability, caching, concurrency, and the replacement runs.

The six cases exercise preserving refactor behavior, responsive OTP work with failure recovery, Ecto sandbox isolation, channel permission changes, polling deadlines, and transactional downstream enqueueing. Each condition ran each case three times. The accepted sample contains 207 passing behavioral checks.

## Run accounting

The planned batch produced 54 original records. All 54 submitted implementations passed grading. Three sessions recovered from provider request timeouts and were marked invalid under the frozen protocol: `otp-pruned-3`, `polling-pruned-1`, and `sandbox-baseline-1`. Their original records remain in [original-results.json](original-results.json). They weren't code failures.

Those three cases were repeated in fresh sessions with unchanged inputs. All three replacements completed cleanly and passed. The table uses 51 valid original runs plus those three replacements, for 54 valid observations from 57 attempts. [results.json](results.json) identifies each accepted record's source. [retry-results.json](retry-results.json), [retry-protocol.json](retry-protocol.json), and the archived [retry script](retry-invalid.py) preserve the replacement procedure.

Before the measured batch, an initial batch was stopped after logs showed shell startup switching runtimes. That entire batch at `/private/tmp/astra-skill-eval/runs-final` is excluded. The final runner explicitly pins the runtime and disables login shells and shell snapshots. Three real shell calls verified consistent versions, then all six seed/reference control pairs were revalidated before sampling. Frozen task, condition, runner, and dependency-lock hashes still matched after the experiment.

## What this supports

Remove the tested reminders and simplify the tutorial material. Keep the explicit `unbuffer` workflow because the user requires it. Treat specialized additions as candidates that need a demonstrated failure before they earn more context. The concrete editing proposal is in [proposed-changes.md](../../proposed-changes.md).

These small, audit-selected tasks don't establish everything Astra knows or what other models need. The tasks explicitly describe desired behavior, and baseline retains common project instructions, including `unbuffer` and relevant checks. The experiment doesn't isolate those common instructions, test automatic skill discovery, cover every instruction in the snapshots, or prove general equivalence. The channel case tests real callbacks and serialization, not a complete websocket session. Broader tutorial removal is an editorial recommendation informed by the results.

## Evidence

[Detailed tables](summary.md), [machine-readable evidence](evidence.json), [controls](controls.json), [input hashes](manifest.json), [environment](environment.json), and the [isolation audit](isolation-audit.md) are retained here. Per-run prompts, event logs, submitted sources, and grader logs were stored in temporary directories and were not retained. Historical paths in the saved records identify their original locations. The archived retry script documents the original procedure and depends on those missing directories.

The saved records support recalculating the summary, but the original submissions and log-level audit findings can no longer be independently inspected. The runner, fixtures, and condition snapshots remain available for new evaluations. The temporary PostgreSQL cluster was stopped after grading. The checkout moved to `~/code/elixir-agent-tools` after sampling, so historical command paths retain its former name.
