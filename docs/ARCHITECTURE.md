# Sendblue Events Architecture

This plugin is the presentation layer of Sendblue's real-time-events path. It deliberately wraps the Sendblue CLI instead of handling API credentials in QML.

## Data flow

```text
authoritative Sendblue domain commit
  -> best-effort account-scoped Redis pub/sub
  -> authenticated GET /api/v2/events (SSE)
  -> sendblue@3.11 client.events.stream()
  -> sendblue events --jsonl --include-control
  -> Omarchy bar widget, activity popup, and live notifications
```

The account is always derived from Grayrunner's existing authenticated request. The stream and recovery routes do not accept an email, company slug, company ID, account, or worker selector from the caller. Line-scoped temporary tokens are denied account-wide stream and snapshot access.

## Event catalog

- `message.received`
- `message.created`
- `message.updated`
- `typing.changed`
- `line.assigned`
- `line.unassigned`
- `line.status.changed`
- `line.blocked`
- `contact.created`
- `verification.approved`
- `verification.expired`
- `verification.canceled`

Calls and FaceTime events are intentionally outside this project.

Every public event has a version-one envelope:

```json
{
  "version": 1,
  "id": "message:example:received",
  "type": "message.received",
  "occurred_at": "2026-08-16T00:00:00.000Z",
  "data": { "message_id": "example" }
}
```

## Delivery and recovery

Redis pub/sub provides low-latency cross-instance fanout; it is not retained history. The server sends heartbeats, bounds active connections, closes slow clients, fails closed if its Redis subscription is unhealthy, and rotates every stream after 15 minutes to force reauthentication.

The CLI connects through the official SDK's generated SSE resource first, performs recovery while live frames buffer in the response, and then consumes/deduplicates the overlap. It stores a bounded per-credential cursor in a mode-`0600` file under `~/.sendblue/`. Line recovery also emits a CLI-only `lines.snapshot` control record; the widget atomically replaces its line map from that complete array instead of treating a snapshot as deduplicated live transitions. A `recovery.warning` control record keeps the live connection usable while visibly reporting a partially failed recovery source.

Recovery is domain-specific:

- messages: `updated_at_gte`, ordered ascending, one-minute overlap;
- contacts: `created_at_gte` plus immutable `contact_id`;
- line membership/health: `/api/v2/lines/state` snapshot;
- verification terminal state: account-scoped `updated_at_gte` list;
- typing: intentionally ephemeral and not recovered.

Recovered inbound messages may increase unread state, but the plugin only sends desktop notifications for live inbound events. The line snapshot replaces stale membership and health after reconnect.

## Repository map

- `sb-api-v2`: PR #1742 merged and deployed as `80a2eb82`; producers, Redis/SSE transport, recovery routes, OpenAPI, and tests.
- `sendblue-ts`: generated SDK `sendblue@3.11.0` published with `client.events.stream()`.
- `sendblue-cli`, branch `draft/omarchy-realtime-events-20260816`: 0.10 release candidate; SDK-backed JSONL command, credential-isolated cursors, reconnect, recovery, and dedupe.
- `omarchy-sendblue-plugin`, this repository: bar widget and pure-JavaScript model release candidate.

## Release boundary

Nothing in this repository deploys or enables the backend, CLI, SDK, or plugin. Publish and install the widget only after the matching CLI 0.10 release completes normal review and npm publication.

Exact offline replay would require a retained event log or transactional outbox spanning multiple domains. That is a separate platform decision; this plugin instead converges current durable state through bounded recovery APIs.
