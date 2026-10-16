import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import "../code/DetailModel.js" as Detail

// Hourglass for Plasma: screen time the way a phone shows it.
//
// Plasma tells this widget which window is in front (the task manager model); the recorder service
// (bin/hourglass serve, the same core as the Omarchy edition) keeps the clock, asks the desktop how long it has been
// idle, reads what runs in a terminal and writes the history. This sends it only the app's id and, if you turned
// details on, a short label derived here from the title; a window's title itself never leaves the widget.
PlasmoidItem {
  id: root

  readonly property string service: "app.duduphudu.Hourglass"
  readonly property string helper: String(Qt.resolvedUrl("../code/bin/hourglass")).replace("file://", "")

  readonly property bool recording: watcher.registered
  property var report: null
  property string message: ""

  toolTipMainText: "Hourglass"
  toolTipSubText: {
    if (!root.recording) return "Not recording: open to start"
    var t = root.todaySeconds
    var line = root.spell(t) + " today"
    if (root.report && root.report.today.pickups > 0) line += ", " + root.report.today.pickups + " pick-ups"
    return line
  }

  preferredRepresentation: compactRepresentation
  fullRepresentation: FullView { hourglass: root }

  // ---------------------------------------------------------------- the recorder

  DBus.DBusServiceWatcher {
    id: watcher
    busType: DBus.BusType.Session
    watchedService: root.service
    onRegisteredChanged: if (registered) { root.sendFocus(true); root.refresh() }
  }

  // Plasma's D-Bus module wants the signature as a whole tuple, "(ssbu)": given "ssbu" it silently sends no
  // arguments at all. Both callbacks get the pending reply; the answer is its value.
  function call(member, signature, args, done) {
    var message = { service: root.service, path: "/app/duduphudu/Hourglass", iface: "app.duduphudu.Hourglass1",
                    member: member, arguments: args }
    if (signature) message.signature = "(" + signature + ")"
    DBus.SessionBus.asyncCall(message, function (reply) { if (done) done(String(reply.value === undefined ? "" : reply.value)) }, function (reply) {
      root.message = "The recorder did not answer."
      console.warn("hourglass:", member, reply.error ? reply.error.message : "")
    })
  }

  // Commands the widget runs: the helper by absolute path, its path quoted, nothing from outside in it.
  P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []
    property var onDone: ({})
    onNewData: function (source, data) {
      disconnectSource(source)
      var cb = runner.onDone[source]
      delete runner.onDone[source]
      if (cb) cb(data["exit code"], String(data["stdout"] || "").slice(0, 4096))
    }
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function run(command, done) {
    runner.onDone[command] = done
    runner.connectSource(command)
  }

  function startRecording() {
    root.message = "Starting the recorder…"
    root.run("/usr/bin/python3 -I " + root.quote(root.helper) + " install-service", function (code) {
      root.message = code === 0 ? "" : "The recorder could not be started. It needs systemd and Python 3."
    })
  }

  function stopRecording() {
    root.run("/usr/bin/python3 -I " + root.quote(root.helper) + " remove-service", function (code) {
      root.message = code === 0 ? "" : "The recorder could not be stopped."
    })
  }

  // ---------------------------------------------------------------- the window in front

  TaskManager.TasksModel {
    id: tasks
    filterByVirtualDesktop: false
    filterByScreen: false
    filterByActivity: false
    filterMinimized: false
    groupMode: TaskManager.TasksModel.GroupDisabled
    onActiveTaskChanged: root.sendFocus(false)
    onDataChanged: function (from, to) {
      if (tasks.activeTask.valid && from.row <= tasks.activeTask.row && to.row >= tasks.activeTask.row) root.sendFocus(false)
    }
  }

  readonly property var pageSites: Detail.siteList(Plasmoid.configuration.pageSites)
  readonly property var neverApps: String(Plasmoid.configuration.neverApps || "").toLowerCase().split(",")
    .map(function (a) { return a.trim() }).filter(function (a) { return a.length > 0 }).slice(0, 48)
  property string lastSent: ""
  // The app last in front, for the panel's "Limit … to 1 h" (the open panel itself is never a task).
  property string appNow: ""

  function sendFocus(force) {
    if (!root.recording) return
    var i = tasks.activeTask
    var app = "", title = "", pid = 0
    if (i && i.valid) {
      app = String(tasks.data(i, TaskManager.AbstractTasksModel.AppId) || "").replace(/\.desktop$/, "").slice(0, 64)
      title = String(tasks.data(i, Qt.DisplayRole) || "").slice(0, 512)
      pid = Number(tasks.data(i, TaskManager.AbstractTasksModel.AppPid) || 0)
    }
    var describable = Plasmoid.configuration.details && app !== "" && root.neverApps.indexOf(app.toLowerCase()) < 0
    var kind = Detail.kind(app)
    var label = describable && kind !== "terminal" ? Detail.label(app, title, root.pageSites) : ""
    var terminal = describable && kind === "terminal"
    root.appNow = app
    var key = app + "|" + label + "|" + terminal + "|" + pid
    if (!force && key === root.lastSent) return
    root.lastSent = key
    root.call("Focus", "ssbu", [app, label, terminal, Math.max(0, Math.floor(pid))], null)
  }

  // ---------------------------------------------------------------- reports, limits and the week

  property double nowMs: Date.now()
  readonly property int todaySeconds: {
    var base = root.report ? root.report.today.total : 0
    var live = root.report && root.report.live ? root.report.live.seconds : 0
    return base + live
  }

  function refresh() {
    if (!root.recording) return
    root.call("Report", "s", [String(Plasmoid.configuration.limits || "").slice(0, 2000)], function (reply) {
      try {
        var text = String(reply)
        if (text.length > 2 * 1024 * 1024) return
        root.report = JSON.parse(text)
        root.message = ""
        root.checkLimits()
      } catch (e) {
        root.message = "Hourglass could not read its history."
      }
    })
  }

  Timer {
    interval: root.expanded ? 60000 : 120000
    repeat: true
    running: root.recording
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      root.refresh()
      var d = new Date()
      if (Plasmoid.configuration.weeklySummary && d.getDay() === 0 && d.getHours() >= 20)
        root.call("Weekly", "", [], function (reply) { var t = String(reply || ""); if (t) root.notify("Your week", t) })
    }
  }

  onExpandedChanged: function () { if (root.expanded) root.refresh() }

  property var toldNow: []

  function checkLimits() {
    var list = root.report ? root.report.limits : []
    var onDisk = root.report && Array.isArray(root.report.told) ? root.report.told : []
    for (var i = 0; i < list.length; i++) {
      var x = list[i]
      var id = x.kind + ":" + x.key
      var done = id + "|done", five = id + "|five"
      if (x.left <= 0 && onDisk.indexOf(done) < 0 && root.toldNow.indexOf(done) < 0)
        root.tell(done, "Time is up for " + x.name, "You set " + x.minutes + " minutes a day for it.")
      else if (x.left > 0 && x.left <= 300 && onDisk.indexOf(five) < 0 && root.toldNow.indexOf(five) < 0)
        root.tell(five, "Five minutes left for " + x.name, "Of the " + x.minutes + " minutes a day you set.")
    }
  }

  function tell(key, title, body) {
    root.toldNow = root.toldNow.concat([key])
    root.call("Told", "s", [key], null)
    root.notify(title, body)
  }

  function notify(title, body) {
    root.run("/usr/bin/notify-send --app-name=Hourglass --icon=chronometer -- " + root.quote(String(title).slice(0, 120))
             + " " + root.quote(String(body).slice(0, 240)), null)
  }

  // Changed in place, so a limit keeps its row; a new one is added last.
  function setLimit(kind, key, minutes) {
    var prefix = kind + ":" + key + "="
    var entry = minutes > 0 ? prefix + Math.max(5, Math.min(1440, Math.round(minutes))) : ""
    var parts = String(Plasmoid.configuration.limits || "").split(";").map(function (p) { return p.trim() })
      .filter(function (p) { return p.length > 0 })
    var at = parts.findIndex(function (p) { return p.indexOf(prefix) === 0 })
    if (at >= 0) parts.splice(at, 1, entry); else parts.push(entry)
    Plasmoid.configuration.limits = parts.filter(function (p) { return p.length > 0 }).slice(0, 24).join("; ")
    root.refresh()
  }

  function save(key, value) {
    Plasmoid.configuration[key] = value
    if (key === "details" || key === "neverApps") root.sendFocus(true)
  }

  function forgetDetails() {
    root.call("ForgetDetails", "", [], function () { root.refresh() })
  }

  function spell(seconds) {
    var minutes = Math.floor(seconds / 60)
    if (seconds > 0 && minutes === 0) return "under a minute"
    if (minutes < 60) return minutes + " min"
    var m = minutes % 60
    return Math.floor(minutes / 60) + " h" + (m ? " " + (m < 10 ? "0" : "") + m : "")
  }

  Plasmoid.icon: "chronometer"
}
