# Omarchy NextEvent

A **next-meeting chip** for the [Omarchy](https://omarchy.org/) bar: live countdown from Google Calendar (or any iCal feed), one-click Join (Meet / Zoom / Teams / Webex / GoTo), multi-day agenda panel — with data that never leaves your machine.

> **⚡ Built for Omarchy:** this repo is [austrasien](https://github.com/austrasien)’s fork of [tobiasz-p/next-event](https://github.com/tobiasz-p/next-event). Upstream already does the hard work (ICS + OAuth sync, Meet join, agenda). This fork adds a **bar lead time** (title only when the event is soon), more reliable **Omarchy web-app** meeting opens (`google-app-open` with `xdg-open` fallback), and a few QML/`shell.json` parsing fixes.

```
Calendar feed  →  bar chip (title near start)  →  agenda panel / Join meeting
```

Upstream credit: **[tobiasz-p](https://github.com/tobiasz-p)** — MIT. Plugin id stays `tobiasz-p.next-event` so an existing bar entry keeps working.

---

### ☕ Support the Project
If this saves you from missing the next Meet while the bar stays quiet, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

### 💬 Feedback & Community
Got a question, found a bug, or have a suggestion? Open an [**issue**](https://github.com/austrasien/omarchy-next-event/issues).

---

## 🚀 Overview

NextEvent watches your calendars and surfaces the next actionable meeting in the Omarchy bar. Private iCal URLs and OAuth tokens stay on your machine — the widget fetches feeds directly (or reads a local JSON state file written by the optional sync helper).

**Why this fork?**

| | Upstream only ❌ | This fork ✅ |
| :--- | :--- | :--- |
| **Bar when the day is quiet** | Always shows the next title (even hours away) | Title only within `announceLeadHours` (default **3**); calendar glyph stays clickable |
| **Join via Omarchy web apps** | `browserCommand` or `xdg-open` | Prefer `google-app-open`, fall back to `xdg-open` |
| **`shell.json` list feeds** | QVariantList edge cases | Parses array-like QML lists cleanly |
| **Plugin id** | `tobiasz-p.next-event` | Same — no `shell.json` rewrite |

> **Note:** Calendar secrets (private ICS addresses, OAuth `client_secret*.json`, `calendar-events.json`) live under your home config/state dirs and are **gitignored**. Never paste real feed URLs into issues or README screenshots.

## ✨ Key Features

### 📅 Bar + agenda
- Next event with live countdown (`in 15 min`, `15 min left`, `Tmrw 14:00`, …).
- Left click → agenda panel · Right click → join next meeting · Middle click → refresh.
- Multi-day schedule, per-feed colors, all-day dots, calendar legend.

### 🎥 One-click Join
- Detects Google Meet, Zoom, Teams, Webex, GoToMeeting links in the event.
- Optional `browserCommand` (e.g. `google-app-open`) opens Meet in the Omarchy web app; Zoom/Teams still fall back to `xdg-open`.

### 🔐 Calendar on your machine
- **iCal:** private Google / Outlook / iCloud / Nextcloud feeds (URL treated as a credential — never shown in process argv).
- **OAuth:** guided `sync/setup` for Workspace accounts that block secret ICS URLs → local `~/.local/state/omarchy/calendar-events.json`.
- No third-party relay, no telemetry.

### 🧩 This fork
- `announceLeadHours` (settings stepper **Bar lead time**, `0` = always show title).
- All-day events never steal the bar title when a lead time is set.
- Outlined bar label for readability on busy wallpapers.

## 🛠 Installation (Omarchy)

```sh
omarchy plugin add https://github.com/austrasien/omarchy-next-event.git --enable
```

`--enable` places the widget in the bar (pick a section when prompted). Already on upstream?

```sh
cd ~/.config/omarchy/plugins/tobiasz-p.next-event
git remote set-url origin https://github.com/austrasien/omarchy-next-event.git
git remote add upstream https://github.com/tobiasz-p/next-event.git 2>/dev/null || true
git pull
omarchy restart shell
```

### Update / remove

```sh
omarchy plugin update tobiasz-p.next-event
omarchy plugin remove tobiasz-p.next-event
```

### Connect a calendar

**Private iCal (personal accounts):**

```sh
omarchy bar set tobiasz-p.next-event icsUrl '<your-private-ics-url>'
```

Multiple feeds: `Work|#1a73e8|<url>,Perso|#0b8043|<url>` — see upstream docs for JSON array form.

**Google Workspace OAuth** (when secret ICS is disabled):

```sh
~/.config/omarchy/plugins/tobiasz-p.next-event/sync/setup
```

Optional: `omarchy bar set tobiasz-p.next-event browserCommand google-app-open`  
Optional: `omarchy bar set tobiasz-p.next-event announceLeadHours 3`

### Requirements
- Omarchy Quattro shell (`omarchy-shell` / Quickshell)
- `curl` for ICS mode
- Optional OAuth path: `gum`, `gws`, systemd user timer (installed by `sync/setup`)

No sudo for the widget itself.

## ⚙️ Settings

| Key | Default | Meaning |
|---|---|---|
| `icsUrl` | `""` | iCal feed(s): URL, `label\|#color\|url` list, or JSON array |
| `eventsJsonPath` | `~/.local/state/omarchy/calendar-events.json` | OAuth / sync JSON state |
| `announceLeadHours` | `3` | Hours ahead to show the event **title** on the bar (`0` = always) |
| `refreshMinutes` | `5` | ICS refetch interval |
| `showDaysAhead` | `3` | Agenda lookahead (days) |
| `maxTitleLength` | `28` | Bar title truncation |
| `timeFormat` | `24` | `24` or `12` |
| `browserCommand` | `""` | Opener for Meet/calendar URLs (try `google-app-open`) |
| `calendarUrlBase` | Google Calendar | Base for “Open in Calendar” (e.g. `…/calendar/u/1`) |

More keys (`showOnlyWithVideoLink`, colors, panel keybindings, …) match [upstream](https://github.com/tobiasz-p/next-event).

## 🔒 Privacy

- Feeds and OAuth tokens stay local. Nothing is uploaded to austrasien or a middleman.
- Treat private ICS URLs like passwords; rotate them in Google Calendar if they leak.
- This repo’s `.gitignore` blocks `client_secret*.json`, `calendar-events.json`, `shell.json`, and `*.local.*`.

## ⚖️ License

Licensed under the **MIT License** (upstream [tobiasz-p/next-event](https://github.com/tobiasz-p/next-event)).

---
*Forked so the next Meet shows up when it matters — without parking the full title on the bar all day.*
