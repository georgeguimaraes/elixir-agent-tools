# Phoenix interfaces

mount and handle_params run for both disconnected and connected initial renders. Use handle_params for data affected by patch navigation. Moving a query between those callbacks does not deduplicate initial work. Async tasks only start when connected. Extract the values needed by an async closure rather than capturing the full socket.

assign_new may reuse disconnected conn assigns or eligible parent assigns, but does not preserve arbitrary disconnected computations across connection.

Scopes are threaded by configured generators. Custom queries and event handlers still need authorization. Phoenix Channel handle_out receives current channel socket state. Intercept outgoing events when delivery depends on recipient state, and apply the current recipient-specific policy.

Reusing a start_async name makes the latest result win. Cancel the previous task if the work itself must stop. Do not treat name reuse as inherently wrong.

Do not rely on terminate/2 for guaranteed cleanup. Use an appropriately owned monitor when cleanup must observe process departure. For webhook signature verification, preserve raw bytes through a scoped Plug.Parsers body_reader with size and error handling.
