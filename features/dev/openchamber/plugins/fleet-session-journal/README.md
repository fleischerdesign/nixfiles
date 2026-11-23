# Fleet Session Journal

A service-only built-in extension: it has no rail panel. OpenChamber posts the
four session lifecycle events to `POST /session-events` whenever a turn
finishes or fails, a permission is requested, or a question is asked. The
service appends each request as one JSON line to `events.jsonl` in its private
`OPENCHAMBER_SERVICE_DATA_DIR`.

`content: true` records the reply, permission detail or question content. That
is useful for fleet debugging and audit, but it can contain source code and
agent output; treat the extension data directory as sensitive. Disable the
extension to stop writes; its data stays until the extension is removed.

The service is intentionally small and has no panel. It is also the fixture
for panel-less extension packaging: `openchamber.id` is top-level and no
`contributes.panel` exists.
