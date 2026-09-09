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

### Connect Google Calendar

Pick **one** path. Most personal Gmail accounts use **Option A**. Many Google Workspace (work) orgs disable private iCal links — use **Option B**.

You can also open the widget panel (left-click the calendar glyph) → **Settings** and paste feeds there; the CLI below does the same thing.

#### Which option?

| Your account | Typical choice |
| :--- | :--- |
| Personal `@gmail.com` (or Google account with “Secret address in iCal format”) | **Option A — private iCal URL** |
| Work Google Workspace where Settings hide / disable the secret ICS link | **Option B — OAuth sync** |
| Both work + personal | Option A with **two** feeds, or A for personal + B for work |

Treat every private ICS URL like a **password**: anyone with it can read that calendar. Never commit it, never paste it into a GitHub issue or screenshot.

---

#### Option A — Private iCal URL (recommended for personal Google)

1. In a browser, open [Google Calendar](https://calendar.google.com) and sign in to the account you want.
2. Click the **gear** → **Settings**.
3. Left sidebar → under **Settings for my calendars**, click the calendar to expose (e.g. “Personal” or your primary calendar).
4. Scroll to **Integrate calendar**.
5. Copy **Secret address in iCal format**  
   It looks like:  
   `https://calendar.google.com/calendar/ical/YOU%40gmail.com/private-xxxxxxxx/basic.ics`  
   Use the **secret** address, not the public HTML link.
6. On Omarchy, set it on the widget (quotes matter if the URL has special characters):

```sh
omarchy bar set tobiasz-p.next-event icsUrl 'https://calendar.google.com/calendar/ical/…/private-…/basic.ics'
```

7. Refresh: middle-click the bar widget, or open the panel → refresh. Within a few seconds you should see upcoming events (or only the calendar glyph if nothing is within `announceLeadHours`).

**Several calendars** (work + personal, each with a label and optional color):

```sh
omarchy bar set tobiasz-p.next-event icsUrl 'Work|#1a73e8|https://…/private-…/basic.ics,Perso|#0b8043|https://…/private-…/basic.ics'
```

Format per feed: `Label|#RRGGBB|<ics-url>` (label and color optional). Comma separates feeds.

If a URL itself contains `,` or `|`, put a JSON array in `~/.config/omarchy/shell.json` on the widget entry instead:

```json
"icsUrl": [
  { "url": "https://…/private-…/basic.ics", "label": "Work", "color": "#1a73e8" },
  { "url": "https://…/private-…/basic.ics", "label": "Perso", "color": "#0b8043" }
]
```

Then `omarchy restart shell`.

**Several Google accounts in the browser** (so “Open in Calendar” hits the right profile):

```sh
omarchy bar set tobiasz-p.next-event calendarUrlBase 'https://calendar.google.com/calendar/u/1'
```

Use `/u/0` for the first signed-in account, `/u/1` for the second, etc.

---

#### Option B — Google Workspace OAuth (when secret ICS is blocked)

Use this when step 5 in Option A is missing or your admin disabled private iCal.

1. Run the guided setup (creates a **your** GCP OAuth client, logs in, installs a user systemd timer):

```sh
~/.config/omarchy/plugins/tobiasz-p.next-event/sync/setup
```

2. Follow the prompts: enable Calendar API, download Desktop OAuth client JSON, sign in, pick calendars to sync.
3. Events land in `~/.local/state/omarchy/calendar-events.json` (refreshed by the timer). The widget reads that file when no `icsUrl` is set (or when `sourceMode` is JSON).
4. Leave `icsUrl` empty for pure OAuth mode, or keep ICS feeds for other calendars alongside.

Credentials stay under your home profile (`client_secret*.json` for the sync helper) — never copy them into this git repo.

---

#### Recommended Omarchy extras (this fork)

Open Meet in the Omarchy Google web app when possible:

```sh
omarchy bar set tobiasz-p.next-event browserCommand google-app-open
```

Show the event **title** on the bar only when it starts within N hours (default already `3`; `0` = always):

```sh
omarchy bar set tobiasz-p.next-event announceLeadHours 3
```

How far ahead the agenda panel lists meetings:

```sh
omarchy bar set tobiasz-p.next-event showDaysAhead 7
```

---

### Requirements
- Omarchy Quattro shell (`omarchy-shell` / Quickshell)
- `curl` for Option A (ICS)
- Option B: `gum`, `gws`, systemd user timer (installed by `sync/setup`)

No sudo for the widget itself.

## ⚙️ Settings

| Key | Default | Meaning |
|---|---|---|
| `icsUrl` | `""` | Secret iCal URL(s) — see **Connect Google Calendar** |
| `eventsJsonPath` | `~/.local/state/omarchy/calendar-events.json` | OAuth / sync JSON state (Option B) |
| `announceLeadHours` | `3` | Hours ahead to show the event **title** on the bar (`0` = always) |
| `refreshMinutes` | `5` | ICS refetch interval |
| `showDaysAhead` | `3` | Agenda lookahead (days) |
| `maxTitleLength` | `28` | Bar title truncation |
| `timeFormat` | `24` | `24` or `12` |
| `browserCommand` | `""` | Opener for Meet/calendar URLs (`google-app-open` recommended on Omarchy) |
| `calendarUrlBase` | `https://calendar.google.com/calendar` | “Open in Calendar” base; add `/u/1` etc. for multi-account |

More keys (`showOnlyWithVideoLink`, colors, panel keybindings, …) match [upstream](https://github.com/tobiasz-p/next-event).

## 🔒 Privacy

- Feeds and OAuth tokens stay local. Nothing is uploaded to austrasien or a middleman.
- Treat private ICS URLs like passwords; rotate them in Google Calendar if they leak.
- This repo’s `.gitignore` blocks `client_secret*.json`, `calendar-events.json`, `shell.json`, and `*.local.*`.

## ⚖️ License

Licensed under the **MIT License** (upstream [tobiasz-p/next-event](https://github.com/tobiasz-p/next-event)).

---
*Forked so the next Meet shows up when it matters — without parking the full title on the bar all day.*
