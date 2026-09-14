# Omantfy

Subscribe to an [ntfy](https://ntfy.sh) topic from the Omarchy bar. Incoming
messages become Omarchy desktop notifications, and the bar panel keeps a short
history you can click through.

## Install

```bash
omarchy plugin add https://github.com/gianmegantara/omantfy.git --enable --yes
```

Then click the bell, set your **Topics** (and **Access token** if your server
requires auth), and **Save**.

## Usage

- **Left click** the bell — open the recent-messages panel.
- **Right click** — reconnect the stream.
- **Middle click** — toggle desktop notifications.

The panel's gear opens the settings form. Set the **server**, **topic**, and an
optional **access token**, then **Save**. The subscription reconnects
immediately; you do not need to restart the shell.

The first time you open the panel it lands on the settings form, since there is
no topic yet.

## Settings

Stored inline in `~/.config/omarchy/shell.json` under the widget entry.

| Key | Default | Meaning |
|---|---|---|
| `server` | `https://ntfy.giandev.site` | Base URL of the ntfy server. |
| `topic` | *(empty)* | One or more topics, comma-separated. Empty disables the stream. |
| `token` | *(empty)* | Bearer token for protected topics. |
| `notify` | `true` | Raise a desktop notification per message. |
| `sound` | `true` | Play a sound per message (primary screen only). |
| `soundFile` | freedesktop `message-new-instant.oga` | Audio file played with `pw-play`. |
| `glyph` | bell glyph | Nerd Font glyph shown in the bar. |
| `unreadColor` | `#f5c542` | Bar glyph colour while there are unread messages. |
| `maxMessages` | `30` | How many recent messages the panel keeps. |

You can also set them from a terminal:

```bash
omarchy bar set gian.omantfy server https://ntfy.sh
omarchy bar set gian.omantfy topic my-topic
omarchy bar set gian.omantfy token tk_xxx
omarchy bar set gian.omantfy notify true --json
```

## Multiple topics

Put a comma-separated list in **Topics** and ntfy subscribes to all of them in
one stream:

```bash
omarchy bar set gian.omantfy topic "alerts, releases, build-status"
```

Each message keeps its own topic, so the panel tags every row with the topic it
came from when more than one is configured. All topics share the one server and
access token.

## Behaviour

- The bell is the normal bar colour at rest and turns **yellow** while there
  are unread messages. Opening the panel clears it; a message that arrives
  while the panel is open stays read.
- The topics are streamed with `curl -sS --fail --no-buffer <server>/<topics>/json`.
- ntfy priorities map to Omarchy urgencies: `1–2` → low, `3–4` → normal,
  `5` → critical.
- A message's `click` URL becomes the notification's click action (opened with
  `xdg-open`).
- An optional sound plays for each message via `pw-play` (the panel has a
  preview button). Toggle it with **Play a sound** or the `sound` setting.
- On `401`/`403` (wrong topic or token) the stream stops and waits for a
  settings change or a manual reconnect instead of retrying in a loop. Other
  failures reconnect after 5 seconds.
- Notifications are raised only on the primary screen, so a multi-monitor bar
  does not toast each message once per output.

## IPC

```bash
omarchy-shell gian.omantfy toggle     # open/close the panel
omarchy-shell gian.omantfy reconnect  # reconnect the stream
omarchy-shell gian.omantfy clear      # drop the recent-message list
omarchy-shell gian.omantfy status     # idle | connecting | connected | error | unconfigured
omarchy-shell gian.omantfy info       # JSON: status, server, topic(s), messages, error
```

## Files

- `manifest.json` — plugin declaration and settings schema.
- `BarWidget.qml` — bar icon, panel wiring, settings persistence.
- `Service.qml` — the ntfy stream, message parsing, and notification dispatch.
- `NtfyPanel.qml` — the popup panel (status, settings form, message list).
