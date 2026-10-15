import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Hourglass in the bar: an hourglass, today's time in the tooltip, and a dot when a limit you set is close.
BarWidget {
  id: root
  moduleName: "reidenxerx.hourglass"

  readonly property string pluginId: "reidenxerx.hourglass"
  property var hourglass: null

  function findService() {
    if (root.hourglass) return
    var shell = root.bar ? root.bar.shell : null
    root.hourglass = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(root.pluginId) : null
  }

  Timer {
    interval: 1000
    repeat: true
    running: !root.hourglass
    triggeredOnStart: true
    onTriggered: root.findService()
  }

  onBarChanged: root.findService()

  function spell(seconds) {
    var minutes = Math.floor(seconds / 60)
    if (seconds > 0 && minutes === 0) return "under a minute"
    if (minutes < 60) return minutes + " min"
    return Math.floor(minutes / 60) + " h " + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + " min"
  }

  readonly property string tooltip: {
    var h = root.hourglass
    if (!h) return "Hourglass"
    var line = "Hourglass: " + root.spell(h.todaySeconds) + " today"
    var r = h.report
    if (r && r.today.pickups > 0) line += ", " + r.today.pickups + (r.today.pickups === 1 ? " pick-up" : " pick-ups")
    if (h.limitClose) line += "\nA limit you set is close"
    return line
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // md-timer-sand U+F051F (checked in the font's cmap).
    text: String.fromCodePoint(0xF051F)
    tooltipText: root.tooltip
    onPressed: function (which) {
      if (!root.hourglass) return
      var p = button.mapToItem(null, button.width / 2, 0)
      root.hourglass.togglePanel(p.x)
    }
  }

  Rectangle {
    visible: root.hourglass !== null && root.hourglass.limitClose
    width: Math.max(4, Style.space(5))
    height: width
    radius: width / 2
    color: Commons.Color.accent
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: Style.space(4)
  }
}
