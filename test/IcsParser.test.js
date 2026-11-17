"use strict"

const { describe, it } = require("node:test")
const assert = require("node:assert/strict")
const { IcsParser, icsFeedOwner } = require("../Model.js")

describe("IcsParser", () => {
  describe("unfoldIcs()", () => {
    it("unfolds lines starting with space or tab into single logical lines", () => {
      const raw = "URL:https://meet.google.com/\r\n abc-defg-hij\r\nLOCATION:Room A"
      const lines = IcsParser.unfoldIcs(raw)
      assert.deepStrictEqual(lines, ["URL:https://meet.google.com/abc-defg-hij", "LOCATION:Room A"])
    })
  })

  describe("unescapeIcs()", () => {
    it("decodes escaped commas, semicolons, backslashes, and newlines", () => {
      assert.strictEqual(
        IcsParser.unescapeIcs("Line1\\nLine2\\, with comma\\; and semi\\\\"),
        "Line1\nLine2, with comma; and semi\\"
      )
    })
  })

  describe("caretDecode()", () => {
    it("decodes caret-encoded characters into raw values", () => {
      assert.strictEqual(
        IcsParser.caretDecode("test^nnewline^'quote^^caret"),
        'test\nnewline"quote^caret'
      )
    })
  })

  describe("splitProperty()", () => {
    it("splits property name, parameters and value accurately", () => {
      const prop = IcsParser.splitProperty('DTSTART;TZID="Europe/Warsaw":20260828T100000')
      assert.strictEqual(prop.name, "DTSTART")
      assert.strictEqual(prop.params.TZID, "Europe/Warsaw")
      assert.strictEqual(prop.value, "20260828T100000")
    })
  })

  describe("parse()", () => {
    const NOW = new Date("2026-08-17T09:00:00Z")

    function feed(lines) {
      return [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "BEGIN:VEVENT",
        "UID:test-event-1",
        "DTSTART:20260817T140000Z",
        "DTEND:20260817T150000Z",
        "SUMMARY:Test Event",
        ...lines,
        "END:VEVENT",
        "END:VCALENDAR"
      ].join("\r\n")
    }

    it("finds Meet link in DESCRIPTION", () => {
      const ics = feed(["DESCRIPTION:Join at https://meet.google.com/abc-defg-hij"])
      const events = IcsParser.parse(ics, { now: NOW })
      assert.strictEqual(events[0].meetUrl, "https://meet.google.com/abc-defg-hij")
    })

    it("finds Meet link in X-GOOGLE-CONFERENCE", () => {
      const ics = feed(["X-GOOGLE-CONFERENCE:https://meet.google.com/xyz-1234-abc"])
      const events = IcsParser.parse(ics, { now: NOW })
      assert.strictEqual(events[0].meetUrl, "https://meet.google.com/xyz-1234-abc")
    })

    it("finds Teams link in X-MICROSOFT-SKYPETEAMSMEETINGURL", () => {
      const ics = feed([
        "X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz"
      ])
      const events = IcsParser.parse(ics, { now: NOW })
      assert.strictEqual(
        events[0].meetUrl,
        "https://teams.microsoft.com/l/meetup-join/19%3ameeting_xyz"
      )
    })

    it("reads Zoom link from CONFERENCE property (RFC 7986)", () => {
      const ics = feed(["CONFERENCE;VALUE=URI:https://zoom.us/j/123456789"])
      const events = IcsParser.parse(ics, { now: NOW })
      assert.strictEqual(events[0].meetUrl, "https://zoom.us/j/123456789")
    })

    it("prioritizes Google Meet when event carries multiple provider links", () => {
      const ics = feed([
        "LOCATION:https://zoom.us/j/123456789",
        "DESCRIPTION:Backup Meet link: https://meet.google.com/abc-defg-hij"
      ])
      const events = IcsParser.parse(ics, { now: NOW })
      assert.strictEqual(events[0].meetUrl, "https://meet.google.com/abc-defg-hij")
    })

    it("expands recurring VEVENT and applies EXDATE exclusions", () => {
      const ics = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "BEGIN:VEVENT",
        "UID:daily-standup",
        "DTSTART:20260817T090000Z",
        "DTEND:20260817T093000Z",
        "RRULE:FREQ=DAILY;COUNT=5",
        "EXDATE:20260819T090000Z",
        "SUMMARY:Daily Standup",
        "END:VEVENT",
        "END:VCALENDAR"
      ].join("\r\n")

      const events = IcsParser.parse(ics, { now: NOW, lookaheadDays: 7 })
      assert.strictEqual(events.length, 4)
    })

    it("parses COLOR property and supports options.calendarColor and options.feedLabel", () => {
      const icsWithColor = feed(["COLOR:#ea4335"])
      const events1 = IcsParser.parse(icsWithColor, { now: NOW })
      assert.strictEqual(events1[0].calendarColor, "#ea4335")

      const icsPlain = feed([])
      const events2 = IcsParser.parse(icsPlain, {
        now: NOW,
        calendarColor: "#4285f4",
        feedLabel: "Work"
      })
      assert.strictEqual(events2[0].calendarColor, "#4285f4")
      assert.strictEqual(events2[0].feedLabel, "Work")
    })
  })

  describe("declined invitations", () => {
    const NOW = new Date("2026-08-17T09:00:00Z")
    const OWNER = "ATTENDEE;CUTYPE=INDIVIDUAL;PARTSTAT=%s;CN=me@example.com:mailto:me@example.com"
    const OTHER = "ATTENDEE;PARTSTAT=%s;CN=you@example.com:mailto:you@example.com"

    function feed(header, attendees, extra) {
      return [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        ...header,
        "BEGIN:VEVENT",
        "UID:invite-1",
        "DTSTART:20260817T140000Z",
        "DTEND:20260817T150000Z",
        "SUMMARY:Invite",
        ...attendees,
        "END:VEVENT",
        ...(extra || []),
        "END:VCALENDAR"
      ].join("\r\n")
    }

    it("drops an event the owner named by X-WR-CALNAME declined", () => {
      const ics = feed(["X-WR-CALNAME:Me@Example.com"], [OWNER.replace("%s", "DECLINED")])
      assert.strictEqual(IcsParser.parse(ics, { now: NOW }).length, 0)
    })

    it("drops an event the owner given in options declined", () => {
      const ics = feed(["X-WR-CALNAME:Perso"], [OWNER.replace("%s", "DECLINED")])
      assert.strictEqual(IcsParser.parse(ics, { now: NOW }).length, 1)
      const events = IcsParser.parse(ics, { now: NOW, ownerEmails: ["me@example.com"] })
      assert.strictEqual(events.length, 0)
    })

    it("keeps an event the owner accepted while another attendee declined", () => {
      const ics = feed(
        ["X-WR-CALNAME:me@example.com"],
        [OWNER.replace("%s", "ACCEPTED"), OTHER.replace("%s", "DECLINED")]
      )
      assert.strictEqual(IcsParser.parse(ics, { now: NOW }).length, 1)
    })

    it("drops only the occurrence the owner declined in a series", () => {
      const ics = [
        "BEGIN:VCALENDAR",
        "X-WR-CALNAME:me@example.com",
        "BEGIN:VEVENT",
        "UID:series-1",
        "DTSTART:20260817T140000Z",
        "DTEND:20260817T150000Z",
        "RRULE:FREQ=DAILY;COUNT=3",
        "SUMMARY:Daily",
        OWNER.replace("%s", "ACCEPTED"),
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:series-1",
        "RECURRENCE-ID:20260818T140000Z",
        "DTSTART:20260818T140000Z",
        "DTEND:20260818T150000Z",
        "SUMMARY:Daily",
        OWNER.replace("%s", "DECLINED"),
        "END:VEVENT",
        "END:VCALENDAR"
      ].join("\r\n")
      const starts = IcsParser.parse(ics, { now: NOW, lookaheadDays: 5 }).map((e) =>
        e.start.toISOString()
      )
      assert.deepStrictEqual(starts, ["2026-08-17T14:00:00.000Z", "2026-08-19T14:00:00.000Z"])
    })
  })

  describe("icsFeedOwner()", () => {
    it("reads the owner address from a Google iCal URL", () => {
      assert.strictEqual(
        icsFeedOwner(
          "https://calendar.google.com/calendar/ical/Me%40Example.com/private-abc/basic.ics"
        ),
        "me@example.com"
      )
    })

    it("returns an empty string for other URLs", () => {
      assert.strictEqual(icsFeedOwner("https://example.com/cal.ics"), "")
      assert.strictEqual(icsFeedOwner(""), "")
    })
  })
})
