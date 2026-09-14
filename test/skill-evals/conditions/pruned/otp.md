# OTP concurrency

A GenServer serializes callbacks. Slow work in handle_continue still occupies the server even though start_link can return after init. Use a separate task when the server must remain responsive during that work.

Task.Supervisor.async remains linked to the caller. async_nolink removes that link, but Task.await can still exit the caller on task failure or timeout. When recovering within a GenServer, handle task result and DOWN messages, clear completed monitors, and define what happens to callers when work fails or the server stops.

Choose supervision strategies from actual dependencies. Do not add processes solely to organize code. Scope dynamically named processes through Registry instead of allocating atoms from identifiers.

When using ETS to bypass serialized reads, account for table ownership and the owner's restart. A monitor provides notification of process termination, while terminate callbacks are not guaranteed for every exit.
