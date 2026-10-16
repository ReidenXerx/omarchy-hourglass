import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "../code/DetailModel.js" as Detail

// The panel: the day or the week at the computer, by hour, by category and by app, how often you came back to it,
// and the limits you set. The same panel as the Omarchy edition, drawn with Plasma's own controls and colours.
// No text fields, so nothing here reads the clipboard.
PlasmaExtras.Representation {
  id: view

  required property var hourglass

  Layout.preferredWidth: Kirigami.Units.gridUnit * 24
  Layout.preferredHeight: Kirigami.Units.gridUnit * 32
  Layout.minimumWidth: Kirigami.Units.gridUnit * 18
  Layout.minimumHeight: Kirigami.Units.gridUnit * 14

  property string range: "today"
  property var expanded: ({})

  readonly property var r: view.hourglass.report
  readonly property bool week: view.range === "week"
  readonly property bool details: Plasmoid.configuration.details
  readonly property color ink: Kirigami.Theme.textColor
  readonly property color faint: Qt.rgba(ink.r, ink.g, ink.b, 0.65)
  readonly property color accent: Kirigami.Theme.highlightColor
  // Captions a step below the text Plasma uses for labels. Kirigami.Theme.smallFont cannot be used for this: in a
  // widget's popup it answers 12 pt at the root and 7 pt in a delegate (Plasma 6.8), so it is taken from a label.
  readonly property real smallPt: Math.max(7, Math.round(sizer.font.pointSize * 0.9))
  PlasmaComponents.Label { id: sizer; visible: false }

  readonly property int total: view.r ? (view.week ? view.r.week.total : view.hourglass.todaySeconds) : 0
  readonly property var categories: view.r ? (view.week ? view.r.week.categories : view.r.today.categories) : []
  readonly property var appList: view.r ? (view.week ? view.r.week.apps : view.r.today.apps) : []

  function toggleApp(app) {
    var next = Object.assign({}, view.expanded)
    next[app] = !next[app]
    view.expanded = next
  }

  // Sites seen in the details shown, for choosing which keep their pages.
  readonly property var sitesSeen: {
    var out = []
    var add = function (s) { if (s && out.indexOf(s) < 0 && out.length < 12) out.push(s) }
    var lists = view.r ? [view.r.today.apps, view.r.week.apps] : []
    for (var i = 0; i < lists.length; i++)
      for (var j = 0; j < lists[i].length; j++) {
        if (Detail.kind(lists[i][j].app) !== "browser") continue
        var det = lists[i][j].details || []
        for (var k = 0; k < det.length; k++)
          if (det[k].label !== "Other" && det[k].label !== "Other sites") add(det[k].label.split(": ")[0])
      }
    var chosen = view.hourglass.pageSites
    for (var c = 0; c < chosen.length; c++) add(chosen[c])
    return out
  }

  function toggleSite(site) {
    var list = view.hourglass.pageSites.slice()
    var at = list.indexOf(site)
    if (at >= 0) list.splice(at, 1); else list.push(site)
    view.hourglass.save("pageSites", list.join(", "))
  }

  // One colour per category, the same everywhere in the panel: the accent for the first, then neutral tints.
  function categoryColor(name) {
    var order = ["Development", "Web", "Social", "Games", "Entertainment", "Creativity", "Productivity", "Utilities", "Other"]
    var hues = [view.accent, "#6f9fd8", "#6fc795", "#ef8a7d", "#c792ea", "#e2c46a", "#7fd1c7", "#9aa1ad", "#6b717d"]
    var i = order.indexOf(name)
    return hues[i < 0 ? hues.length - 1 : i]
  }

  function clock(t) {
    var d = new Date(t * 1000)
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
  }

  readonly property string comparison: {
    if (!view.r) return ""
    if (view.week) {
      var prev = view.r.week.previous
      if (!prev) return view.r.week.pickups + " pick-ups this week"
      var c = Math.round(100 * (view.r.week.total - prev) / prev)
      return (c === 0 ? "The same as last week" : Math.abs(c) + "% " + (c > 0 ? "more" : "less") + " than last week") + " · " + view.r.week.pickups + " pick-ups"
    }
    var line = view.r.today.pickups + (view.r.today.pickups === 1 ? " pick-up" : " pick-ups")
    var avg = view.r.average
    if (avg) {
      var d = Math.round(100 * (view.total - avg) / avg)
      line = (d === 0 ? "Right on your daily average" : Math.abs(d) + "% " + (d > 0 ? "above" : "below") + " your daily average") + " · " + line
    }
    return line
  }

  component Heading: PlasmaComponents.Label {
    textFormat: Text.PlainText
    color: view.faint
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
    font.pointSize: view.smallPt
    Layout.topMargin: Kirigami.Units.smallSpacing
  }

  component Note: PlasmaComponents.Label {
    Layout.fillWidth: true
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: view.faint
    font.pointSize: view.smallPt
  }

  header: PlasmaExtras.PlasmoidHeading {
    RowLayout {
      anchors.fill: parent
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        PlasmaComponents.Label {
          visible: view.hourglass.recording
          textFormat: Text.PlainText
          text: view.week ? "This week" : "Today"
          color: view.faint
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 1
          font.pointSize: view.smallPt
        }
        Kirigami.Heading {
          textFormat: Text.PlainText
          level: 1
          text: !view.hourglass.recording ? "Not recording" : view.r ? view.hourglass.spell(view.total) : "Reading…"
        }
      }
      PlasmaComponents.TabBar {
        id: tabs
        Layout.alignment: Qt.AlignTop
        visible: view.hourglass.recording
        currentIndex: view.week ? 1 : 0
        PlasmaComponents.TabButton { text: "Today"; onClicked: view.range = "today" }
        PlasmaComponents.TabButton { text: "Week"; onClicked: view.range = "week" }
      }
    }
  }

  // ---------------------------------------------------------------- before the recorder runs
  ColumnLayout {
    anchors.centerIn: parent
    width: parent.width - Kirigami.Units.gridUnit * 2
    visible: !view.hourglass.recording
    spacing: Kirigami.Units.largeSpacing

    Kirigami.Icon {
      Layout.alignment: Qt.AlignHCenter
      source: "chronometer"
      implicitWidth: Kirigami.Units.iconSizes.huge
      implicitHeight: implicitWidth
    }
    PlasmaComponents.Label {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
      text: "Hourglass counts time with a small recorder that runs in your session. It keeps everything on this computer."
    }
    PlasmaComponents.Button {
      Layout.alignment: Qt.AlignHCenter
      icon.name: "media-record"
      text: "Start recording"
      onClicked: view.hourglass.startRecording()
    }
    Note {
      horizontalAlignment: Text.AlignHCenter
      visible: view.hourglass.message !== ""
      text: view.hourglass.message
    }
  }

  // ---------------------------------------------------------------- the report
  PlasmaComponents.ScrollView {
    id: scroller
    anchors.fill: parent
    visible: view.hourglass.recording
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    contentWidth: availableWidth

    ColumnLayout {
      id: content
      width: scroller.availableWidth
      spacing: Kirigami.Units.largeSpacing

      PlasmaComponents.Label {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: view.comparison
        color: view.faint
      }

      // ------------------------------------------------ by hour, or by day
      Canvas {
        id: chart
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 6
        readonly property var data: view.r
        readonly property bool weekView: view.week
        readonly property color ink: view.ink
        readonly property color bar: view.accent
        onDataChanged: requestPaint()
        onWeekViewChanged: requestPaint()
        onWidthChanged: requestPaint()
        onInkChanged: requestPaint()
        onBarChanged: requestPaint()

        onPaint: {
          var c = getContext("2d")
          c.reset()
          var d = chart.data
          var caption = Math.round(view.smallPt * 4 / 3)
          var bottom = caption + 6
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
          c.fillStyle = Qt.rgba(chart.ink.r, chart.ink.g, chart.ink.b, 0.6)
          c.font = caption + "px sans-serif"
          c.textAlign = chart.weekView ? "center" : "left"
          for (var k = 0; k < n; k++)
            if (labels[k]) c.fillText(labels[k], chart.weekView ? k * slot + slot / 2 : k * slot + 1, height - 3)
        }
      }

      // ------------------------------------------------ by category
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.smallSpacing * 2
        visible: view.categories.length > 0
        Row {
          anchors.fill: parent
          Repeater {
            model: view.categories
            delegate: Rectangle {
              required property var modelData
              width: view.total > 0 ? parent.width * Math.min(1, modelData.seconds / Math.max(1, view.categories.reduce(function (a, b) { return a + b.seconds }, 0))) : 0
              height: parent.height
              color: view.categoryColor(modelData.name)
            }
          }
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        Repeater {
          model: view.categories.slice(0, 6)
          delegate: PlasmaComponents.Label {
            required property var modelData
            textFormat: Text.PlainText
            text: modelData.name + " " + view.hourglass.spell(modelData.seconds)
            color: view.categoryColor(modelData.name)
            font.pointSize: view.smallPt
          }
        }
      }

      Kirigami.Separator { Layout.fillWidth: true }

      // ------------------------------------------------ by app
      Heading { text: "Most used" }

      Note {
        visible: view.appList.length === 0
        text: "Nothing yet. Time counts while an app is in front and you are at the keyboard."
      }

      Repeater {
        model: view.appList.slice(0, 8)
        delegate: ColumnLayout {
          id: appRow
          required property var modelData
          readonly property var details: modelData.details || []
          readonly property bool open: view.expanded[modelData.app] === true
          Layout.fillWidth: true
          spacing: Kirigami.Units.smallSpacing

          RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing
            Rectangle {
              implicitWidth: Kirigami.Units.smallSpacing * 2; implicitHeight: implicitWidth; radius: implicitWidth / 2
              color: view.categoryColor(appRow.modelData.category)
            }
            PlasmaComponents.Label {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: appRow.modelData.name
            }
            PlasmaComponents.Label {
              textFormat: Text.PlainText
              text: view.hourglass.spell(appRow.modelData.seconds)
            }
            // Kept in every row, unseen where there is nothing to show, so the times stay in one column.
            PlasmaComponents.ToolButton {
              enabled: appRow.details.length > 0
              opacity: enabled ? 1 : 0
              icon.name: appRow.open ? "arrow-up" : "arrow-down"
              display: QQC2.AbstractButton.IconOnly
              text: appRow.open ? "Hide what was done in " + appRow.modelData.name : "Show what was done in " + appRow.modelData.name
              onClicked: view.toggleApp(appRow.modelData.app)
              PlasmaComponents.ToolTip.text: text
              PlasmaComponents.ToolTip.visible: hovered
            }
          }

          Repeater {
            model: appRow.open ? appRow.details : []
            delegate: RowLayout {
              required property var modelData
              Layout.fillWidth: true
              Layout.leftMargin: Kirigami.Units.gridUnit
              PlasmaComponents.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: modelData.label
                color: view.faint
                font.pointSize: view.smallPt
              }
              PlasmaComponents.Label {
                textFormat: Text.PlainText
                text: view.hourglass.spell(modelData.seconds)
                color: view.faint
                font.pointSize: view.smallPt
              }
            }
          }
        }
      }

      Note {
        visible: !view.week && view.r !== null && view.r.today.pickups > 0
        text: {
          var t = view.r ? view.r.today : null
          if (!t) return ""
          var parts = []
          if (t.firstPickup) parts.push("First pick-up " + view.clock(t.firstPickup))
          if (t.busiestPickupHour !== null) parts.push("most pick-ups " + t.busiestPickupHour + ":00–" + (t.busiestPickupHour + 1) + ":00")
          if (t.longest && t.longest.seconds >= 600) parts.push("longest stretch " + view.hourglass.spell(t.longest.seconds) + " in " + (view.appList.filter(function (a) { return a.app === t.longest.app })[0] || { name: t.longest.app }).name)
          return parts.join(" · ")
        }
      }

      Kirigami.Separator { Layout.fillWidth: true }

      // ------------------------------------------------ limits
      Heading { text: "Daily limits" }

      Repeater {
        model: view.r ? view.r.limits : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Kirigami.Units.smallSpacing
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PlasmaComponents.Label {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: modelData.name + (modelData.kind === "cat" ? " (category)" : "")
            }
            PlasmaComponents.Label {
              textFormat: Text.PlainText
              text: view.hourglass.spell(modelData.used) + " of " + view.hourglass.spell(modelData.minutes * 60) + (modelData.left <= 0 ? ", used up" : "")
              color: modelData.left <= 300 ? Kirigami.Theme.negativeTextColor : view.faint
              font.pointSize: view.smallPt
            }
          }
          PlasmaComponents.ToolButton {
            text: "−"
            Accessible.name: "15 minutes less"
            PlasmaComponents.ToolTip.text: Accessible.name
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: view.hourglass.setLimit(modelData.kind, modelData.key, Math.max(5, modelData.minutes - 15))
          }
          PlasmaComponents.ToolButton {
            text: "+"
            Accessible.name: "15 minutes more"
            PlasmaComponents.ToolTip.text: Accessible.name
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: view.hourglass.setLimit(modelData.kind, modelData.key, modelData.minutes + 15)
          }
          PlasmaComponents.ToolButton {
            icon.name: "edit-delete"
            display: QQC2.AbstractButton.IconOnly
            text: "Remove the limit"
            PlasmaComponents.ToolTip.text: text
            PlasmaComponents.ToolTip.visible: hovered
            onClicked: view.hourglass.setLimit(modelData.kind, modelData.key, 0)
          }
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents.Button {
          readonly property string cls: view.hourglass.appNow
          readonly property var known: view.appList.filter(function (a) { return a.app === cls })[0]
          visible: cls !== "" && view.r !== null && view.r.limits.filter(function (x) { return x.kind === "app" && x.key === cls }).length === 0
          text: "Limit " + (known ? known.name : cls) + " to 1 h"
          onClicked: view.hourglass.setLimit("app", cls, 60)
        }
        Repeater {
          model: view.categories.filter(function (c) {
            return c.name !== "Other" && view.r && view.r.limits.filter(function (x) { return x.kind === "cat" && x.key === c.name }).length === 0
          }).slice(0, 3)
          delegate: PlasmaComponents.Button {
            required property var modelData
            text: "Limit " + modelData.name + " to 1 h"
            onClicked: view.hourglass.setLimit("cat", modelData.name, 60)
          }
        }
      }

      Note { text: "Limits send a notice five minutes before and when the time is up. They never close anything." }

      Kirigami.Separator { Layout.fillWidth: true }

      PlasmaComponents.Switch {
        Layout.fillWidth: true
        text: "A summary on Sunday evening"
        checked: Plasmoid.configuration.weeklySummary
        onToggled: view.hourglass.save("weeklySummary", checked)
      }

      PlasmaComponents.Switch {
        Layout.fillWidth: true
        text: "Remember what you did in each app"
        checked: view.details
        onToggled: view.hourglass.save("details", checked)
      }

      Note {
        visible: view.details && view.sitesSeen.length > 0
        text: "Keep the page, not just the site, for:"
      }

      Flow {
        Layout.fillWidth: true
        visible: view.details
        spacing: Kirigami.Units.smallSpacing
        Repeater {
          model: view.sitesSeen
          delegate: PlasmaComponents.Button {
            required property string modelData
            text: modelData
            checkable: true
            checked: view.hourglass.pageSites.indexOf(modelData) >= 0
            onClicked: view.toggleSite(modelData)
          }
        }
      }

      Flow {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing
        // Always here, so details can be switched off first and then forgotten.
        PlasmaComponents.Button {
          icon.name: "edit-clear-history"
          text: "Forget details"
          onClicked: view.hourglass.forgetDetails()
        }
        PlasmaComponents.Button {
          icon.name: "media-playback-stop"
          text: "Stop recording"
          onClicked: view.hourglass.stopRecording()
        }
      }

      Note {
        text: view.details
          ? "Details are short labels such as YouTube, a project in your editor or what runs in a terminal, never a window's title. Private windows and password managers are never described."
          : "Only which app was in front, for how long, and when you came back is kept, on this computer: never window titles, never pages."
      }

      Note {
        visible: view.hourglass.message !== ""
        text: view.hourglass.message
        color: Kirigami.Theme.negativeTextColor
      }
    }
  }
}
