# Astra skill evaluation

This screening experiment compares fresh GPT-6-Astra sessions with no domain skills, corrected full skills, and pruned skills. It measures the effect of loaded guidance. It does not test skill discovery or establish everything the model knows.

The six tasks cover a contract-preserving Elixir refactor, responsive OTP work, Ecto sandbox ownership, Phoenix channel authorization, bounded Oban polling, and atomic downstream enqueueing. They were selected from issues identified during the skill audit. These are small targeted fixtures, not a representative benchmark of Elixir development. No held-out task set has been evaluated.

Each task runs three times per condition, for 54 trials. The model, reasoning effort (`high`), public task, initial code, dependencies, runtime, tools, and 240-second task limit are held constant. Trial order is shuffled with a fixed seed and three sessions run concurrently. Relevant guidance is supplied directly as developer instructions. The full and pruned conditions contain the same retained factual guidance, with the full condition also retaining tutorials and broader material. Baseline receives the common project instructions only.

All conditions retain the same shell, editing, and live web-search tools. Installed dependency source is available. Personal skills, plugins, memory, and automatic AGENTS loading are disabled to avoid leakage. The common instructions include `unbuffer mix` and the task's scope. The user's actual home and Codex home are never replaced. Authentication uses the existing Codex login, while run state and logs live in the temporary experiment directory.

The runner resolves the pinned Elixir and Erlang installations through asdf and puts their executable directories first in the command environment. Codex login shells and shell snapshots are disabled so shell startup cannot silently replace that runtime. An initial batch at `/private/tmp/astra-skill-eval/runs-final` was stopped after its logs showed runtime switching. It is excluded from the measured comparison, which uses fresh sessions and controls.

Each case supplies seed code, public tests, hidden tests, and a reference implementation. Before model trials, the seed must fail and the reference must pass a nonempty test suite. Grading uses a fresh copy of the base project with only submitted `lib/` files overlaid, restoring the original tests and using a fresh database when needed. Hidden tests and references are never copied into the agent's workspace. The channel case exercises actual Phoenix callbacks and message serialization, not a complete websocket transport session.

Inputs are hashed before measured runs. Do not change conditions, tasks, tests, or grading after freezing. A changed experiment needs a new output directory and new controls. Frozen inputs and repeated runs allow inspection of unexpected outcomes. A pass means the implementation passed the executable checks, completed within the time budget, and preserved protected files. Missing test output, provider errors, and incomplete runs are reported separately rather than treated as evidence of model knowledge.

Results from the completed screening and its three transport-error replacements are in [results/2026-09-05](results/2026-09-05/README.md). The [proposed edits](proposed-changes.md) separate measured decisions from broader editorial recommendations.

## Running locally

The runner currently targets macOS and uses copy-on-write `cp -cR`. It requires Codex, uv, unbuffer, PostgreSQL tools, and the Elixir/OTP versions in `project/.tool-versions`. `project/mix.lock` pins dependency versions. Public packages are sufficient, with no Oban Pro dependency or license required.

Prepare a temporary base project by copying `project/` to `/private/tmp/astra-skill-eval/base`, then run `unbuffer mix deps.get` and `MIX_ENV=test unbuffer mix compile` there. Use `HEX_HOME=/private/tmp/astra-skill-eval/hex` for an isolated package cache. Start a separate PostgreSQL cluster with role `skill_eval`, loopback address `127.0.0.1`, and port `55439`. The runner creates uniquely named databases inside that cluster. Do not point it at a production database server.

```sh
uv run --no-project python test/skill-evals/run.py controls --output /private/tmp/astra-skill-eval/controls-v4
uv run --no-project python test/skill-evals/run.py run --controls /private/tmp/astra-skill-eval/controls-v4/controls.json
```

Run outputs include exact prompts and condition text, model event logs and usage, submitted sources, hidden-check logs, per-run results, shuffled trial order, and input hashes. Resume completed trials with the same command and unchanged inputs. Interrupted trials without a result file require a fresh output directory or explicit recovery after inspecting their partial outputs.

Interpret differences conservatively. Three repetitions of six related tasks can identify regressions or obvious redundancy, but cannot prove equivalence, estimate broad coding ability, or attribute an outcome to one specific instruction. Follow-up ablations and new tasks are needed for those claims. Timing and token usage include the harness and tool interactions, and may be affected by caching and concurrency.
