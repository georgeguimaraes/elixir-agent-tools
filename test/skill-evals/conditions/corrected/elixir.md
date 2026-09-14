---
name: elixir
description: Write and refactor idiomatic Elixir functions, modules, and data structures. Use for pattern matching, control flow, error handling, protocols, behaviours, and deciding whether a process is needed. Use otp for process design and supervision.
---

# Elixir

Design modules, model data, and handle errors with Elixir's functional idioms.

For unfamiliar or version-sensitive library behavior, consult the installed dependency's relevant `usage-rules.md`, `usage-rules/` files, and source documentation. Resolve versions from `mix.lock`. Read the relevant sections only, and preserve project conventions.

## The Iron Law

```
NO PROCESS WITHOUT A RUNTIME REASON
```

Before creating a GenServer, Agent, or any process, answer YES to at least one:
1. Do I need mutable state persisting across calls?
2. Do I need concurrent execution?
3. Do I need fault isolation?

**All three are NO?** Use plain functions. Modules organize code; processes manage runtime.

## The Three Decoupled Dimensions

OOP couples behavior, state, and mutability together. Elixir decouples them:

| OOP Dimension | Elixir Equivalent |
|---------------|-------------------|
| Behavior | Modules (functions) |
| State | Data (structs, maps) |
| Mutability | Processes (GenServer) |

Pick only what you need. "I only need data and functions" = no process needed.

## "Let It Crash" = "Let It Heal"

The misconception: Write careless code.
The truth: Supervisors START processes.

- Handle expected errors explicitly (`{:ok, _}` / `{:error, _}`)
- Let unexpected errors crash → supervisor restarts

## Control Flow

**Pattern matching first:**
- Match on function heads instead of `if/else` or `case` in bodies
- `%{}` matches ANY map—use `map_size(map) == 0` guard for empty maps
- Avoid nested `case`—refactor to single `case`, `with`, or separate functions

**Error handling:**
- Use `{:ok, result}` / `{:error, reason}` for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining `{:ok, _}` / `{:error, _}` operations

**Be explicit about expected cases:**
- Avoid `_ -> nil` catch-alls—they silently swallow unexpected cases
- Avoid `value && value.field` nil-punning—obscures actual return types
- Preserve all return values and failure behavior when replacing `case` with `with`. An unmatched `<-` returns its value unless an `else` handles it, while an unmatched `case` raises.

## Polymorphism

| For Polymorphism Over... | Use | Contract |
|--------------------------|-----|----------|
| Modules | Behaviors | Upfront callbacks |
| Data | Protocols | Upfront implementations |
| Processes | Message passing | Implicit (send/receive) |

**Behaviors** = default for module polymorphism (very cheap at runtime)
**Protocols** = only when composing data types, especially built-ins
**Message passing** = only when stateful by design (IO, file handles)

Use the simplest abstraction: pattern matching → anonymous functions → behaviors → protocols → message passing. Each step adds complexity.

**When justified:** Library extensibility, multiple implementations, test swapping.
**When to stay coupled:** Internal module, single implementation, pattern matching handles all cases.

## Data Modeling Replaces Class Hierarchies

OOP: Complex class hierarchy + visitor pattern.
Elixir: Model as data + pattern matching + recursion.

```elixir
{:sequence, {:literal, "rain"}, {:repeat, {:alternation, "dogs", "cats"}}}

def interpret({:literal, text}, input), do: ...
def interpret({:sequence, left, right}, input), do: ...
def interpret({:repeat, pattern}, input), do: ...
```

## Defaults and Options

`Keyword.get/3` and `Map.get/3` use the default only when the key is absent. A present key with `nil` keeps that value. Preserve absent-key and explicit-nil behavior when simplifying option handling, and do not assume a sentinel such as `:default` is equivalent to calling the original fallback.

Keep configuration handling local when that makes the contract clearer. A helper is appropriate when it owns shared behavior.

## Idioms

