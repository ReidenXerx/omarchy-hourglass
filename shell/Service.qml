import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "DetailModel.js" as Detail

// Hourglass's service: notices which app is in front while you are at the keyboard, and hands the time to the helper
// once a minute.
//
// Time counts while an app is focused and you are not idle (the Wayland idle monitor, which also honours a film's
// idle inhibitor). A minute without input ends the stretch where the input stopped; a sleep ends it where the laptop
// went down. Coming back after five minutes away is a pick-up. Only the app's class is kept, never a title.
Item {
  id: hourglass

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "reidenxerx.hourglass"
  readonly property string helper: String(Qt.resolvedUrl("../bin/hourglass")).replace("file://", "")
  readonly property int pickupAway: 300          // seconds away that make coming back a pick-up
  // Its own icon for notifications: icon themes name an hourglass differently, or not at all.
  readonly property string icon: String(Qt.resolvedUrl("../assets/hourglass.svg")).replace("file://", "")
  readonly property var helperEnv: ({
    PATH: "/usr/bin",
    HOME: Quickshell.env("HOME") || "",
    XDG_STATE_HOME: Quickshell.env("XDG_STATE_HOME") || "",
    XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME") || "",
    XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || ""
  })

  // ---------------------------------------------------------------- settings, from Hourglass's entry in shell.json

  property var entry: null
  readonly property string limits: hourglass.entry && typeof hourglass.entry.limits === "string" ? hourglass.entry.limits.slice(0, 2000) : ""
  readonly property bool weeklySummary: !hourglass.entry || hourglass.entry.weeklySummary !== false
  // Details are off until you turn them on. Then only a short label is kept, never a title (DetailModel.js).
  readonly property bool details: hourglass.entry !== null && hourglass.entry.details === true
  readonly property var pageSites: Detail.siteList(hourglass.entry ? hourglass.entry.pageSites : "")
  readonly property var neverApps: String(hourglass.entry && typeof hourglass.entry.neverApps === "string" ? hourglass.entry.neverApps : "")
    .toLowerCase().split(",").map(function (a) { return a.trim() }).filter(function (a) { return a.length > 0 }).slice(0, 48)
  readonly property int idleSeconds: {
    var n = hourglass.entry ? Number(hourglass.entry.idleSeconds) : 60
    return isFinite(n) ? Math.max(30, Math.min(600, Math.round(n))) : 60
  }

  function findEntry(config) {
    if (!config || typeof config !== "object") return null
    var layout = config.bar && config.bar.layout ? config.bar.layout : {}
    for (var section in layout) {
      var list = layout[section]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) if (list[i] && list[i].id === hourglass.pluginId) return list[i]
    }
    return null
  }

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      if (raw.length > 4 * 1024 * 1024) return
      try { hourglass.entry = hourglass.findEntry(JSON.parse(raw)) } catch (e) { }
    }
  }

  property string message: ""

  // A changed limit is shown, and checked, at once.
  onLimitsChanged: hourglass.refresh()

  function save(next) {
    if (!hourglass.shell || typeof hourglass.shell.updateEntryInline !== "function" || !hourglass.entry) {
      hourglass.message = "Hourglass can only save its settings while its widget is on the bar."
      return false
    }
    var payload = { limits: String(next.limits !== undefined ? next.limits : hourglass.limits),
                    weeklySummary: next.weeklySummary !== undefined ? next.weeklySummary === true : hourglass.weeklySummary,
                    idleSeconds: next.idleSeconds !== undefined ? next.idleSeconds : hourglass.idleSeconds,
                    details: next.details !== undefined ? next.details === true : hourglass.details,
                    pageSites: next.pageSites !== undefined ? String(next.pageSites) : hourglass.pageSites.join(", "),
                    neverApps: next.neverApps !== undefined ? String(next.neverApps) : hourglass.neverApps.join(", ") }
    hourglass.shell.updateEntryInline(hourglass.pluginId, payload)
    hourglass.message = ""
    return true
  }

  // ---------------------------------------------------------------- what is in front, and whether you are there

  readonly property var focused: ToplevelManager.activeToplevel
  readonly property string appClass: {
    var c = hourglass.focused ? String(hourglass.focused.appId || "").trim().slice(0, 64) : ""
    return /^[A-Za-z0-9][A-Za-z0-9 ._+:@-]*$/.test(c) ? c : ""
  }

  // What the label for the window in front is: from its title for browsers and editors, from what runs in it for
  // terminals (the helper's probe), nothing for apps you listed or for private windows.
  readonly property string title: hourglass.focused ? String(hourglass.focused.title || "").slice(0, 512) : ""
  readonly property string kind: Detail.kind(hourglass.appClass)
  readonly property bool describable: hourglass.details && hourglass.appClass !== ""
    && hourglass.neverApps.indexOf(hourglass.appClass.toLowerCase()) < 0
  property string terminalLabel: ""
  readonly property string detailLabel: !hourglass.describable ? ""
    : hourglass.kind === "terminal" ? hourglass.terminalLabel
    : Detail.label(hourglass.appClass, hourglass.title, hourglass.pageSites)

  onDetailLabelChanged: {
    var now = Date.now()
    if (hourglass.current && hourglass.current.d !== hourglass.detailLabel) {
      hourglass.closeAt(now)
      hourglass.openAt(now)
    }
  }

  function probeTerminal() {
    if (!hourglass.describable || hourglass.kind !== "terminal" || prober.running) return
    Hyprland.refreshToplevels()
    var top = Hyprland.activeToplevel
    var pid = top && top.lastIpcObject ? Number(top.lastIpcObject.pid) : 0
    if (!(pid > 0)) { hourglass.terminalLabel = ""; return }
    prober.command = ["/usr/bin/python3", "-I", hourglass.helper, "probe", String(Math.floor(pid))]
    prober.running = true
    deadline.restart()
  }

  Process {
    id: prober
    clearEnvironment: true
    environment: hourglass.helperEnv
    stdout: StdioCollector {
      onStreamFinished: hourglass.terminalLabel = Detail.clip(text.split("\n")[0])
    }
  }

  // While a terminal is in front, what runs in it is looked at again every twenty seconds.
  Timer {
    interval: 20000
    repeat: true
    running: hourglass.describable && hourglass.kind === "terminal" && !hourglass.away
    triggeredOnStart: true
    onTriggered: hourglass.probeTerminal()
  }

  function forgetDetails() {
    if (forgetter.running) return
    forgetter.running = true
    deadline.restart()
  }

  Process {
    id: forgetter
    command: ["/usr/bin/python3", "-I", hourglass.helper, "forget-details"]
    clearEnvironment: true
    environment: hourglass.helperEnv
    onExited: function (code) {
      hourglass.message = code === 0 ? "" : "Hourglass could not forget the details."
      hourglass.refresh()
    }
  }

  IdleMonitor {
    id: idle
    enabled: true
    respectInhibitors: true
    timeout: hourglass.idleSeconds
  }

  readonly property bool away: idle.isIdle

  property var current: null          // { app, start } in milliseconds
  property var pending: []            // stretches and pick-ups waiting for the helper
  property double awaySince: 0
  property double lastTick: Date.now()

  function closeAt(endMs) {
    var c = hourglass.current
    hourglass.current = null
    if (!c || endMs - c.start < 2000) return
    var stretch = { a: c.app, s: Math.floor(c.start / 1000), e: Math.floor(endMs / 1000) }
    if (c.d) stretch.d = c.d
    hourglass.pending = hourglass.pending.concat([stretch])
  }

  function openAt(startMs) {
    if (hourglass.appClass && !hourglass.away)
      hourglass.current = { app: hourglass.appClass, start: startMs, d: hourglass.detailLabel }
  }

  function back(nowMs) {
    if (hourglass.awaySince > 0 && nowMs - hourglass.awaySince >= hourglass.pickupAway * 1000)
      hourglass.pending = hourglass.pending.concat([{ p: Math.floor(nowMs / 1000) }])
    hourglass.awaySince = 0
  }

  onAppClassChanged: {
    var now = Date.now()
    hourglass.terminalLabel = ""
    hourglass.closeAt(now)
    hourglass.openAt(now)
  }

  onAwayChanged: {
    var now = Date.now()
    if (hourglass.away) {
      // The input stopped a whole timeout ago; the time since was not spent here.
      var stopped = now - hourglass.idleSeconds * 1000
      hourglass.closeAt(Math.max(stopped, hourglass.current ? hourglass.current.start : stopped))
      hourglass.awaySince = stopped
    } else {
      hourglass.back(now)
      hourglass.openAt(now)
    }
  }

  // A clock that jumped means the laptop slept: the stretch ended when it went down.
  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      if (now - hourglass.lastTick > 60000) {
        hourglass.closeAt(hourglass.lastTick)
        if (hourglass.awaySince === 0) hourglass.awaySince = hourglass.lastTick
        if (!hourglass.away) {
          hourglass.back(now)
          hourglass.openAt(now)
        }
      }
      hourglass.lastTick = now
    }
  }

  // ---------------------------------------------------------------- handing it to the helper

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: hourglass.flush()
  }

  function flush() {
    // Cut the stretch in progress, so a shell restart loses at most a minute.
    if (hourglass.current) {
      var now = Date.now()
      var app = hourglass.current.app
      hourglass.closeAt(now)
      if (!hourglass.away && app === hourglass.appClass) hourglass.current = { app: app, start: now, d: hourglass.detailLabel }
    }
    if (hourglass.pending.length === 0 || adder.running) return
    adder.payload = JSON.stringify(hourglass.pending.slice(0, 2000))
    hourglass.pending = []
    adder.running = true
    deadline.restart()
  }

  Process {
    id: adder
    property string payload: ""
    command: ["/usr/bin/python3", "-I", hourglass.helper, "add"]
    clearEnvironment: true
    environment: hourglass.helperEnv
    stdinEnabled: true
    onStarted: {
      adder.write(adder.payload + "\n")
      adder.payload = ""
    }
    onExited: function (code) { if (hourglass.panelOpen) hourglass.refresh() }
  }

  // ---------------------------------------------------------------- reports

  property var report: null
  property bool panelOpen: false

  function refresh() {
    if (reporter.running) return
    reporter.command = ["/usr/bin/python3", "-I", hourglass.helper, "report", "--limits", hourglass.limits]
    reporter.running = true
    deadline.restart()
  }

  Process {
    id: reporter
    clearEnvironment: true
    environment: hourglass.helperEnv
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.length > 2 * 1024 * 1024) return
        try {
          hourglass.report = JSON.parse(text)
          hourglass.checkLimits()
        } catch (e) { }
      }
    }
  }

  // Any helper call that has not finished in ten seconds is stopped.
  Timer {
    id: deadline
    interval: 10000
    onTriggered: {
      if (adder.running) adder.signal(9)
      if (reporter.running) reporter.signal(9)
      if (weekly.running) weekly.signal(9)
    }
  }

  // Today's total for the bar: the last report, plus the stretch in progress.
  property double nowMs: Date.now()
  readonly property int todaySeconds: {
    var base = hourglass.report ? hourglass.report.today.total : 0
    var live = hourglass.current ? Math.max(0, (hourglass.nowMs - hourglass.current.start) / 1000) : 0
    return Math.round(base + live)
  }

  Timer {
    interval: hourglass.panelOpen ? 60000 : 120000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      hourglass.nowMs = Date.now()
      hourglass.refresh()
      // The weekly summary is due from Sunday 20:00; the helper makes sure it is told only once.
      var d = new Date()
      if (hourglass.weeklySummary && d.getDay() === 0 && d.getHours() >= 20 && !weekly.running) weekly.running = true
    }
  }

  // ---------------------------------------------------------------- limits and the weekly summary

  // Which limits have been told about today: "key|five" and "key|done", reset at midnight.
  PersistentProperties {
    id: told
    reloadableId: "reidenxerx.hourglass.told"
    property string day: ""
    property string keys: ""
  }

  readonly property bool limitClose: {
    var list = hourglass.report ? hourglass.report.limits : []
    for (var i = 0; i < list.length; i++) if (list[i].left <= 600) return true
    return false
  }

  function checkLimits() {
    var today = new Date().toDateString()
    if (told.day !== today) { told.day = today; told.keys = "" }
    var list = hourglass.report ? hourglass.report.limits : []
    for (var i = 0; i < list.length; i++) {
      var x = list[i]
      var id = x.kind + ":" + x.key
      if (x.left <= 0 && told.keys.indexOf(id + "|done;") < 0) {
        told.keys += id + "|done;"
        hourglass.notify("Time is up for " + x.name, "You set " + x.minutes + " minutes a day for it.")
      } else if (x.left > 0 && x.left <= 300 && told.keys.indexOf(id + "|five;") < 0) {
        told.keys += id + "|five;"
        hourglass.notify("Five minutes left for " + x.name, "Of the " + x.minutes + " minutes a day you set.")
      }
    }
  }

  function notify(title, body) {
    Quickshell.execDetached({
      command: ["/usr/bin/notify-send", "--app-name=Hourglass", "--icon=" + hourglass.icon, "--", String(title).slice(0, 120), String(body).slice(0, 240)],
      clearEnvironment: true,
      environment: { PATH: "/usr/bin", DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS") || "",
                     XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") || "" }
    })
  }

  Process {
    id: weekly
    command: ["/usr/bin/python3", "-I", hourglass.helper, "weekly"]
    clearEnvironment: true
    environment: hourglass.helperEnv
    stdout: StdioCollector {
      onStreamFinished: {
        var line = text.trim().slice(0, 300)
        if (line) hourglass.notify("Your week", line)
      }
    }
  }

  // ---------------------------------------------------------------- the panel

  property real anchorX: -1

  function togglePanel(x) {
    if (x !== undefined && x >= 0) hourglass.anchorX = x
    if (hourglass.shell && typeof hourglass.shell.toggle === "function") hourglass.shell.toggle(hourglass.pluginId, "{}")
  }

  function setLimit(kind, key, minutes) {
    var parts = hourglass.limits.split(";").map(function (p) { return p.trim() }).filter(function (p) {
      return p && p.indexOf(kind + ":" + key + "=") !== 0
    })
    if (minutes > 0) parts.push(kind + ":" + key + "=" + Math.max(5, Math.min(1440, Math.round(minutes))))
    hourglass.save({ limits: parts.slice(0, 24).join("; ") })
  }

  Component.onCompleted: hourglass.openAt(Date.now())
}
