I'd cut more than the pruned snapshots. All 54 original submissions passed their behavioral checks, including every baseline submission without domain skill guidance. Three original sessions had recovered provider errors, so they are excluded from the valid-run comparison and repeated separately. The [results](results/2026-09-05/README.md) preserve that distinction.

The experiment found no correctness benefit from the tested reminders. It doesn't establish everything Astra knows, or what other models need. These were six small tasks chosen from the audit, with three repetitions per condition and normal development tools available.

| Skill | What I'd change in production |
|---|---|
| [elixir](../../plugins/elixir-dev/skills/elixir/SKILL.md) | Delete the OOP comparison, basic syntax tutorials, rationalization tables, and flawed simplification examples. Astra preserved the refactor's nil and exception behavior without those reminders. Keep the required Mix workflow and a short pointer to installed-version dependency guidance. |
| [ecto](../../plugins/elixir-dev/skills/ecto/SKILL.md) | Delete general DDD, CRUD, and schema tutorials. Remove the incorrect sandbox restriction and transaction example. Baseline already handled per-test connection ownership and atomic rollback. Don't replace these sections with another tutorial. |
| [phoenix](../../plugins/elixir-dev/skills/phoenix/SKILL.md) | Delete the false subscription-time socket claim and its repeated warning. Baseline applied current permissions correctly. Remove component taxonomy, common PubSub examples, CSS advice, and repeated warnings as an editorial simplification. The tests didn't separately cover every one of those sections. |
| [otp](../../plugins/elixir-dev/skills/otp/SKILL.md) | Delete the basic concurrency table, abstraction decision tree, storage catalog, and repeated process rules. Baseline handled responsive work, busy rejection, failure replies, and recovery. Remove the misleading continuation and await claims along with their tutorial blocks. |
| [oban](../../plugins/elixir-dev/skills/oban/SKILL.md) | Delete basic worker templates, repeated error-handling advice, and the broken enqueue example. Baseline handled downstream enqueue failure and polling deadlines. Remove the incorrect Pro examples rather than expanding them into a versioned API reference. |

Every condition explicitly receives `unbuffer`, so the comparison says nothing about whether Astra would choose it unaided. It stays because you require it inside coding agents. The common prompt also requests relevant checks and preserves interfaces, so baseline means no extra domain skills, not no instructions.

The [documentation audit](doc-audit.md) establishes which existing claims are wrong. Deleting those claims is justified independently of whether a skill helps. Keeping a pointer to installed-version docs is a maintenance choice, not a behavior improvement isolated by this experiment.

The broad tutorial cuts are an editorial recommendation informed by the baseline results. Claims about CTE prefixes, PgBouncer, LiveView lifecycle details, Pro workflows, and other untested topics still need their own tasks if we want evidence that reminders help. I wouldn't add more context just because a detail is specialized.

The frozen [corrected](conditions/corrected/) and [pruned](conditions/pruned/) snapshots remain available for review and reproduction. The pruned set has 872 words versus 4,913 in the corrected set, but its size alone doesn't justify its remaining instructions. Production skills are unchanged pending review of this proposal.

