---
name: oban
description: Build and debug durable background jobs with Oban and Oban Pro. Use for workers, job argument serialization, retries, scheduled or recurring jobs, uniqueness, batches, and workflows. Use otp for in-memory tasks and process supervision.
---

# Oban

Handle durable jobs, serialization, failures, and workflow composition with Oban.

---

# Part 1: Oban (Non-Pro)

## The Iron Law: JSON Serialization

```
JOB ARGS ARE JSON. ATOMS BECOME STRINGS.
```

This single fact causes most Oban debugging headaches.

```elixir
# Creating - atom keys are fine
MyWorker.new(%{user_id: 123})

# Processing - must use string keys (JSON converted atoms to strings)
def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
  # ...
end
```

## Error Handling: Let It Crash

**Don't catch errors in Oban jobs.** Let them bubble up to Oban for proper handling.

### Why?

1. **Automatic logging**: Oban logs the full error with stacktrace
2. **Automatic retries**: Jobs retry with exponential backoff
3. **Visibility**: Failed jobs appear in Oban Web dashboard
4. **Consistency**: Error states are tracked in the database

### Anti-Pattern

```elixir
# Bad: Swallowing errors
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} ->
      Logger.error("Failed: #{reason}")
      {:ok, :failed}  # Silently marks as complete!
  end
end
```

### Correct Pattern

```elixir
# Good: Let errors propagate
def perform(%Oban.Job{} = job) do
  result = do_work!(job.args)  # Raises on failure
  {:ok, result}
end

# Or return error tuple - Oban treats as failure
def perform(%Oban.Job{} = job) do
  case do_work(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, reason} -> {:error, reason}  # Oban will retry
  end
end
```

### When to Catch Errors

Only catch errors when you need custom retry logic or want to mark a job as permanently failed:

```elixir
def perform(%Oban.Job{} = job) do
  case external_api_call(job.args) do
    {:ok, result} -> {:ok, result}
    {:error, :not_found} -> {:cancel, :resource_not_found}  # Don't retry
    {:error, :rate_limited} -> {:snooze, 60}  # Retry in 60 seconds
    {:error, _} -> {:error, :will_retry}  # Normal retry
  end
end
```

## Snoozing for Polling

Use `{:snooze, seconds}` to reschedule polling. Bound polling with an explicit deadline or snooze limit. From Oban 2.24, core snoozing rolls back `attempt` and increments `meta.snoozed`, so `max_attempts` alone does not bound repeated snoozes. Older versions and configured engines may differ. Smart Engine supported attempt-preserving snoozes before this core change:

```elixir
def perform(%Oban.Job{} = job) do
  cond do
    external_thing_finished?(job.args) -> {:ok, :done}
    polling_expired?(job) -> {:cancel, :polling_expired}
    true -> {:snooze, 5}
  end
end
```

## Simple Job Chaining

For simple sequential chains (JobA → JobB → JobC), have each job enqueue the next:

```elixir
def perform(%Oban.Job{} = job) do
  result = do_work(job.args)
  case NextWorker.new(%{data: result}) |> Oban.insert() do
    {:ok, _next_job} -> {:ok, result}
    {:error, reason} -> {:error, reason}
  end
end
```

Explicit enqueueing can be sufficient for a small chain. Workflows also support linear dependencies when tracking or composition is useful. Preserve enqueue errors and account for duplicate side effects if the current job retries.

Completion and follow-on work need the intended persistence and idempotency guarantees. Return failure when any required work fails.

## Unique Jobs

Prevent duplicate jobs with the `unique` option:

```elixir
use Oban.Worker,
  queue: :default,
  unique: [period: 60]  # Only one job with same args per 60 seconds

# Or scope uniqueness to specific fields
unique: [period: 300, keys: [:user_id]]
```

**Gotcha:** Uniqueness is checked on insert, not execution. With a 60-second uniqueness period, identical jobs inserted 61 seconds apart can both run. It is not an exactly-once execution guarantee.

## High Throughput: Chunking

For millions of records, **chunk work into batches** rather than one job per item:

```elixir
# Bad: One job per contact (millions of jobs = database strain)
Enum.each(contacts, &ContactWorker.new(%{id: &1.id}) |> Oban.insert())

# Good: Chunk into batches
contacts
|> Enum.chunk_every(100)
|> Enum.each(&BatchWorker.new(%{contact_ids: Enum.map(&1, fn c -> c.id end)}) |> Oban.insert())
```

Bulk-insert uniqueness support and guarantees depend on the installed version and engine. Verify those contracts before trading uniqueness for throughput. Unique insertion is not an exactly-once execution guarantee.

---

# Part 2: Oban Pro

## Cascade Context: Erlang Term Serialization

Unlike regular job args, **cascade context preserves atoms**:

