import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Hourglass's panel: the day or the week at the laptop, by hour, by category and by app, how often you came back to
// it, and the limits you set. Held by the shell as an overlay so it outlives the bar widget's rebuilds; no text
// fields, so nothing here reads the clipboard.
Item {
  id: overlay

  property var shell: null
  property var manifest: null
  property var hourglass: null
  property bool opened: false
  property string range: "today"

  readonly property string pluginId: "reidenxerx.hourglass"

  function findService() {
    if (!overlay.hourglass && overlay.shell && typeof overlay.shell.serviceFor === "function")
      overlay.hourglass = overlay.shell.serviceFor(overlay.pluginId)
  }

  Timer {
    interval: 1000
    repeat: true
    running: !overlay.hourglass
    triggeredOnStart: true
    onTriggered: overlay.findService()
  }

  function open(payloadJson) {
    overlay.findService()
    overlay.opened = true
    if (overlay.hourglass) {
      overlay.hourglass.panelOpen = true
      overlay.hourglass.flush()
      overlay.hourglass.refresh()
    }
  }

  function close() {
    if (!overlay.opened) return
    overlay.opened = false
    if (overlay.hourglass) overlay.hourglass.panelOpen = false
  }

  function dismiss() {
    overlay.close()
    if (overlay.shell && typeof overlay.shell.hide === "function") overlay.shell.hide(overlay.pluginId)
  }

  function toggle() {
    if (overlay.opened) overlay.dismiss()
    else overlay.open("{}")
  }

  readonly property var r: overlay.hourglass ? overlay.hourglass.report : null
  readonly property bool week: overlay.range === "week"
  readonly property color ink: Commons.Color.popups.text
  readonly property color faint: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.6)
  readonly property color hairline: Qt.rgba(overlay.ink.r, overlay.ink.g, overlay.ink.b, 0.12)
  readonly property color accent: Commons.Color.accent
  readonly property color paper: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g,
                                         Commons.Color.popups.background.b, 1)
  readonly property var borderSpec: Border.localOrSurfaceSpec("popups", "border", Commons.Color.popups.border,
                                                              Commons.Color.popups.border, Math.max(1, Style.space(2)))

  // One colour per category, the same everywhere in the panel: the accent for the first, then theme-neutral tints.
  function categoryColor(name) {
    var order = ["Development", "Web", "Social", "Games", "Entertainment", "Creativity", "Productivity", "Utilities", "Other"]
    var hues = [overlay.accent, "#6f9fd8", "#6fc795", "#ef8a7d", "#c792ea", "#e2c46a", "#7fd1c7", "#9aa1ad", "#6b717d"]
    var i = order.indexOf(name)
    return hues[i < 0 ? hues.length - 1 : i]
  }

  function spell(seconds) {
    var minutes = Math.floor(seconds / 60)
    if (seconds > 0 && minutes === 0) return "under a minute"
    if (minutes < 60) return minutes + " min"
    var m = minutes % 60
    return Math.floor(minutes / 60) + " h" + (m ? " " + (m < 10 ? "0" : "") + m : "")
  }

  function clock(t) {
    var d = new Date(t * 1000)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
  }

  readonly property int total: overlay.r ? (overlay.week ? overlay.r.week.total : overlay.hourglass.todaySeconds) : 0
  readonly property var categories: overlay.r ? (overlay.week ? overlay.r.week.categories : overlay.r.today.categories) : []
  readonly property var appList: overlay.r ? (overlay.week ? overlay.r.week.apps : overlay.r.today.apps) : []

  readonly property string comparison: {
    if (!overlay.r) return ""
    if (overlay.week) {
      var prev = overlay.r.week.previous
      if (!prev) return overlay.r.week.pickups + " pick-ups this week"
      var c = Math.round(100 * (overlay.r.week.total - prev) / prev)
      return (c === 0 ? "The same as last week" : Math.abs(c) + "% " + (c > 0 ? "more" : "less") + " than last week") + " · " + overlay.r.week.pickups + " pick-ups"
    }
    var line = overlay.r.today.pickups + (overlay.r.today.pickups === 1 ? " pick-up" : " pick-ups")
    var avg = overlay.r.average
    if (avg) {
      var d = Math.round(100 * (overlay.total - avg) / avg)
      line = (d === 0 ? "Right on your daily average" : Math.abs(d) + "% " + (d > 0 ? "above" : "below") + " your daily average") + " · " + line
    }
    return line
  }

  component Heading: Text {
    textFormat: Text.PlainText
    color: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    Layout.topMargin: Style.space(4)
  }

  PanelWindow {
    id: surface
    visible: overlay.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hourglass-panel"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: overlay.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    MouseArea {
      anchors.fill: parent
      onClicked: overlay.dismiss()
    }

    Item {
      anchors.fill: parent
      focus: overlay.opened
      Keys.onEscapePressed: overlay.dismiss()
    }

    BorderSurface {
      id: card
      width: Style.space(430)
      height: Math.min(surface.height - y - Style.gapsOut * 2, content.implicitHeight + Style.spacing.popupPadding * 2)
      x: {
        var want = overlay.hourglass && overlay.hourglass.anchorX >= 0 ? overlay.hourglass.anchorX - width / 2 : surface.width - width
        return Math.max(Style.gapsOut, Math.min(surface.width - width - Style.gapsOut, want))
      }
      y: Style.bar.sizeHorizontal + Style.gapsOut * 2
      color: overlay.paper
      borderSpec: overlay.borderSpec
      radius: Style.cornerRadius
      clip: true

      MouseArea { anchors.fill: parent }

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.spacing.popupPadding
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(10)

          // ------------------------------------------------ the total
          RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                textFormat: Text.PlainText
                text: overlay.week ? "This week" : "Today"
                color: overlay.faint
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
              }
              Text {
                textFormat: Text.PlainText
                text: overlay.r ? overlay.spell(overlay.total) : "Reading…"
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }
            ButtonGroup {
              Layout.alignment: Qt.AlignTop
              options: [{ value: "today", label: "Today" }, { value: "week", label: "Week" }]
              value: overlay.range
              foreground: overlay.ink
              accent: overlay.accent
              fontSize: Style.font.caption
              onChanged: function (v) { overlay.range = v }
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: overlay.comparison
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // ------------------------------------------------ by hour, or by day
          Canvas {
            id: chart
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(110)
            readonly property var data: overlay.r
            readonly property bool weekView: overlay.week
            readonly property color ink: overlay.ink
            readonly property color bar: overlay.accent
            onDataChanged: requestPaint()
            onWeekViewChanged: requestPaint()
            onWidthChanged: requestPaint()
            onInkChanged: requestPaint()

            onPaint: {
              var c = getContext("2d")
              c.reset()
              var d = chart.data
              var bottom = Style.space(16)
              var h = height - bottom
              c.strokeStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.14)
              c.lineWidth = 1
              c.beginPath(); c.moveTo(0, h + 0.5); c.lineTo(width, h + 0.5); c.stroke()
              if (!d) return
              var values, labels, top
              if (chart.weekView) {
                values = d.week.days.map(function (x) { return x.seconds })
                labels = d.week.days.map(function (x) { return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(x.d + "T12:00:00").getDay()] })
                top = Math.max(3600, Math.max.apply(null, values))
              } else {
                values = d.today.hours
                labels = values.map(function (x, i) { return i % 6 === 0 ? (i < 10 ? "0" : "") + i : "" })
                top = 3600
              }
              var n = values.length
              var slot = width / n
              var w = Math.max(2, slot * (chart.weekView ? 0.55 : 0.7))
              c.fillStyle = chart.bar
              for (var i = 0; i < n; i++) {
                var bh = Math.round(values[i] / top * (h - 4))
                if (values[i] > 0 && bh < 2) bh = 2
                c.fillRect(i * slot + (slot - w) / 2, h - bh, w, bh)
              }
              // A dashed line for the daily average on the week chart.
              if (chart.weekView && d.average) {
                var ay = h - d.average / top * (h - 4)
                c.strokeStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.45)
                c.setLineDash([4, 4])
                c.beginPath(); c.moveTo(0, ay); c.lineTo(width, ay); c.stroke()
                c.setLineDash([])
              }
              c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.55)
              c.font = Math.round(Style.font.caption * 0.9) + "px sans-serif"
              c.textAlign = chart.weekView ? "center" : "left"
              for (var k = 0; k < n; k++)
                if (labels[k]) c.fillText(labels[k], chart.weekView ? k * slot + slot / 2 : k * slot + 1, height - 3)
            }
          }

          // ------------------------------------------------ by category
          Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(8)
            visible: overlay.categories.length > 0
            Row {
              anchors.fill: parent
              Repeater {
                model: overlay.categories
                delegate: Rectangle {
                  required property var modelData
                  width: overlay.total > 0 ? parent.width * Math.min(1, modelData.seconds / Math.max(1, overlay.categories.reduce(function (a, b) { return a + b.seconds }, 0))) : 0
                  height: parent.height
                  color: overlay.categoryColor(modelData.name)
                }
              }
            }
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(12)
            Repeater {
              model: overlay.categories.slice(0, 6)
              delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: modelData.name + " " + overlay.spell(modelData.seconds)
                color: overlay.categoryColor(modelData.name)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true }

          // ------------------------------------------------ by app
          Heading { text: "Most used" }

          Text {
            Layout.fillWidth: true
            visible: overlay.appList.length === 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "Nothing yet. Time counts while an app is in front and you are at the keyboard."
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: overlay.appList.slice(0, 8)
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(10)
              Rectangle {
                width: Style.space(8); height: width; radius: width / 2
                color: overlay.categoryColor(modelData.category)
              }
              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: modelData.name
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Text {
                textFormat: Text.PlainText
                text: overlay.spell(modelData.seconds)
                color: overlay.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            Layout.fillWidth: true
            visible: !overlay.week && overlay.r !== null && overlay.r.today.pickups > 0
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: {
              var t = overlay.r ? overlay.r.today : null
              if (!t) return ""
              var parts = []
              if (t.firstPickup) parts.push("First pick-up " + overlay.clock(t.firstPickup))
              if (t.busiestPickupHour !== null) parts.push("most pick-ups " + t.busiestPickupHour + ":00–" + (t.busiestPickupHour + 1) + ":00")
              if (t.longest && t.longest.seconds >= 600) parts.push("longest stretch " + overlay.spell(t.longest.seconds) + " in " + (overlay.appList.filter(function (a) { return a.app === t.longest.app })[0] || { name: t.longest.app }).name)
              return parts.join(" · ")
            }
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { Layout.fillWidth: true }

          // ------------------------------------------------ limits
          Heading { text: "Daily limits" }

          Repeater {
            model: overlay.r ? overlay.r.limits : []
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.space(6)
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: modelData.name + (modelData.kind === "cat" ? " (category)" : "")
                  color: overlay.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                Text {
                  textFormat: Text.PlainText
                  text: overlay.spell(modelData.used) + " of " + overlay.spell(modelData.minutes * 60) + (modelData.left <= 0 ? ", used up" : "")
                  color: modelData.left <= 300 ? Commons.Color.urgent : overlay.faint
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
              Button {
                text: "−"; bordered: true; foreground: overlay.ink; accent: overlay.accent
                onClicked: overlay.hourglass.setLimit(modelData.kind, modelData.key, Math.max(5, modelData.minutes - 15))
              }
              Button {
                text: "+"; bordered: true; foreground: overlay.ink; accent: overlay.accent
                onClicked: overlay.hourglass.setLimit(modelData.kind, modelData.key, modelData.minutes + 15)
              }
              Button {
                text: "Remove"; foreground: overlay.faint; accent: overlay.accent
                onClicked: overlay.hourglass.setLimit(modelData.kind, modelData.key, 0)
              }
            }
          }

          Flow {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Button {
              readonly property string cls: overlay.hourglass ? overlay.hourglass.appClass : ""
              readonly property var known: overlay.appList.filter(function (a) { return a.app === cls })[0]
              visible: cls !== "" && overlay.r !== null && overlay.r.limits.filter(function (x) { return x.kind === "app" && x.key === cls }).length === 0
              text: "Limit " + (known ? known.name : cls) + " to 1 h"
              bordered: true
              foreground: overlay.ink
              accent: overlay.accent
              onClicked: overlay.hourglass.setLimit("app", cls, 60)
            }
            Repeater {
              model: overlay.categories.filter(function (c) {
                return c.name !== "Other" && overlay.r && overlay.r.limits.filter(function (x) { return x.kind === "cat" && x.key === c.name }).length === 0
              }).slice(0, 3)
              delegate: Button {
                required property var modelData
                text: "Limit " + modelData.name + " to 1 h"
                bordered: true
                foreground: overlay.ink
                accent: overlay.accent
                onClicked: overlay.hourglass.setLimit("cat", modelData.name, 60)
              }
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "Limits send a notice five minutes before and when the time is up. They never close anything."
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          PanelSeparator { Layout.fillWidth: true }

          RowLayout {
            Layout.fillWidth: true
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "A summary on Sunday evening"
              color: overlay.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }
            ToggleSwitch {
              checked: overlay.hourglass ? overlay.hourglass.weeklySummary : true
              foreground: overlay.ink
              accent: overlay.accent
              onToggled: overlay.hourglass.save({ weeklySummary: !overlay.hourglass.weeklySummary })
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "Only which app was in front and for how long is kept, on this laptop: never window titles, never pages."
            color: overlay.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: overlay.hourglass !== null && overlay.hourglass.message !== ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: overlay.hourglass ? overlay.hourglass.message : ""
            color: Commons.Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
