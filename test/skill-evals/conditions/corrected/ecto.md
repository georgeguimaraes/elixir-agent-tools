---
name: ecto
description: Design and debug Elixir persistence with Ecto. Use for schemas, changesets, queries, preloads, transactions, migrations, multi-tenancy, and data access through application contexts. Covers database query performance and connection pools.
---

# Ecto

Model persistence, compose queries, and keep data access within application boundaries.

## Context = Setting That Changes Meaning

Context isn't just a namespace—it changes what words mean. "Product" means different things in Checkout (SKU, name), Billing (SKU, cost), and Fulfillment (SKU, warehouse). Each bounded context may have its OWN Product schema/table.

**Think top-down:** Subdomain → Context → Entity. Not "What context does Product belong to?" but "What is a Product in this business domain?"

## Cross-Context References: IDs, Not Associations

```elixir
schema "cart_items" do
  field :product_id, :integer  # Reference by ID
  # NOT: belongs_to :product, Catalog.Product
end
```

Query through the context, not across associations. Keeps contexts independent and testable.

## DDD Patterns as Pipelines

```elixir
def create_product(params) do
  params
  |> Products.build()       # Factory: unstructured → domain
  |> Products.validate()    # Aggregate: enforce invariants
  |> Products.insert()      # Repository: persist
end
```

Use events (as data structs) to compose bounded contexts with minimal coupling.

## Schema ≠ Database Table

| Use Case | Approach |
|----------|----------|
| Database table | Standard `schema/2` |
| Form validation only | `embedded_schema/1` |
| API request/response | Embedded schema or schemaless |

## Multiple Changesets per Schema

```elixir
def registration_changeset(user, attrs)  # Full validation + password
def profile_changeset(user, attrs)       # Name, bio only
def admin_changeset(user, attrs)         # Role, verified_at
```

Different operations = different changesets.

## Multi-Tenancy: Composite Foreign Keys

```elixir
add :post_id, references(:posts, with: [org_id: :org_id], match: :full)
```

Use `prepare_query/3` for automatic scoping. Raise if `org_id` missing.

Thread authorization scope through custom queries as well as generated code. Tenant identifiers need constraints that prevent cross-tenant references, not just application filtering.

## Preload vs Join Trade-offs

| Approach | Best For |
|----------|----------|
| Separate preloads | Has-many with many records (less memory) |
| Join preloads | Belongs-to, has-one (single query) |

Join preloads repeat parent columns for each joined child row. Consider the resulting row count and payload for the actual associations and workload.

## CRUD Contexts Are Fine

> "If you have a CRUD bounded context, go for it. No need to add complexity."

Use generators for simple cases. Add DDD patterns only when business logic demands it.

## Gotchas from Core Team

### CTE Prefixes Need Query-Specific Attention

Parent-query, schema-source, and CTE-reference prefixes are distinct. Referencing a CTE through a schema tuple can inherit that schema's prefix. Use a query-level `prefix: nil` when overriding an inherited schema prefix is appropriate. Inspect generated SQL rather than setting every recursive query to a tenant prefix.

### Parameterized Queries ≠ Prepared Statements

- **Parameterized queries:** `WHERE id = $1` — always used by Ecto
- **Prepared statements:** Query plan cached by name — can be disabled

**PgBouncer:** Check pooling mode and configuration. Transaction pooling supports protocol-level prepared statements when `max_prepared_statements` is nonzero. `prepare: :unnamed` is an option when the deployment cannot support named statements. SQL `PREPARE` is a separate feature.

### pool_count vs pool_size

Queries are randomly routed among pools without considering available connections. Total connections equal `pool_size * pool_count`. Tune pool settings from measured contention and workload behavior.

### Sandbox Access for Collaborating Processes

Other processes can share the sandbox owner's connection through explicit allowances or shared mode. Allowances support concurrent tests with appropriate isolation. Shared mode grants automatic access but requires nonconcurrent tests. Ensure collaborating workers finish before the connection owner exits.

Use explicit `Sandbox.allow` calls when each test owns its collaborators. Prefer test-supervised processes and explicit ownership over sleeps or globally serializing otherwise isolated tests.

### PostgreSQL Text Rejects NUL

PostgreSQL rejects NUL in character values. This does not mean the database server crashes. Validate input according to the application's data contract. Removing characters silently is a policy choice, not a universal fix.

### preload_order for Association Sorting

```elixir
has_many :comments, Comment, preload_order: [desc: :inserted_at]
```

Note: Doesn't work for `through` associations.

### Runtime Migrations Use List API

```elixir
Ecto.Migrator.run(Repo, [{0, Migration1}, {1, Migration2}], :up, opts)
```

## Idioms

- Prefer `Repo.insert/1` over `Repo.insert!/1`—handle `{:ok, _}` / `{:error, _}` explicitly
- `Repo.transact/1` is available from Ecto 3.13. Function callbacks must return `{:ok, value}` or `{:error, reason}`, and the error tuple rolls back. `Repo.transaction/1` instead wraps a normal return and does not treat a returned error tuple as a rollback. `Repo.transact` also accepts `Ecto.Multi`. Choose the API and composition that fit the operation.

## Red Flags - STOP and Reconsider

- belongs_to pointing to another context's schema
- Single changeset for all operations
- Preloading has-many with join
- CTEs in multi-tenant apps whose generated SQL has not been checked for correct prefixes
- Assuming PgBouncer prepared-statement support without checking pooling mode and configuration
- Collaborating database processes without sandbox access or a lifetime bounded by the connection owner
- Changing user data through unconditional NUL removal without a defined policy

**Any of these? Re-read the Gotchas section.**
