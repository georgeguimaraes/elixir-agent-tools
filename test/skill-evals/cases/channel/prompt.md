An open document channel must react to permission changes without making the user reconnect. The application already sends `{:access_changed, boolean}` messages to the channel. Fix the channel so each subsequent `document_changed` broadcast is delivered only while access is allowed, including granting access again after it was revoked. Preserve the topic, event name, and broadcast payload. Keep the existing callback interface and return values.

Work in `lib/access_channel.ex`. Run the available tests before finishing.
