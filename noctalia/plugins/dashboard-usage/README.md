# Noctalia plugin — Dashboard

A [Noctalia](https://noctalia.dev) bar widget that reads the dashboard server you
already run. It has no data of its own and no Python of its own — a thin QML
front-end over `GET /api/usage`, the same payload the Svelte UI consumes.

```
┌──────────────────────────────────────────┐
│  ✳ 63%                    ← the bar pill │
└──────────────────────────────────────────┘
   ↑ Claude mark: orange = live, grey = down
        click ↓
┌──────────────────────────────────────────┐
│ ● Dashboard           updated 12s ago ⟳ ↗│
│                                          │
│ ┌ Limits ───────────────── 2h51m left ─┐ │
│ │ 5-hour        ███████░░░░░░░░    63% │ │
│ │ 7-day         █████████░░░░░░    71% │ │
│ │ Cap · weekly  ████░░░░░  $22 / $80   │ │
│ └──────────────────────────────────────┘ │
│ ┌ Tokens · this 5-hour window ─────────┐ │
│ │ 4.8M                      169k/min   │ │
│ │                           throughput │ │
│ │ projected by window end        11.2M │ │
│ └──────────────────────────────────────┘ │
│ ┌ Cost ────────────────────────────────┐ │
│ │ spent $4.21 · burn $1.80/h · proj $9 │ │
│ └──────────────────────────────────────┘ │
│ ● cachyos  ● ubuntuserver                │
└──────────────────────────────────────────┘
```

## Dependency

**This plugin requires a running dashboard server** (the `server.py` in the repo
root). It does not read `ccusage`, Claude logs, or anything else directly —
if the server is down the widget says `offline` and the panel tells you so.

Point it at whichever instance you already use — the default is the always-on
box, since a local `server.py` is usually not running:

- always-on box: `http://ubuntuserver:8443` (default)
- over Tailscale: `https://ubuntuserver.<your-tailnet>.ts.net`
- local: `http://127.0.0.1:8787`

That means the plugin inherits everything the server already does — multi-machine
aggregation, the stale-while-revalidate cache, cached data for sleeping laptops.

## Install

```sh
./install.sh
```

This symlinks the directory into `~/.config/noctalia/plugins/dashboard-usage`,
so the plugin lives in this repo and updates with it. Then:

1. Noctalia → **Settings → Plugins → Installed** → enable **Dashboard**.
   (Local plugins are discovered by a folder scan and start *disabled*.)
   Enabling automatically adds the pill to the right section of your bar.
2. If your server isn't at the default URL, set it in the plugin's **settings**
   (gear icon).

Remove with `./install.sh --uninstall`.

## What it shows

**Bar pill** — the Claude mark plus one number. The logo doubles as the liveness
indicator: **orange when the server is answering, grey when it isn't**. The
number is configurable:

| Mode | Shows |
|---|---|
| `auto` (default) | Plan % when the server has it, otherwise window spend |
| `plan` | Plan / configured-cap percentage |
| `tokens` | Tokens used in the active 5-hour window |
| `spend` | Spent so far in the active 5-hour window |
| `burn` | Live burn rate in `$/hour` |
| `projected` | Projected cost of the whole window |
| `remaining` | Time left in the window |

**Panel** — ordered by what actually governs a session:

1. **Limits** — every gauge the server could compute: real plan percentages when
   Anthropic exposes them, configured USD caps otherwise, with the time left in
   the window in the header. Gauges with no data — a cap left at `0`, meaning
   *track only* — are omitted rather than shown empty. Amber past your warning
   threshold, red past critical (defaults 75% / 90%).
2. **Tokens** — used this window, live throughput, projection to window end.
3. **Cost** — spend, burn rate, projection.

Then a dot per collector machine, so a sleeping laptop is visibly dropped.

Cards are forced opaque rather than inheriting the panel's translucency, which
keeps the small figures legible over a busy wallpaper.

**Interactions** — left click opens the panel, middle click forces a refresh,
right click gives Refresh / Open dashboard / Widget settings. The refresh button
requests `?sync=1`, which makes the aggregator bypass its cache and re-pull every
collector now.

## Files

| File | Role |
|---|---|
| `Main.qml` | The only data source: one timer, one in-flight request, all derived display strings. Bar and panel share it via `pluginApi.mainInstance`. |
| `BarWidget.qml` | The pill. Pure presentation. |
| `ClaudePill.qml` | The capsule itself. Noctalia's `BarPill` draws icons from the Tabler font and can't show an image, so the capsule is rebuilt with the same Style tokens to lead with the Claude mark. |
| `claudeLogo.js` | The logo's 24×24 path, rendered to an SVG data URI with the fill baked in — that's what allows orange/grey recolouring. |
| `Panel.qml` | Detail view: limits, tokens, cost, machines. |
| `Settings.qml` | URL, poll interval, bar metric, thresholds. |
| `manifest.json` | Entry points + `defaultSettings`. |

## Notes

- Strings are plain English; there is no `i18n/` yet. Noctalia supports
  `pluginApi.tr()` with `i18n/<lang>.json` if this is ever localised.
- Noctalia's hot reload follows symlinks, so with debug mode on you can edit
  these files in the repo and see changes without restarting the shell.
