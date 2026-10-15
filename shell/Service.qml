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

  // A helper call that has not finished in ten seconds is stopped. One per process, so one call never extends
  // another's deadline.
  component Deadline: Timer {
    property var target: null
    interval: 10000
    running: target !== null && target.running
    onTriggered: if (target && target.running) target.signal(9)
  }

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
    var top = Hyprland.activeToplevel
    var pid = top && top.lastIpcObject ? Number(top.lastIpcObject.pid) : 0
    if (!(pid > 0)) { hourglass.terminalLabel = ""; return }
    prober.command = ["/usr/bin/python3", "-I", hourglass.helper, "probe", String(Math.floor(pid))]
    prober.running = true
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
    // What is still waiting to be written goes without its labels too.
    hourglass.pending = hourglass.pending.map(function (r) { var c = Object.assign({}, r); delete c.d; return c })
    if (hourglass.current) hourglass.current = { app: hourglass.current.app, start: hourglass.current.start, d: "" }
    if (forgetter.running) return
    forgetter.running = true
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
    hourglass.closeAt(now)
    hourglass.openAt(now)
  }

  // Another window, even of the same terminal, may run something else: its label is read again, once Hyprland's
  // list of windows has caught up with the focus change.
  onFocusedChanged: {
    hourglass.terminalLabel = ""
    if (hourglass.kind === "terminal") {
      Hyprland.refreshToplevels()
      probeSoon.restart()
    }
  }

  Timer {
    id: probeSoon
    interval: 400
    onTriggered: hourglass.probeTerminal()
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

  // A clock that jumped means the laptop slept: the stretch ended when it went down. Checked by its own timer and
  // first thing in every flush, so after a resume the flush can never be the one that counts the sleep.
  function checkClock() {
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

  Timer {
    interval: 15000
    repeat: true
    running: true
    onTriggered: hourglass.checkClock()
  }

  // ---------------------------------------------------------------- handing it to the helper

  Timer {
    interval: 60000
    repeat: true
    running: true
    onTriggered: hourglass.flush()
  }

  function flush() {
    hourglass.checkClock()
    // Cut the stretch in progress, so a shell restart loses at most a minute. Cut where you were surely here: the
    // last idle timeout of it may yet turn out to have been idle, and is left in the stretch that goes on.
    if (hourglass.current) {
      var cut = Date.now() - hourglass.idleSeconds * 1000
      if (cut > hourglass.current.start) {
        var keep = hourglass.current
        hourglass.closeAt(cut)
        hourglass.current = { app: keep.app, start: cut, d: keep.d }
      }
    }
    if (hourglass.pending.length === 0 || adder.running) return
    adder.batch = hourglass.pending.slice(0, 2000)
    hourglass.pending = hourglass.pending.slice(2000)
    adder.payload = JSON.stringify(adder.batch)
    adder.running = true
  }

  Process {
    id: adder
    property string payload: ""
    property var batch: []
    command: ["/usr/bin/python3", "-I", hourglass.helper, "add"]
    clearEnvironment: true
    environment: hourglass.helperEnv
    stdinEnabled: true
    onStarted: {
      adder.write(adder.payload + "\n")
      adder.payload = ""
    }
    onExited: function (code) {
      // A batch the helper did not take is kept for the next flush, not lost.
      if (code !== 0) hourglass.pending = adder.batch.concat(hourglass.pending).slice(0, 5000)
      adder.batch = []
      if (hourglass.panelOpen) hourglass.refresh()
    }
  }

  // ---------------------------------------------------------------- reports

  property var report: null
  property bool panelOpen: false

  function refresh() {
    if (reporter.running) return
    reporter.command = ["/usr/bin/python3", "-I", hourglass.helper, "report", "--limits", hourglass.limits]
    reporter.running = true
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

  Deadline { target: adder }
  Deadline { target: reporter }
  Deadline { target: weekly }
  Deadline { target: prober }
  Deadline { target: forgetter }

  // Today's total for the bar: the last report, plus the stretch in progress.
  property double nowMs: Date.now()
  readonly property int todaySeconds: {
    var base = hourglass.report ? hourglass.report.today.total : 0
    var live = hourglass.current ? Math.max(0, (hourglass.nowMs - hourglass.current.start) / 1000) : 0
    return Math.round(base + live)
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: hourglass.nowMs = Date.now()
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

  // Which limit notices were given today: kept by the helper on disk (so a restart does not repeat them), and here
  // until the next report includes them.
  property var toldNow: []

  function wasTold(key) {
    var onDisk = hourglass.report && Array.isArray(hourglass.report.told) ? hourglass.report.told : []
    return onDisk.indexOf(key) >= 0 || hourglass.toldNow.indexOf(key) >= 0
  }

  function tell(key, title, body) {
    hourglass.toldNow = hourglass.toldNow.concat([key])
    teller.command = ["/usr/bin/python3", "-I", hourglass.helper, "told", key]
    if (!teller.running) teller.running = true
    hourglass.notify(title, body)
  }

  Process {
    id: teller
    clearEnvironment: true
    environment: hourglass.helperEnv
  }
  Deadline { target: teller }

  readonly property bool limitClose: {
    var list = hourglass.report ? hourglass.report.limits : []
    for (var i = 0; i < list.length; i++) if (list[i].left <= 600) return true
    return false
  }

  function checkLimits() {
    var list = hourglass.report ? hourglass.report.limits : []
    for (var i = 0; i < list.length; i++) {
      var x = list[i]
      var id = x.kind + ":" + x.key
      if (x.left <= 0 && !hourglass.wasTold(id + "|done"))
        hourglass.tell(id + "|done", "Time is up for " + x.name, "You set " + x.minutes + " minutes a day for it.")
      else if (x.left > 0 && x.left <= 300 && !hourglass.wasTold(id + "|five"))
        hourglass.tell(id + "|five", "Five minutes left for " + x.name, "Of the " + x.minutes + " minutes a day you set.")
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
