# Release notes draft — v1.0 (austrasien fork)

Use with:

```sh
gh release create v1.0 \
  --repo austrasien/omarchy-next-event \
  --title "v1.0 - Initial Release : Omarchy NextEvent 📅" \
  --notes-file RELEASE_NOTES.md
```

---

First public release of this **austrasien** fork of [tobiasz-p/next-event](https://github.com/tobiasz-p/next-event) — same next-meeting chip for the Omarchy bar, plus a quieter bar when nothing is soon and more reliable Meet opens via Omarchy web apps.

---

### ☕ Support the Project (Fuel the Development!)
If this saves you from missing the next Meet while the bar stays quiet, a tip is always appreciated.

[![Donate via PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/austraz)

---

## ✨ What’s included

### 📅 Bar + agenda (upstream)
* Next event countdown, multi-day agenda panel, per-feed colors.
* Left click → panel · Right click → Join · Middle click → refresh.
* Google Meet / Zoom / Teams / Webex / GoToMeeting link detection.

### 🔐 Calendars on your machine (upstream)
* Private iCal feeds and optional Workspace OAuth sync — no third-party relay.
* Feed URLs never appear in process argv (curl `-K -` over stdin).

### 🧩 This fork
* **`announceLeadHours`** (default 3): show the event title on the bar only when it is within the lead window; calendar glyph stays clickable. `0` = always show.
* All-day events never take the bar title when a lead time is set.
* **`google-app-open` + `xdg-open` fallback** for Join / Open in Calendar.
* QML/`shell.json` array-like feed list parsing; outlined bar label for busy wallpapers.

---

**📥 How to install?**
```sh
omarchy plugin add https://github.com/austrasien/omarchy-next-event.git --enable
```

Already on upstream?
```sh
cd ~/.config/omarchy/plugins/tobiasz-p.next-event
git remote set-url origin https://github.com/austrasien/omarchy-next-event.git
git pull
omarchy restart shell
```

Optional:
```sh
omarchy bar set tobiasz-p.next-event browserCommand google-app-open
omarchy bar set tobiasz-p.next-event announceLeadHours 3
```

💬 **Feedback:** Found a bug or have a suggestion? Open an [issue](https://github.com/austrasien/omarchy-next-event/issues).

Licensed under the **MIT License** (upstream [tobiasz-p/next-event](https://github.com/tobiasz-p/next-event)).
