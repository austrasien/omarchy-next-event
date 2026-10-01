import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// NextEvent — the next event, right in the bar.
//
// Left click opens the meeting list; right click joins the next meeting;
// middle click refetches the calendar. The event title only appears on the
// bar within announceLeadHours (default 3); otherwise a calendar glyph
// stays so the agenda panel is always one click away.
BarWidget {
  id: root
  moduleName: "tobiasz-p.next-event"

  // Outline only against a solid bar. `bar` is a QtObject (not var) so this
  // binding follows the host flipping transparent after the color sample.
  readonly property bool barTransparent: bar ? bar.transparent : false

  // ---- settings (shell.json layout entry, `omarchy bar set`)
  // icsUrl is a feed list: "url", "url1,url2", "label|url" per feed
  // (comma-separated), or a JSON array of strings / { url, label } objects.
  readonly property var icsFeeds: Model.splitIcsFeeds(settings ? settings.icsUrl : "")
  readonly property bool hasCalendarSource: {
    var url = settings ? settings.icsUrl : null
    if (url == null || url === "") return false
    if (typeof url === "string") return url.trim().length > 0 && url.trim() !== "[object Object]"
    if (typeof url === "object" && typeof url.length === "number") return url.length > 0
    if (typeof url === "object") return true
    return icsFeeds.length > 0
  }
  readonly property string eventsJsonPath: String(setting("eventsJsonPath", (Quickshell.env("HOME") || "") + "/.local/state/omarchy/calendar-events.json") || "").trim()
  // Host injects the layout entry (always has `id`). Until then settings is
  // `{}` and icsFeeds looks empty — do not infer JSON/OAuth sync from that.
  readonly property bool settingsBound: !!(settings && (settings.id || settings.icsUrl != null || settings.sourceMode))
  readonly property string sourceMode: {
    var explicit = settings && settings.sourceMode != null ? String(settings.sourceMode).trim() : ""
    if (explicit) return explicit
    if (icsFeeds.length > 0) return Model.SOURCE_MODE_ICS
    if (!settingsBound) return Model.SOURCE_MODE_ICS
    return Model.SOURCE_MODE_JSON
  }
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", Model.DEFAULT_REFRESH_MINUTES), 10) || Model.DEFAULT_REFRESH_MINUTES)
  readonly property int showDaysAhead: Math.max(1, parseInt(setting("showDaysAhead", Model.DEFAULT_LOOKAHEAD_DAYS), 10) || Model.DEFAULT_LOOKAHEAD_DAYS)
  readonly property int announceLeadHours: Model.normalizeAnnounceLeadHours(setting("announceLeadHours", Model.DEFAULT_ANNOUNCE_LEAD_HOURS))
  readonly property int maxTitleLength: Math.max(Model.MIN_MAX_TITLE_LENGTH, parseInt(setting("maxTitleLength", Model.DEFAULT_MAX_TITLE_LENGTH), 10) || Model.DEFAULT_MAX_TITLE_LENGTH)
  readonly property string timeFormat: String(setting("timeFormat", Model.DEFAULT_TIME_FORMAT) || Model.DEFAULT_TIME_FORMAT).trim()
  readonly property bool use12Hour: Model.is12Hour(timeFormat)
  readonly property int maxFeedSizeMiB: Math.max(1, parseInt(setting("maxFeedSizeMiB", Model.DEFAULT_MAX_FEED_SIZE_MIB), 10) || Model.DEFAULT_MAX_FEED_SIZE_MIB)
  readonly property bool showOnlyWithVideoLink: Model.toBoolean(setting("showOnlyWithVideoLink", false), false)
  readonly property bool showCalendarLabel: Model.toBoolean(setting("showCalendarLabel", true), true)
  readonly property bool useCalendarColors: Model.toBoolean(setting("useCalendarColors", true), true)
  readonly property bool colorOnBar: Model.toBoolean(setting("colorOnBar", false), false)
  readonly property string browserCommand: String(setting("browserCommand", "") || "").trim()
  // Base for "Open in Calendar". Defaults to the signed-in account; set to
  // e.g. "https://calendar.google.com/calendar/u/2" to open a specific
  // account (matches the u/N in your browser's calendar URL).
  readonly property string calendarUrlBase: String(setting("calendarUrlBase", Model.DEFAULT_CALENDAR_URL_BASE) || "").trim()
  // Single-key panel shortcuts (text keys while the panel is focused).
  // Arrows and j/k/h/l are reserved by the shell's key catcher for
  // navigation, so those letters would be dead config here.
  readonly property string keyRefresh: Model.normalizeKey(setting("keyRefresh", Model.DEFAULT_KEY_REFRESH), Model.DEFAULT_KEY_REFRESH)
  readonly property string keySettings: Model.normalizeKey(setting("keySettings", Model.DEFAULT_KEY_SETTINGS), Model.DEFAULT_KEY_SETTINGS)
  readonly property string keyJoin: Model.normalizeKey(setting("keyJoin", Model.DEFAULT_KEY_JOIN), Model.DEFAULT_KEY_JOIN)
  readonly property string keyCalendar: Model.normalizeKey(setting("keyCalendar", Model.DEFAULT_KEY_CALENDAR), Model.DEFAULT_KEY_CALENDAR)

  // ---- internal limits
  readonly property int maxRawEvents: Model.DEFAULT_MAX_EVENTS
  readonly property int maxMeetingRows: Model.DEFAULT_MAX_MEETING_ROWS
  readonly property int maxScheduleRows: Model.DEFAULT_MAX_ROWS

  // ---- state
  property bool jsonLoaded: false
  readonly property bool configured: hasCalendarSource || icsFeeds.length > 0 || jsonLoaded || (rawEvents && rawEvents.length > 0)
  onSourceModeChanged: {
    jsonLoaded = false
    fetchCalendar()
  }
  property var rawEvents: []
  property var meetings: []
  property var upcomingToday: []
  property var scheduleGroups: []
  property var calendarLegend: []
  property var nextMeeting: null
  property string pillEventKey: ""
  property double pillShownAtMs: 0
  property date lastUpdated: new Date(0)
  property bool lastFetchFailed: false
  // Number of feeds that failed on the last fetch while *some* succeeded;
  // 0 means all known feeds responded. Used for a partial-offline status.
  property int offlineFeedCount: 0
  readonly property bool fetching: fetchProc.running || syncProc.running
  property date now: new Date()

  // Internal fetch-loop state (populated by fetchCalendar).
  property var pendingFeeds: []
  property var feedChunks: []
  property var failedFeeds: []
  property string currentFeedUrl: ""
  property string currentFeedLabel: ""
  property string currentFeedColor: ""
  property string feedOutput: ""

  readonly property string label: Model.barLabel(root.configured, root.nextMeeting, root.now, root.maxTitleLength, root.use12Hour, root.announceLeadHours)
  readonly property bool inMeeting: nextMeeting
    && !nextMeeting.allDay
    && nextMeeting.start && nextMeeting.end
    && root.now.getTime() >= nextMeeting.start.getTime()
    && root.now.getTime() < nextMeeting.end.getTime()
  // Title is on the bar only inside announceLeadHours (or while live).
  readonly property bool announcingSoon: root.label !== "" && !root.inMeeting
  readonly property color sampledForeground: bar ? bar.barForeground : Color.foreground
  // Transparent bar: bright orange for soon, dark red for live. These are
  // pill washes (text stays barForeground). The old burnt `#9a3412` was a
  // text color — at low alpha on a sky wallpaper it reads as grey.
  readonly property color soonColor: root.barTransparent ? "#ea580c" : Color.accent
  readonly property color liveColor: root.barTransparent ? "#b91c1c" : (bar ? bar.urgent : Color.urgent)
  readonly property color barLabelColor: root.sampledForeground
  readonly property int pillThickness: Math.max(16, (bar ? bar.barSize : Style.bar.sizeHorizontal) - Style.space(6))
  readonly property int pillRadius: Style.cornerRadius > 0 ? Math.round(root.pillThickness * 0.32) : 0
  readonly property real eventProgress: Model.eventProgress(root.nextMeeting, root.now)
  readonly property real pillSoonProgress: Model.pillProgress(root.nextMeeting, root.now, root.pillShownAtMs)
  readonly property bool pillVisible: root.inMeeting || root.announcingSoon
  // Track and fill share one RGB. A 0.28 orange wash over this sky wallpaper
  // composites to grey (same trap as `#9a3412`). The unfilled side is the
  // fill colour at lower alpha — high enough to stay red, not grey.
  readonly property color pillHue: {
    if (root.inMeeting) return root.liveColor
    var t = Math.max(0, Math.min(1, root.pillSoonProgress))
    var s = root.soonColor
    var l = root.liveColor
    return Qt.rgba(s.r + (l.r - s.r) * t, s.g + (l.g - s.g) * t, s.b + (l.b - s.b) * t, 1)
  }
  readonly property color pillTrackColor: {
    if (!root.pillVisible) return "transparent"
    return Util.alpha(root.pillHue, root.barTransparent ? 0.64 : 0.12)
  }
  readonly property color pillFillColor: {
    if (!root.pillVisible) return "transparent"
    return Util.alpha(root.pillHue, root.barTransparent ? 0.88 : 0.28)
  }

  // ---- actions
  function openMeetingUrl(url) {
    if (!url) return
    var quote = Util.shellQuote(url)
    // Prefer the configured opener (google-app-open → Omarchy web app).
    // Fall back to xdg-open so Zoom/Teams still work when no web app matches.
    if (browserCommand !== "") bar.run(browserCommand + " " + quote + " || xdg-open " + quote)
    else bar.run("xdg-open " + quote)
  }

  function joinMeeting(event) {
    if (event && event.meetUrl) openMeetingUrl(event.meetUrl)
  }

  function openCalendar(event) {
    var url = Model.eventCalendarUrl(event, root.calendarUrlBase)
    if (url) openMeetingUrl(url)
  }

  function openEvent(event) {
    if (!event) return
    if (event.meetUrl) openMeetingUrl(event.meetUrl)
    else openCalendar(event)
  }

  // The feed URL is a credential (e.g. Google's "secret address in iCal
  // format"), so it must never appear in a process argument list where every
  // local user can read it. curl gets each URL over stdin as a `-K -` config
  // line. Feeds are fetched one at a time so a single offline feed doesn't
  // take down the whole widget: the rest still render, and the failed count is
  // surfaced as a partial-offline status.
  function fetchCalendar() {
    if (root.icsFeeds.length > 0) {
      if (!root.configured || fetchProc.running) return
      root.pendingFeeds = root.icsFeeds.slice()
      root.feedChunks = []
      root.failedFeeds = []
      root.offlineFeedCount = 0
      if (root.pendingFeeds.length === 0) {
        root.lastFetchFailed = false
        root.meetingDataChanged()
        return
      }
      root.startNextFetch()
    } else if (root.sourceMode === Model.SOURCE_MODE_JSON && root.settingsBound) {
      if (!syncProc.running) syncProc.running = true
    }
  }

  function startNextFetch() {
    if (root.pendingFeeds.length === 0) {
      root.finishFetch()
      return
    }
    var feed = root.pendingFeeds[0]
    root.currentFeedUrl = String(feed.url || "").trim()
    root.currentFeedLabel = feed.label ? String(feed.label).trim() : ""
    root.currentFeedColor = feed.color ? String(feed.color).trim() : ""
    root.feedOutput = ""
    if (!root.currentFeedUrl) {
      root.pendingFeeds.shift()
      root.startNextFetch()
      return
    }
    fetchProc.stdinEnabled = true
    fetchProc.command = ["curl", "-fsSL", "-A", "Mozilla/5.0", "--max-time", String(Model.FETCH_TIMEOUT_SECONDS), "--max-filesize", String(root.maxFeedSizeMiB * Model.BYTES_PER_MIB), "-K", "-"]
    fetchProc.running = true
  }

  // Accumulate one parsed feed's events (tagged with its label) and continue.
  function onFeedStreamFinished(text) {
    root.feedOutput = String(text || "")
  }

  function onFeedExited(exitCode) {
    var raw = root.feedOutput.trim()
    if (exitCode === 0 && raw) {
      var events = Model.parseIcs(raw, {
        lookaheadDays: root.showDaysAhead + 1,
        maxEvents: 80,
        now: root.now,
        calendarColor: root.currentFeedColor,
        feedLabel: root.currentFeedLabel
      })
      for (var i = 0; i < events.length; i++) {
        if (root.currentFeedLabel) events[i].feedLabel = root.currentFeedLabel
        if (root.currentFeedColor) events[i].calendarColor = root.currentFeedColor
      }
      root.feedChunks.push(events)
    } else {
      root.failedFeeds.push(root.currentFeedUrl)
    }
    root.pendingFeeds.shift()
    root.feedOutput = ""
    root.startNextFetch()
  }

  function applyScheduleState(events, lastUpdatedDate) {
    root.rawEvents = events || []
    var state = Model.computeScheduleState(root.rawEvents, root.now, {
      lookaheadDays: root.showDaysAhead,
      showOnlyWithVideoLink: root.showOnlyWithVideoLink,
      maxMeetingRows: root.maxMeetingRows,
      maxScheduleRows: root.maxScheduleRows,
      feeds: root.icsFeeds
    })
    root.meetings = state.meetings
    root.upcomingToday = state.upcomingToday
    root.scheduleGroups = state.scheduleGroups
    root.nextMeeting = state.nextMeeting
    root.calendarLegend = state.calendarLegend || []
    if (lastUpdatedDate) root.lastUpdated = lastUpdatedDate
    root.syncPillOrigin()
    root.meetingDataChanged()
  }

  function pillKey(ev) {
    if (!ev) return ""
    var uid = ev.uid ? String(ev.uid) : (ev.title ? String(ev.title) : "")
    var start = ev.start && ev.start.getTime ? ev.start.getTime() : 0
    return uid + "|" + start
  }

  function syncPillOrigin() {
    if (!root.nextMeeting) {
      root.pillEventKey = ""
      root.pillShownAtMs = 0
      return
    }
    if (!root.pillVisible) return
    var key = root.pillKey(root.nextMeeting)
    if (key !== root.pillEventKey) {
      root.pillEventKey = key
      root.pillShownAtMs = root.now.getTime()
    }
  }

  function finishFetch() {
    root.offlineFeedCount = root.failedFeeds.length

    var allEvents = []
    for (var chunkIndex = 0; chunkIndex < root.feedChunks.length; chunkIndex++) {
      allEvents = allEvents.concat(root.feedChunks[chunkIndex])
    }
    var events = Model.dedupeEvents(allEvents)

    if (events.length === 0 && root.offlineFeedCount > 0 && root.feedChunks.length === 0) {
      // Every feed failed: no data at all.
      root.rawEvents = []
      root.lastFetchFailed = true
      root.meetingDataChanged()
      return
    }

    root.lastFetchFailed = false
    root.applyScheduleState(events, new Date())
  }

  function onJsonData(raw) {
    var text = String(raw || "").trim()
    if (!text) return
    var parsed = Model.parseJsonState(text, {
      lookaheadDays: root.showDaysAhead + 1,
      now: root.now
    })
    root.jsonLoaded = true
    root.lastFetchFailed = false
    root.applyScheduleState(parsed.events, parsed.syncedAt ? new Date(parsed.syncedAt) : new Date())
  }

  function refresh() {
    fetchCalendar()
  }

  function recalc() {
    root.applyScheduleState(root.rawEvents, null)
  }

  signal meetingDataChanged()

  // ---- panel plumbing (shape contract for shell.summon/hide/toggle)
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    root.recalc()
    Qt.callLater(root.fetchCalendar)
  }
  onMeetingDataChanged: {
    if (panelLoader.item) panelLoader.item.reload()
  }
  onPillVisibleChanged: root.syncPillOrigin()
  onNextMeetingChanged: root.syncPillOrigin()

  // Refetch the calendar on a schedule.
  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.fetchCalendar()
  }

  // Keep the countdown and pill fill fresh while announced or live.
  Timer {
    id: nowTimer
    interval: root.pillVisible ? 1000 : 30 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.now = new Date()
      root.recalc()
    }
    onIntervalChanged: restart()
  }

  FileView {
    id: jsonFileView
    path: root.sourceMode === "json" ? root.eventsJsonPath : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.onJsonData(text())
    onLoadFailed: function(error) {
      console.warn("NextEvent: eventsJson load failed: " + error + " path=" + root.eventsJsonPath)
    }
    onFileChanged: reload()
  }

  Process {
    id: syncProc
    command: [Qt.resolvedUrl("sync/next-event-sync").toString().replace("file://", "")]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("next-event-sync exited with code", exitCode)
      } else {
        jsonFileView.reload()
      }
    }
  }

  Component.onCompleted: {
    Qt.callLater(root.fetchCalendar)
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onFeedStreamFinished(text)
    }
    onStarted: {
      fetchProc.write("url = \"" + root.currentFeedUrl.replace(/([\\"])/g, "\\$1") + "\"\n")
      fetchProc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.onFeedExited(exitCode)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Rectangle {
    id: pill
    z: 0
    anchors.centerIn: button
    width: root.vertical ? root.pillThickness : button.width
    height: root.vertical ? button.height : root.pillThickness
    radius: root.pillRadius
    color: root.pillTrackColor
    visible: root.pillVisible
    antialiasing: true
    Behavior on color { ColorAnimation { duration: 180 } }

    // Soon: fill right-to-left (bottom-to-top when the bar is vertical).
    Item {
      id: soonFillClip
      width: root.vertical ? parent.width : parent.width * Math.max(0, Math.min(1, root.pillSoonProgress))
      height: root.vertical ? parent.height * Math.max(0, Math.min(1, root.pillSoonProgress)) : parent.height
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      visible: root.announcingSoon && root.pillSoonProgress > 0

      Behavior on width { enabled: !root.vertical && root.announcingSoon; NumberAnimation { duration: 400; easing.type: Easing.Linear } }
      Behavior on height { enabled: root.vertical && root.announcingSoon; NumberAnimation { duration: 400; easing.type: Easing.Linear } }

      Rectangle {
        width: pill.width
        height: pill.height
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        radius: pill.radius
        color: root.pillFillColor
        antialiasing: true
      }
    }

    // Live: fill left-to-right (top-to-bottom when the bar is vertical).
    Item {
      id: liveFillClip
      width: root.vertical ? parent.width : parent.width * Math.max(0, Math.min(1, root.eventProgress))
      height: root.vertical ? parent.height * Math.max(0, Math.min(1, root.eventProgress)) : parent.height
      anchors.left: parent.left
      anchors.top: parent.top
      clip: true
      visible: root.inMeeting && root.eventProgress > 0

      Behavior on width { enabled: !root.vertical && root.inMeeting; NumberAnimation { duration: 400; easing.type: Easing.Linear } }
      Behavior on height { enabled: root.vertical && root.inMeeting; NumberAnimation { duration: 400; easing.type: Easing.Linear } }

      Rectangle {
        width: pill.width
        height: pill.height
        radius: pill.radius
        color: root.pillFillColor
        antialiasing: true
      }
    }
  }

  WidgetButton {
    id: button
    z: 1
    anchors.fill: parent
    bar: root.bar
    text: root.label !== "" ? root.label : Model.ICON_CALENDAR_EMPTY
    foreground: root.barLabelColor
    labelVisible: false
    hasVisualContent: true
    dimmed: false
    active: root.inMeeting
    useActiveColor: false
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipLine

    Text {
      id: outlinedLabel
      anchors.centerIn: parent
      enabled: false
      textFormat: Text.PlainText
      text: button.text
      color: root.barLabelColor
      opacity: root.label === "" ? 0.7 : 1
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      style: root.barTransparent ? Text.Normal : Text.Outline
      styleColor: "#000000"
      renderType: root.barTransparent ? Text.NativeRendering : Text.QtRendering
      rotation: button.textRotation
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.nextMeeting && root.nextMeeting.meetUrl) root.joinMeeting(root.nextMeeting)
        else root.toggle()
      } else if (b === Qt.MiddleButton) {
        root.refresh()
      } else {
        root.toggle()
      }
    }
  }

  readonly property string tooltipLine: Model.tooltipLine(root.configured, root.nextMeeting, root.now, {
    lastFetchFailed: root.lastFetchFailed,
    offlineFeedCount: root.offlineFeedCount,
    showCalendarLabel: root.showCalendarLabel,
    use12Hour: root.use12Hour
  })
}