From the external repositories, I'd borrow Bradley Golden's [dependency-local usage-rules discovery](https://github.com/bradleygolden/claude-marketplace-elixir/blob/main/plugins/elixir/skills/usage-rules/SKILL.md) as two sentences:

> Check `mix.lock` before relying on a dependency API. Read any relevant `usage-rules.md` or `usage-rules/` files under `deps/<package>/`, and use documentation for that version.

The lookup workflow itself wasn't isolated by the experiment. Skip the external skill's cache/fetch machinery, mandatory routing, and bulk context loading.

Rechecking the Oban Pro claim narrowed the actual correction: our example uses `perform/1` with `Oban.Pro.Worker`, whose documented callback remains `process/1` in stable 1.7.12 and prerelease 1.8.0-rc.1. Structured args remain optional through `args_schema`, with `job.args` cast into the worker's struct. Our existing `recorded: true` option is valid, so calling it an incorrect example was too broad. Recording can also use keyword options, and 1.8 adds global defaults and external storage. Cascade functions automatically record their results. See the [version recheck](doc-audit.md#oban-pro-recheck). These distinctions justify correcting the proposal, not expanding the skill into an API tutorial.

The other Elixir, OTP, and Phoenix tutorials haven't produced an additional instruction with demonstrated benefit here. Production upload persistence from j-morgan6's Phoenix guide is a possible next baseline task, not guidance I'd import before testing.

## Candidate rules: exceptions, debugging, and capacity

These are proposed additions for review, not production edits. The earlier six-task experiment did not establish whether Astra benefits from these rules. Keep them in the existing Elixir and OTP skills, without another routing layer or skill.

### Elixir: exceptions

- Choose failure behavior from the caller's contract. Return expected failures the caller can act on. Let broken assumptions raise. A missing user-supplied file and missing required application configuration can warrant different handling. Preserve existing API contracts when refactoring.
- Rescue only the operation and exception types for which you have a recovery or translation policy. Don't turn unrelated programming errors into ordinary domain failures. If rescuing only to add diagnostic context, use `reraise exception, __STACKTRACE__` to preserve the original failure.

### OTP: recovery

- Before relying on a crash, identify what restarts, what state it reconstructs, and what happens to in-flight callers and completed side effects. Supervision alone does not replay requests or undo external writes. Don't rely solely on `after` or `terminate/2` for cleanup after process death. Use resource ownership or a surviving monitor where appropriate, and account separately for node failure.
- Choose task isolation and result handling together. `async_nolink` removes the link, but `Task.await` still exits on failure or timeout. In a GenServer that must survive task failure, handle the task result and matching `:DOWN` asynchronously, including pending caller cleanup.

### OTP: debugging

- State a hypothesis and the observation that would disprove it before changing concurrency. Separate queue wait from execution time. Use the relevant evidence: mailbox growth, database pool wait, scheduler utilization, reductions over an interval, or memory growth. Recheck under the same workload after the fix.
- Start runtime inspection with summaries and narrow its scope. Check mailbox length before fetching messages. Limit tracing by process or function and event count or duration, then stop it. Diagnostics must not create an additional overload problem.

### OTP: capacity without premature architecture

- Before introducing a cache, pool, partition, or additional node for capacity, identify the measured bottleneck or explicit capacity requirement, the metric expected to improve, and the simplest change that meets it. Keep the current architecture when it meets the target.
- Bound externally driven concurrency and backlog, with an explicit policy when full: wait, reject, or discard according to the work's contract. Switching `call` to `cast`, spawning more tasks, or enlarging queues does not establish sustainable throughput. Size concurrency against the constrained resource.
- Treat timeout as an unknown outcome unless the API guarantees cancellation. Before retrying side effects, establish idempotency or reconcile completion. Bound retries within the operation's deadline. Verify that queues drain and latency recovers after a representative burst, not only that peak throughput improves.

### Evidence and scope

The exception rules follow the current [Elixir error guidance](https://hexdocs.pm/elixir/try-catch-and-rescue.html). The task and recovery details are supported by [Task.await/2](https://hexdocs.pm/elixir/Task.html#await/2), [Task.Supervisor.async_nolink/3](https://hexdocs.pm/elixir/Task.Supervisor.html#async_nolink/3), [supervisor restart policies](https://hexdocs.pm/elixir/Supervisor.html#module-restart-values-restart), and [GenServer termination guarantees](https://hexdocs.pm/elixir/GenServer.html#c:terminate/2). Request replay and external side-effect handling are application responsibilities inferred from these lifecycle guarantees.

The debugging and overload guidance is a synthesis of Fred Hebert's author-published [Erlang in Anger](https://www.erlang-in-anger.com/), especially chapters 3, 5, 8, and 9. Its operational principles remain useful, but tool examples must be checked against the project's installed OTP version. The downloaded preview of Francesco Cesarini and Steve Vinoski's [Designing for Scalability with Erlang/OTP](https://www.oreilly.com/library/view/designing-for-scalability/9781449361556/) contains introductory material and the table of contents, not the full book. It is not evidence of having reviewed its later chapters.

Before treating these candidates as proven skill content, compare unaided and guided runs on narrow rescue scope, task failure cleanup, ambiguous completion after timeout, and bounded overload recovery. Keep only rules that change a decision or prevent a demonstrated mistake.
