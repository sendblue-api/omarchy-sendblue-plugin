# Sendblue Events for Omarchy

A native Omarchy bar widget for live Sendblue account activity. It wraps the official `sendblue events` CLI command, so credentials stay in the CLI's existing `~/.sendblue/credentials.json`; the plugin never stores API keys.

The complete runtime path is published: the Grayrunner event/recovery API is deployed, `sendblue@3.11.0` is available on npm, and `@sendblue/cli@0.10.0` is the npm `latest` release. Merely cloning this repository does not start anything.

The widget shows unread inbound activity and current line health. Its bounded, scrollable popup keeps recent account activity usable even with many lines. New inbound messages can trigger desktop notifications. Right-click opens `sendblue messages`; middle-click restarts the stream.

## Requirements

- Omarchy 4 plugin-capable shell
- Sendblue CLI 0.10.0 or newer with the `events` command
- A Sendblue API deployment containing `GET /api/v2/events` and the recovery endpoints

## Install from a checkout

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/sendblue.events
omarchy-shell shell rescanPlugins
omarchy plugin enable sendblue.events right
```

For the published repository, use:

```bash
omarchy plugin add https://github.com/sendblue-api/omarchy-sendblue-plugin --enable
```

The CLI honors `SENDBLUE_API_BASE`, so local Grayrunner testing can point at a development server without changing the plugin. The plugin is intentionally safe when the endpoint is unavailable: it displays the disconnect reason and retries. Partial recovery failures remain connected but surface a visible recovery warning instead of silently presenting stale state.

For a local integration test, launch Omarchy Shell from a terminal that exports `SENDBLUE_API_BASE` to an isolated Grayrunner development server.

## Event guarantees

The SSE connection is live delivery, not a permanent log. The CLI reconnects automatically and repairs gaps with timestamp-based message/contact/verification queries plus the account line-state snapshot. Typing indicators are ephemeral.

Recovered inbound messages increase the unread count but do not generate a stale desktop notification. Immediate line removals disappear from the popup; grace-period lines remain until the recovery snapshot no longer includes them.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the complete event catalog, security boundary, recovery model, and cross-repository release map.

## Development

Validate the manifest with:

```bash
omarchy plugin validate .
```

`Model.js` is deliberately plain JavaScript and can be unit-tested under Node without launching Quickshell.
