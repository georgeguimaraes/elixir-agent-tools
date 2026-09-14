# Oban jobs

Check the installed Oban version and engine before applying Pro or version-specific advice. Ordinary args are persisted as JSON, so worker keys are strings. Oban.Pro.Worker uses process/1, not perform/1, and optional args_schema casts args into a worker struct before execution.

Return failure when the job's required work fails. Do not turn a failed downstream enqueue into success. Retries can repeat side effects, so completion and follow-on work need the intended persistence and idempotency guarantees.

Snoozing does not impose a total polling deadline. In Oban 2.24 and Pro's attempt-preserving engines, snooze rolls back attempt and increments meta["snoozed"]. Earlier core versions have different accounting. Use an explicit deadline or a supported snooze counter when polling must eventually stop, rather than assuming attempt exhaustion.

Uniqueness guarantees and bulk-insert support depend on engine and version. Uniqueness is not an exactly-once execution guarantee.

For Pro workflows, add_workflow composes a known workflow and allows dependents to wait for it. Grafts construct subworkflows dynamically during execution. Supply all context a graft reads. Recorded outputs require recorded: true and the appropriate successful return contract. Batch callbacks use callback_worker and callbacks such as batch_completed/1, with batch insertion through Oban.insert_all. Check the installed API before copying workflow examples.

Workflow integration tests use manual mode and the documented workflow-testing helpers rather than inline mode.
