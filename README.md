# Elixir Agent Tools

Elixir development guidance for coding agents, with optional Mix checks and Expert language server integration.

Five skills covering language idioms, Phoenix interfaces, Ecto persistence, OTP processes, and Oban jobs. Install them with `npx skills`, then add optional plugins when you want automatic checks or code navigation.

**These skills are small on purpose. Every instruction must change the agent's behavior.** Modern coding agents already know the basics. Their context should go toward your code and your problem. We keep only guidance that changes a decision or prevents a demonstrated mistake. If the agent would do the same thing without an instruction, that instruction doesn't belong here.

## Installation

Install all five skills with the [Skills CLI](https://github.com/vercel-labs/skills) and choose your agent when prompted. Works with Codex, Claude Code, OpenCode, and other supported agents:

```bash
npx skills add georgeguimaraes/elixir-agent-tools --skill '*'
```

Add `-g` to make the skills available across projects. Start a new session after installation. Mix checks and code navigation are [optional tools](#optional-tools) you can add later.

<details>
<summary>Alternative: native Claude Code or Codex plugin</summary>

Install the same five skills as a plugin. Choose this or `npx skills` to avoid duplicate skills.

### Claude Code

```bash
claude plugin marketplace add georgeguimaraes/elixir-agent-tools
claude plugin install elixir-dev@elixir-agent-tools
```

### Codex

```bash
codex plugin marketplace add georgeguimaraes/elixir-agent-tools
codex plugin add elixir-dev@elixir-agent-tools
```

</details>

<details>
<summary>Manual installation</summary>

For agents that discover skills under `~/.agents/skills`, clone this repository into a persistent location and link each skill:

```bash
git clone https://github.com/georgeguimaraes/elixir-agent-tools.git "$HOME/.local/share/elixir-agent-tools"
mkdir -p "$HOME/.agents/skills"
for skill in elixir phoenix ecto otp oban; do
  ln -s "$HOME/.local/share/elixir-agent-tools/plugins/elixir-dev/skills/$skill" "$HOME/.agents/skills/$skill"
done
```

If a destination already exists, inspect it before replacing it. Start a new session after installation. Updating the clone updates the linked skills.

For other agents with [Agent Skills support](https://agentskills.io), install the individual folders from `plugins/elixir-dev/skills/` in that agent's skill directory.

</details>

<details>
<summary>Try a local checkout in Codex</summary>

Register the local directory instead of the GitHub repository:

```bash
codex plugin marketplace add /path/to/elixir-agent-tools
codex plugin add elixir-dev@elixir-agent-tools
```

Start a new session after installation.

</details>

## Elixir skills

Each skill has its own discovery description. The agent can load several skills for a task that crosses domains, such as a LiveView form backed by an Ecto changeset. There is no startup hook or mandatory routing skill.

| Skill | Scope | Example request |
|-------|-------|-----------------|
| [elixir](plugins/elixir-dev/skills/elixir/SKILL.md) | Functions, modules, data structures, pattern matching, error handling | "Refactor this nested case expression" |
| [phoenix](plugins/elixir-dev/skills/phoenix/SKILL.md) | LiveView, components, HTTP endpoints, Plug, channels, PubSub | "Keep this LiveView filter in sync with the URL" |
| [ecto](plugins/elixir-dev/skills/ecto/SKILL.md) | Schemas, changesets, queries, transactions, migrations, data access | "Fix the N+1 queries on this page" |
| [otp](plugins/elixir-dev/skills/otp/SKILL.md) | Processes, supervision, runtime concurrency, ETS, Broadway | "Find the bottleneck in this GenServer" |
| [oban](plugins/elixir-dev/skills/oban/SKILL.md) | Durable jobs, retries, scheduling, uniqueness, Oban Pro workflows | "Send these emails in a job that retries failures" |

OTP covers work and state managed by running processes. Oban covers jobs that need persistence, retry policies, or scheduling. Phoenix owns interface behavior, while Ecto owns the persistence behind it.

### Upgrading to elixir-dev 3.0

Skill names now use their domain directly: `elixir`, `phoenix`, `ecto`, `otp`, and `oban`. Remove the `-thinking` suffix from explicit skill references in your prompts and agent instructions. The `using-elixir-skills` router and its startup hook have been removed.

The plugin is now named `elixir-dev` and the marketplace is `elixir-agent-tools`. If you installed from the old Claude Code marketplace, uninstall the plugins you used from `claude-code-elixir`, remove that marketplace, and add `georgeguimaraes/elixir-agent-tools`. Reinstall your chosen plugins with the new marketplace ID using the installation commands above. The old `elixir` plugin is replaced by `elixir-dev`.

Update any explicit plugin-qualified skill references to use the new bundle name.

If you installed skills manually, replace your old skill links or copies with the renamed folders under `plugins/elixir-dev/skills/`.

### Sources

The skills draw on Elixir and Erlang documentation, framework guides, and talks about application design:

- [José Valim - Gang of None](https://www.youtube.com/watch?v=4yAaHV9wQE4)
- [Saša Jurić - The Soul of Erlang and Elixir](https://www.youtube.com/watch?v=JvBT4XBdoUE)
- [Saša Jurić - Clarity](https://www.youtube.com/watch?v=6sNmJtoKDCo)
- [Designing Elixir Systems with OTP](https://pragprog.com/titles/jgotp/designing-elixir-systems-with-otp/)
- [Official Elixir Guides](https://elixir-lang.org/getting-started/)
- [Phoenix 1.8 Scopes](https://hexdocs.pm/phoenix/scopes.html)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Stephen Bussey - Real-Time Phoenix](https://pragprog.com/titles/sbsockets/real-time-phoenix/)
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [German Velasco - DDD for Phoenix Contexts](https://www.youtube.com/watch?v=mSgZ2LJXfew) (ElixirConf 2024)
- [Ecto Multi-Tenancy Guide](https://hexdocs.pm/ecto/multi-tenancy-with-query-prefixes.html)
- [Erlang OTP Design Principles](https://www.erlang.org/doc/system/design_principles.html)
- [Elixir GenServer Docs](https://hexdocs.pm/elixir/GenServer.html)
- [Elixir School - OTP Concurrency](https://elixirschool.com/en/lessons/advanced/otp_concurrency)
- [Saša Jurić - Elixir in Action](https://www.manning.com/books/elixir-in-action-third-edition)

## Optional tools

These tools use native plugins. Add the marketplace for your agent below, then install any tools you want. The skills work without them.

| Plugin | What you get | Requirements |
|--------|--------------|--------------|
| [mix-format](#mix-format) | Run `mix format` after edits to `.ex` and `.exs` files | Claude Code or Codex, Bash, Elixir/Mix, a Mix project |
| [mix-compile](#mix-compile) | Compile with `--warnings-as-errors` after edits to `.ex` files | Claude Code or Codex, Bash, Elixir/Mix, a Mix project |
| [mix-credo](#mix-credo) | Run Credo after edits to `.ex` and `.exs` files | Claude Code or Codex, Bash, Elixir/Mix, Credo in the project |
| [elixir-lsp](#elixir-lsp) | Code navigation and diagnostics through Expert | Claude Code, Expert, Python 3 |

<details>
<summary>Install tools in Claude Code</summary>

Add the marketplace once:

```bash
claude plugin marketplace add georgeguimaraes/elixir-agent-tools
```

Run only the commands for the tools you want:

```bash
claude plugin install mix-format@elixir-agent-tools
claude plugin install mix-compile@elixir-agent-tools
claude plugin install mix-credo@elixir-agent-tools
claude plugin install elixir-lsp@elixir-agent-tools
```

</details>

<details>
<summary>Install tools in Codex</summary>

Add the marketplace once:

```bash
codex plugin marketplace add georgeguimaraes/elixir-agent-tools
```

Run only the commands for the checks you want:

```bash
codex plugin add mix-format@elixir-agent-tools
codex plugin add mix-compile@elixir-agent-tools
codex plugin add mix-credo@elixir-agent-tools
```

Use `/hooks` in Codex to review and trust the installed hook commands. Codex requires hook trust separately from plugin installation. See the [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks). The Expert LSP plugin remains Claude Code only.

</details>

The Mix hooks support macOS and Linux, including WSL on Windows. They use Bash 3.2+, standard Unix tools, and the OS file-lock utility: `lockf` on macOS or `flock` on Linux/WSL. JSON parsing is bundled, so the Mix hooks need no jq, Python, uv, or newer Elixir version.

The three Mix plugins share a Bash runner and a bundled [JSON.sh](https://github.com/dominictarr/JSON.sh) parser. They handle Claude Code's `Edit`, `MultiEdit`, and `Write` events and Codex's `apply_patch` events, including patches spanning multiple files or projects. Shell commands that write files do not trigger these edit hooks.

Checks run synchronously and return failures as context to the agent. The plugins serialize their Mix commands per project, but hook execution order is not guaranteed. Formatting is not guaranteed to finish before compilation or Credo starts. Hooks have bounded waits and report timeouts. Mix plugins 2.0 replace the old single-file scripts and asynchronous Credo hook.

### mix-format

Runs `mix format` on surviving edited `.ex` and `.exs` files, using the nearest parent `mix.exs` to locate each project. Reports formatting failures.

### mix-compile

Runs `mix compile --warnings-as-errors` once per affected Mix project after editing an `.ex` file. Deletions and both sides of a move also trigger compilation. Reports compiler warnings and errors. Edits to `.exs` scripts and tests don't trigger compilation.

Skips compilation when `lsof` detects a BEAM process running from the project directory, to avoid competing with a running server or Mix task.

### mix-credo

Runs `mix credo` for each surviving edited `.ex` or `.exs` file using the project's Credo configuration. Reports code quality issues and skips the check if the Credo task isn't installed. Dependency and project failures remain visible.

### elixir-lsp

Connects Claude Code to [Expert](https://github.com/elixir-lang/expert) for navigation and compiler diagnostics in `.ex`, `.exs`, `.heex`, and `.leex` files.

Install the `expert` binary using the [Expert installation guide](https://expert-lsp.org/docs/installation) and make sure it's on your PATH. The bundled wrapper also requires Python 3.

The wrapper works around Claude Code's handling of server-initiated LSP requests, including `client/registerCapability` ([upstream issue](https://github.com/anthropics/claude-code/issues/32595)). See [expert-wrapper](plugins/elixir-lsp/bin/expert-wrapper) for the implementation.

## Developing the hooks

Edit the canonical runner and parser helpers under `scripts/mix-hooks/`, then run `bash scripts/sync-mix-hooks.sh` to bundle them into the three independently installable plugins. The bundled JSON.sh source and its MIT license live under `vendor/` in each copy.

Run `bash test/verify-plugins.sh` to check package structure and bundle consistency. Run `uv run --no-project python test/test-mix-hooks.py` for behavioral tests with isolated plugin installations and fake Mix commands. Python is used only by development checks, not the Mix hooks.

## License

Copyright (c) 2025 George Guimarães

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).