- Process dictionary is typically unidiomatic—pass state explicitly
- Reserve `is_thing` names for guards only
- Use structs over maps when shape is known: `defstruct [:name, :age]`
- Prepend to lists `[new | list]` not `list ++ [new]`
- Use `dbg/1` for debugging—prints formatted value with context
- Use built-in `JSON` module (Elixir 1.18+) instead of Jason

## Verification

**Inside coding agents, always prefix `mix` commands with `unbuffer`** to get ANSI colors and prevent stdout block-buffering in non-TTY environments (e.g. `unbuffer mix test`). Install: `brew install expect` (macOS) or `apt install expect` (Linux). If `unbuffer` is unavailable, report the missing prerequisite instead of silently dropping it.

After changing Elixir code, verify the completed change before reporting it as done. Run commands from the relevant Mix project using its pinned Elixir/OTP versions. Follow the repository's contribution instructions and existing check aliases. Prefer an alias when it covers the checks below, and run any uncovered checks separately:

1. Format changed files with `unbuffer mix format path/to/file.ex path/to/test.exs`, following the project's formatter configuration.
2. Compile with `unbuffer mix compile --warnings-as-errors` to catch compilation errors and warnings.
3. Run relevant tests with `unbuffer mix test test/path/to/affected_test.exs`. Run the broader suite when the change affects shared behavior or the repository requires it.
4. Run `unbuffer mix credo` when Credo is configured, using the repository's flags and configuration.

Fix failures introduced by the change and rerun the affected checks. Report the commands actually run and their results, including any checks that were skipped or blocked and why. An unrun or blocked check hasn't passed.

## Testing

**Prefer pattern matching over imperative assertions.** Never use `assert length` + `Enum.at`/`List.last`/`hd`. Pattern match checks length and content in one shot:

```elixir
# Bad
assert length(students) == 2
assert Enum.at(students, 0).name == "Alice"
assert Enum.at(students, 1).name == "Bob"

# Good
assert [%{name: "Alice"}, %{name: "Bob"}] = students
```

Same goes for type-only predicates: `assert is_map(user)` / `assert is_list(posts)` pass for almost any non-error return. Pattern match the shape and content together: `assert %User{email: "a@b.com"} = user`. `is_nil/1` is fine when nil-ness is the whole point.

**Test behavior, not implementation.** Test use cases / public API. Refactoring shouldn't break tests.

**Test your code, not the framework.** If deleting your code doesn't fail the test, it's tautological.

**Keep tests async.** `async: false` means you've coupled to global state. Fix the coupling:

| Problem | Solution |
|---------|----------|
| `Application.put_env` | Pass config as function argument |
| Feature flags | Inject via process dictionary or context |
| ETS tables | Create per-test tables with unique names |
| External APIs | Use Mox with explicit allowances |
| File system operations | Use `@tag :tmp_dir` (see below) |

**Use `tmp_dir` for file tests.** ExUnit creates unique temp directories per test, async-safe:

```elixir
@tag :tmp_dir
test "writes file", %{tmp_dir: tmp_dir} do
  path = Path.join(tmp_dir, "test.txt")
  File.write!(path, "content")
  assert File.read!(path) == "content"
end
```

Directory is auto-cleaned before each run. Works with `@moduletag :tmp_dir` for all tests in module.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I need a process to organize this code" | Modules organize code. Processes are for runtime. |
| "GenServer is the Elixir way" | Plain functions are also the Elixir way. |
| "I'll need state eventually" | YAGNI. Add process when you need it. |
| "It's just a simple wrapper process" | Simple wrappers become bottlenecks. |
| "This is how I'd structure it in OOP" | Rethink from data flow. |

## Red Flags - STOP and Reconsider

- Creating process without answering the three questions
- Using GenServer for stateless operations
- Wrapping a library in a process "for safety"
- One process per entity without runtime justification
- Reaching for protocols when pattern matching works

**Any of these? Re-read The Iron Law.**