```elixir
# Creating - atom keys
Workflow.put_context(%{score_run_id: id})

# Processing - atom keys still work!
def my_cascade(%{score_run_id: id}) do
  # ...
end

# Dot notation works too
def later_step(context) do
  context.score_run_id
  context.previous_result
end
```

### Serialization Summary

| | Creating | Processing |
|-----------------|----------|--------------|
| Regular jobs | atoms ok | strings only |
| Cascade context | atoms ok | atoms ok |

## When to Use Workflows

Reserve Workflows for:
- Sequential or complex dependency graphs that benefit from tracking and composition
- Fan-out/fan-in patterns
- When you need recorded values across steps
- Conditional branching based on runtime state

Simple A → B → C chains can use explicit enqueueing or workflows according to their tracking and composition needs.

## Workflow Composition with Graft

`add_workflow/4` composes an already-built subworkflow, and dependent jobs can wait for all of its jobs. `add_graft` supports dynamically constructing and attaching a subworkflow during execution. Choose based on when the subworkflow is known, not on an assumption that only grafts wait for completion.

### Pattern: Composing Independent Concerns

Don't couple unrelated concerns (e.g., notifications) to domain-specific workflows (e.g., scoring). Instead, create a higher-level orchestrator:

```elixir
# Bad: Notification logic buried in AggregateScores
defmodule AggregateScores do
  def workflow(score_run_id) do
    Workflow.new()
    |> Workflow.add(:aggregate, AggregateJob.new(...))
    |> Workflow.add(:send_notification, SendEmail.new(...), deps: :aggregate)  # Wrong place!
  end
end

# Good: Higher-level workflow composes scoring + notification
defmodule FullRunWithNotifications do
  def workflow(site_url, opts) do
    notification_opts = build_notification_opts(opts)

    Workflow.new()
    |> Workflow.put_context(%{notification_opts: notification_opts, site_url: site_url, opts: opts})
    |> Workflow.add_graft(:scoring, &graft_full_run/1)
    |> Workflow.add_cascade(:send_notification, &send_notification/1, deps: :scoring)
  end

  defp graft_full_run(context) do
    # Sub-workflow doesn't know about notifications
    FullRun.workflow(context.site_url, context.opts)
    |> Workflow.apply_graft()
    |> Oban.insert_all()
  end
end
```

### Recording Values for Dependent Steps

`Oban.Worker` implements `perform/1`. `Oban.Pro.Worker` implements `process/1`. With Pro `args_schema`, persisted JSON args are cast into the worker's struct before execution. Without structured args, match the persisted string keys.

For a grafted workflow's output to be available to dependent steps, the final job must use `recorded: true`:

```elixir
defmodule FinalJob do
  use Oban.Pro.Worker, queue: :default, recorded: true

  def process(%Oban.Job{args: %{"score_run_id" => score_run_id}}) do
    score = calculate_score(score_run_id)
    {:ok, %{score_run_id: score_run_id, composite_score: score}}
  end
end
```

## Dynamic Workflow Appending

Add jobs to a running workflow with `Workflow.append/2`:

```elixir
def perform(%Oban.Job{} = job) do
  if needs_extra_step?(job.args) do
    job
    |> Workflow.append()
    |> Workflow.add(:extra, ExtraWorker.new(%{}), deps: [:current_step])
    |> Oban.insert_all()
  end
  {:ok, :done}
end
```

**Caveat:** Cannot override context or add dependencies to already-running jobs. For complex dynamic scenarios, check external state in the job itself.

## Fan-Out/Fan-In with Batches

Batch callbacks can coordinate work after batch completion. Configure the documented `callback_worker` and callbacks such as `batch_completed/1`. `Batch.new` takes a list of changesets first and options second, and batches are inserted with `Oban.insert_all`. Check the installed Pro version before combining batches with dynamic workflows, and include all relevant work before relying on completion.

## Testing Workflows

**Use manual testing mode for workflows** - workflow integration tests need database interaction, not inline execution.

```elixir
# Use run_workflow/1 for integration tests
assert %{completed: 3} =
  Workflow.new()
  |> Workflow.add(:a, WorkerA.new(%{}))
  |> Workflow.add(:b, WorkerB.new(%{}), deps: [:a])
  |> Workflow.add(:c, WorkerC.new(%{}), deps: [:b])
  |> run_workflow()
```

For testing recorded values between workers, insert predecessor jobs with pre-filled metadata.

---

# Red Flags - STOP and Reconsider

**Non-Pro:**
- Pattern matching on atom keys in `perform/1`
- Catching all errors and returning `{:ok, _}`
- Wrapping job logic in try/rescue
- Creating one job per item when processing millions of records

**Pro:**
- Coupling notifications/emails to domain workflows
- Not using `recorded: true` when you need output from grafted workflows
- Testing workflows with inline mode

**Any of these? Re-read the serialization rules.**
