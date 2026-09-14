# Elixir project work

For unfamiliar or version-sensitive library behavior, consult the installed dependency's relevant usage-rules.md, usage-rules/ files, and source documentation. Resolve versions from mix.lock. Read the relevant sections only, and preserve project conventions.

Use plain modules for code organization. Add a process only for a runtime need such as concurrent execution, independently supervised failure, or state across calls.

When simplifying control flow, preserve return values and failures for every supported branch. A failed match in with returns the unmatched value unless an else handles it. Keyword.get/3 uses its default for an absent key, not a key holding nil. Do not replace a case with either construct unless the contracts agree.

Inside coding agents, prefix Mix commands with unbuffer. If unavailable, report the missing prerequisite. Use the project's versions and check aliases. Run formatting, compilation with warnings-as-errors, relevant tests, and Credo when configured. Fix introduced failures and report actual results and skipped checks.

Prefer assertions on meaningful shapes and values rather than type-only checks or positional list indexing. Test public behavior and keep isolation per test when possible.
