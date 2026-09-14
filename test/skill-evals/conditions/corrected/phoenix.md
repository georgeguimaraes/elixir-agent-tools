---
name: phoenix
description: Build and debug Phoenix web interfaces and HTTP endpoints. Use for LiveView lifecycle and data loading, components, forms, routes, controllers, Plug, channels, and PubSub. Use ecto for changesets, queries, and persistence behind those interfaces.
---

# Phoenix

Structure Phoenix interfaces, load LiveView data, and scope real-time updates.

## Where to Load Data: mount vs handle_params

Default: load data in `mount/3`.

```elixir
def mount(_params, _session, socket) do
  posts = Blog.list_posts(socket.assigns.current_scope)
  {:ok, assign(socket, posts: posts)}
end
```

Yes, mount runs twice on initial load (HTTP dead render + WebSocket connect). So does `handle_params/3`. That's the LiveView lifecycle, not a bug to route around. Moving queries from mount to handle_params does not dedupe them.

Use `handle_params/3` for data that changes on live navigation (`push_patch` / `<.link patch={...}>`). mount does not re-run on patches, handle_params does.

```elixir
def handle_params(%{"filter" => filter}, _uri, socket) do
  posts = Blog.list_posts(socket.assigns.current_scope, filter)
  {:noreply, assign(socket, posts: posts, filter: filter)}
end
```

When the initial double-load actually matters, the real tools are:
- `connected?(socket)` to gate work to the connected render (loses SEO / no-JS rendering)
- `assign_async/3` to load in a separate process only when connected, without blocking rendering on its result
- `assign_new/3` to reuse values already set on `conn.assigns` by upstream Plugs (e.g. `:current_user`), or shared from a parent LiveView when the child is mounted with its parent and is not sticky. It does not dedupe arbitrary work across the dead/connected boundary. When no existing or shared assign is available, its function runs again on connected mount.

```elixir
def mount(_params, _session, socket) do
  posts = if connected?(socket), do: Blog.list_posts(socket.assigns.current_scope), else: []
  {:ok, assign(socket, posts: posts)}
end
```

## Scopes: Security-First Pattern (Phoenix 1.8+)

Scopes address OWASP #1 vulnerability: Broken Access Control. Phoenix generators thread configured scopes through generated LiveViews, controllers, and context functions. Custom queries and operations still need explicit scoping and authorization.

```elixir
def list_posts(%Scope{user: user}) do
  Post |> where(user_id: ^user.id) |> Repo.all()
end
```

## PubSub Topics Must Be Scoped

```elixir
def subscribe(%Scope{organization: org}) do
  Phoenix.PubSub.subscribe(@pubsub, "posts:org:#{org.id}")
end
```

Unscoped topics = data leaks between tenants.

## External Polling: GenServer, Not LiveView

**Bad:** Every connected user makes API calls (multiplied by users).
**Good:** Single GenServer polls, broadcasts to all via PubSub.

## Components Receive Data, LiveViews Own Data

- **Functional components:** Display-only, no internal state
- **LiveComponents:** Own state, handle own events
- **LiveViews:** Full page, owns URL, top-level state

## Async Data Loading

Use `assign_async/3` for data that can load after mount:

Extract the values needed by an async closure rather than capturing the full socket.

```elixir
def mount(_params, _session, socket) do
  {:ok, assign_async(socket, :user, fn -> {:ok, %{user: fetch_user()}} end)}
end
```

## Gotchas from Core Team

### LiveView terminate/2 Is Not Guaranteed Cleanup

`terminate/2` can run without trapping exits, including graceful client departure, but is not guaranteed for every exit. Trapping exits changes process semantics and is not a universal cleanup solution.

**Fix:** Use a separate GenServer that monitors the LiveView process via `Process.monitor/1`, then handle `:DOWN` messages to run cleanup.

### start_async Duplicate Names: Later Wins

Calling `start_async` with the same name while a task is in-flight: the **later one wins**, the previous task's result is ignored.

**Fix:** Call `cancel_async/3` first if you want to abort the previous task.

Name reuse is appropriate when only the latest result matters. Cancel the previous task when the work itself must stop.

### Channel Intercepts Use Current Socket State

Phoenix Channel `handle_out` receives current channel socket state. Intercept outgoing events when delivery depends on recipient state, and apply the current recipient-specific policy.

### CSS Class Precedence is Stylesheet Order

When merging classes on components, precedence is determined by **stylesheet order**, not HTML order. If `btn-primary` appears later in the compiled CSS than `bg-red-500`, it wins regardless of HTML order.

**Fix:** Use variant props instead of class merging.

### Upload Content-Type Can't Be Trusted

The `:content_type` in `%Plug.Upload{}` is user-provided. Always validate actual file contents (magic bytes) and rewrite filename/extension.

### Preserve Raw Webhook Bodies

Signature verification needs the original body bytes. Configure an appropriate `Plug.Parsers` `:body_reader` to retain bytes for the relevant webhook requests before parsing consumes them. Handle the `read_body/2` complete, partial, and error returns with explicit request-size limits. A body reader is not used by the multipart parser. Avoid retaining bodies for unrelated requests.

## Red Flags - STOP and Reconsider

- Loading patch-mutable data in mount/3 instead of handle_params/3
- Unscoped PubSub topics in multi-tenant app
- LiveView polling external APIs directly
- Relying on terminate/2 for cleanup that must run after every exit
- CSS class merging for component customization (use variants)
- Trusting `%Plug.Upload{}.content_type` for security

**Any of these? Re-read the Gotchas section.**
