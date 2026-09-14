# Ecto persistence

Read installed-version documentation before relying on version-sensitive APIs. Repo.transact arrived in Ecto 3.13. Its function callback must return an ok/error tuple, with an error return rolling back. Repo.transaction does not interpret a returned error tuple as a rollback. Both transaction composition and return-value changes require preserving the caller's contract.

For sandboxed tests, a collaborating process needs access to the owner's checked-out connection. Explicit Sandbox.allow calls support concurrent tests when each test owns its collaborators. Shared mode grants automatic access but prevents concurrent tests. Workers must finish before the connection owner exits. Use test-supervised processes and explicit ownership rather than sleeps or global test serialization by default.

Thread authorization scope through custom queries as well as generated code. Tenant identifiers need constraints that prevent cross-tenant references, not just application filtering.

With multiple connection pools, routing is random and does not account for free connections. Total connections equal pool_size times pool_count. Tune from contention evidence. PgBouncer prepared-statement support depends on pooling mode and configuration.
