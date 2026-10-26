import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons

// NextEvent as a map of the minimap (austraz.minimap): installed by linking
// this folder as the minimap's maps/nextevent. It reads the upcoming events
// the bar widget publishes ($XDG_RUNTIME_DIR/next-event-upcoming.json), so
// the feeds are fetched once and their URLs stay in the widget.
//
// The face shows the event in focus: one under way (the latest started),
// else the next one. Within the hour before it, a ring fills as the start
// comes near and pulses in the last minutes; under way, the ring is its
// progress. Five minutes before, the map comes up as a notification; at
// the start, as a persistent one until clicked. Click joins the call, or
// opens the event in the calendar.
Item {
  id: view
  required property var minimap

  readonly property string path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/next-event-upcoming.json"
  property var events: []
  property string browserCommand: ""
  property bool use12Hour: false
  property real nowMs: Date.now()

  readonly property int soonMs: 60 * 60000      // the ring starts filling
  readonly property int reminderMs: 5 * 60000   // the heads-up notification

  FileView {
    id: file
    path: view.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: view.take(text())
  }
  // The widget may write the file after the shell starts, and then no
  // watch is set: look again now and then.
  Timer { interval: 15000; running: true; repeat: true; onTriggered: file.reload() }
  Timer { interval: 1000; running: true; repeat: true; onTriggered: view.nowMs = Date.now() }

  function take(raw) {
    try {
      var d = JSON.parse(String(raw || "{}"))
      events = Array.isArray(d.events) ? d.events : []
      browserCommand = String(d.browserCommand || "")
      use12Hour = d.use12Hour === true
    } catch (e) {}
  }

  // The event under way that started last (a short slot inside a long block
  // wins), else the next timed one, else the next all-day one.
  readonly property var current: {
    var now = nowMs
    var live = null, next = null, allDay = null
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      if (ev.end <= now) continue
      if (ev.allDay) { if (!allDay) allDay = ev; continue }
      if (ev.start <= now) { if (!live || ev.start > live.start) live = ev }
      else if (!next || ev.start < next.start) next = ev
    }
    return live || next || allDay
  }
  // What comes after the current one, for the line at the bottom.
  readonly property var after: {
    if (!current) return null
    var best = null
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      if (ev === current || ev.allDay || ev.start < current.start) continue
      if (ev.start === current.start && ev.title === current.title) continue
      if (!best || ev.start < best.start) best = ev
    }
    return best
  }

  readonly property bool empty: current === null
  readonly property bool live: !!current && !current.allDay && nowMs >= current.start
  readonly property real untilMs: current ? current.start - nowMs : 0
  readonly property bool soon: !!current && !current.allDay && !live && untilMs <= soonMs
  readonly property bool imminent: soon && untilMs <= reminderMs
  readonly property color tint: current && /^#[0-9a-fA-F]{6}$/.test(current.color) ? current.color : Color.accent
  readonly property real ring: !current || current.allDay ? 0
    : live ? (nowMs - current.start) / Math.max(1, current.end - current.start)
    : soon ? 1 - untilMs / soonMs : 0

  // ---- reminders
  readonly property string focusKey: current ? current.start + "|" + current.title : ""
  property var told: ({})       // "<key>|soon" / "<key>|start" already shown
  property bool waiting: false  // the persistent start notification is up

  function tell(kind) {
    if (told[focusKey + "|" + kind]) return false
    var t = Object.assign({}, told)
    t[focusKey + "|" + kind] = true
    told = t
    return true
  }

  onNowMsChanged: {
    if (!current || current.allDay) return
    if (imminent && tell("soon")) minimap.notify(view, 10000)
    if (live && nowMs - current.start < reminderMs && tell("start")) {
      waiting = true
      minimap.notify(view, 0, true)
    }
    // Nobody clicked: the start notice goes after five minutes.
    if (waiting && (!live || nowMs - current.start >= reminderMs)) settle()
  }

  function settle() {
    if (!waiting) return
    waiting = false
    minimap.dismiss(view)
  }

  // ---- formatting
  function pad(n) { return (n < 10 ? "0" : "") + n }
  function clock(ms) {
    var d = new Date(ms)
    var h = d.getHours(), m = d.getMinutes()
    if (!use12Hour) return pad(h) + ":" + pad(m)
    return ((h + 11) % 12 + 1) + (m ? ":" + pad(m) : "") + (h < 12 ? " am" : " pm")
  }
  function dayStart(ms) { var d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime() }
  function status() {
    if (!current) return ""
    if (live) {
      var left = Math.ceil((current.end - nowMs) / 60000)
      return left > 90 ? "now" : "now · " + left + " min left"
    }
    var days = Math.round((dayStart(current.start) - dayStart(nowMs)) / 86400000)
    if (current.allDay) return days <= 0 ? "today" : days === 1 ? "tomorrow" : Qt.formatDate(new Date(current.start), "ddd d")
    var mins = Math.ceil(untilMs / 60000)
    if (mins <= 60) return "in " + mins + " min"
    if (days === 0) return "in " + Math.floor(mins / 60) + " h " + pad(mins % 60)
    if (days === 1) return "tomorrow " + clock(current.start)
    return Qt.formatDate(new Date(current.start), "ddd") + " " + clock(current.start)
  }
  function range(ev) {
    if (!ev) return ""
    if (ev.allDay) return "all day"
    return clock(ev.start) + " – " + clock(ev.end)
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
  function open() {
    if (!current) return
    var url = current.meetUrl || current.calendarUrl
    if (!url) return
    var q = quote(url)
    var cmd = browserCommand !== "" ? browserCommand + " " + q + " || xdg-open " + q : "xdg-open " + q
    Quickshell.execDetached(["sh", "-c", cmd])
  }

  // ---- face
  readonly property real w: width
  property real pulse: 1
  SequentialAnimation on pulse {
    running: view.imminent || view.waiting
    loops: Animation.Infinite
    NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
    onRunningChanged: if (!running) view.pulse = 1
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.darker(Color.background, 1.15)
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: Qt.alpha(view.tint, hover.hovered && view.current ? 0.2 : view.live ? 0.14 : 0.07)
    Behavior on color { ColorAnimation { duration: 150 } }
  }

  Shape {
    anchors.fill: parent
    visible: !!view.current && !view.current.allDay
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeColor: Qt.alpha(Color.foreground, 0.08)
      strokeWidth: 6
      fillColor: "transparent"
      PathAngleArc { centerX: view.w / 2; centerY: view.w / 2; radiusX: view.w / 2 - 4; radiusY: radiusX; startAngle: 0; sweepAngle: 360 }
    }
    ShapePath {
      strokeColor: Qt.alpha(view.tint, view.pulse)
      strokeWidth: 6
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: view.w / 2; centerY: view.w / 2
        radiusX: view.w / 2 - 4; radiusY: radiusX
        startAngle: -90
        sweepAngle: 360 * Math.max(0, Math.min(1, view.ring))
      }
    }
  }

  Column {
    anchors.centerIn: parent
    width: view.w * 0.7
    spacing: view.w * 0.012
    visible: !!view.current

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: String.fromCodePoint(view.current && view.current.meetUrl ? 0xF0567 : 0xF00ED)
      color: view.tint
      opacity: view.imminent ? view.pulse : 1
      font.family: Style.fontFamily
      font.pixelSize: view.w * 0.12
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: view.status()
      color: view.live || view.soon ? view.tint : Qt.alpha(Color.foreground, 0.7)
      font.family: Style.fontFamily
      font.pixelSize: Math.round(view.w * 0.075)
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: view.current ? view.current.title : ""
      color: Color.foreground
      font.family: Style.fontFamily
      font.pixelSize: Math.round(view.w * 0.085)
      font.bold: true
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: view.range(view.current)
      color: Qt.alpha(Color.foreground, 0.6)
      font.family: Style.fontFamily
      font.pixelSize: Math.round(view.w * 0.06)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: !!view.after
      text: view.after ? "then " + view.clock(view.after.start) + " · " + view.after.title : ""
      color: Qt.alpha(Color.foreground, 0.45)
      font.family: Style.fontFamily
      font.pixelSize: Math.round(view.w * 0.05)
      elide: Text.ElideRight
    }
  }

  // "Join" under the pointer when there is a call.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: view.w * 0.84
    visible: hover.hovered && !!view.current
    text: view.current && view.current.meetUrl ? "Join" : "Open"
    color: view.tint
    font.family: Style.fontFamily
    font.pixelSize: Math.round(view.w * 0.055)
    font.bold: true
  }

  HoverHandler { id: hover }
  MouseArea {
    anchors.fill: parent
    enabled: !!view.current
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: { view.open(); view.settle() }
  }
}
