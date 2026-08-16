import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "sendblue.events"

  property bool popupOpen: false
  property bool connected: false
  property bool streamStarted: false
  property int unreadCount: 0
  property string lastError: ""
  property string lastEventAt: ""
  property var activity: []
  property var lines: ({})

  readonly property var lineRows: Model.lineRows(lines)
  readonly property bool hasLineProblem: Model.hasLineProblem(lines)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string cliPath: String(setting("cliPath", "sendblue"))
  readonly property bool notificationsEnabled: String(setting("notifications", "On")) === "On"
  readonly property int maxActivity: intSetting("maxActivity", 30, 5, 100)
  readonly property bool opened: popupOpen

  implicitWidth: barSize + ((unreadCount > 0 && !(bar && bar.vertical)) ? Style.space(18) : 0)
  implicitHeight: barSize

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, value))
  }

  function open() { popupOpen = true; unreadCount = 0 }
  function close() { popupOpen = false }
  function toggle() { if (popupOpen) close(); else open() }

  function restart() {
    eventProcess.running = false
    restartTimer.restart()
  }

  function handleOutput(raw) {
    var event = Model.parseEvent(raw)
    if (!event) return
    if (event.type === "stream.connected") {
      connected = true
      streamStarted = true
      lastError = ""
      return
    }
    if (event.type === "stream.disconnected") {
      connected = false
      streamStarted = true
      lastError = String(event.data && event.data.error || "Disconnected")
      return
    }
    if (event.type === "lines.snapshot") {
      connected = true
      streamStarted = true
      lastEventAt = String(event.occurred_at || "")
      lines = Model.replaceLines(event.data)
      return
    }

    connected = true
    streamStarted = true
    lastEventAt = String(event.occurred_at || "")
    activity = Model.prependActivity(activity, event, maxActivity)
    if (String(event.type).indexOf("line.") === 0) lines = Model.upsertLine(lines, event)

    if (event.type === "message.received") {
      if (!popupOpen) unreadCount += 1
      if (notificationsEnabled && event.recovered !== true) {
        Quickshell.execDetached([
          "notify-send",
          "--app-name=Sendblue",
          "--icon=mail-message-new",
          "Sendblue message",
          Model.eventDetail(event)
        ])
      }
    }
  }

  onCliPathChanged: restart()
  onMaxActivityChanged: if (activity.length > maxActivity) activity = activity.slice(0, maxActivity)
  Component.onCompleted: eventProcess.running = true

  Process {
    id: eventProcess
    command: [root.cliPath, "events", "--jsonl", "--include-control"]
    stdout: SplitParser { onRead: function(line) { root.handleOutput(line) } }
    stderr: SplitParser {
      onRead: function(line) {
        var message = Model.stripAnsi(line)
        if (message) root.lastError = message
      }
    }
    onExited: function(exitCode) {
      root.connected = false
      root.streamStarted = true
      if (!root.lastError) root.lastError = "Sendblue CLI exited (" + exitCode + ")"
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 30000
    repeat: false
    onTriggered: if (!eventProcess.running) eventProcess.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.hasLineProblem
      ? "Sendblue line needs attention"
      : (root.connected ? (root.unreadCount ? root.unreadCount + " unread Sendblue message(s)" : "Sendblue connected") : (root.lastError || "Sendblue disconnected"))
    iconComponent: Component {
      Row {
        id: statusRow
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          text: "󰍡"
          color: root.hasLineProblem ? root.urgent : (root.connected ? root.foreground : root.dim)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.icon
        }

        Text {
          visible: root.unreadCount > 0 && !(root.bar && root.bar.vertical)
          text: String(root.unreadCount > 99 ? "99+" : root.unreadCount)
          color: root.hasLineProblem ? root.urgent : root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
    onPressed: function(code) {
      if (code === Qt.RightButton && root.bar) root.bar.run("uwsm-app -- xdg-terminal-exec sendblue messages")
      else if (code === Qt.MiddleButton) root.restart()
      else root.toggle()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(390))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(520))

    Flickable {
      id: popupScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: content
        width: popupScroll.width
        spacing: Style.space(12)

        Row {
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "󰍡"
            color: root.hasLineProblem ? root.urgent : root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
          }

          Column {
            width: parent.width - Style.space(64)
            spacing: Style.space(2)
            Text {
              text: "Sendblue"
              color: root.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: root.connected ? "Live event stream connected" : (root.lastError || "Connecting…")
              color: root.connected ? root.dim : root.urgent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: root.lineRows.length > 0
          PanelSectionHeader { text: "LINES"; foreground: root.foreground; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family }
          Repeater {
            model: root.lineRows
            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(8)
              Text {
                text: modelData.status === "ONLINE" ? "●" : (modelData.status === "DEGRADED" ? "◐" : "○")
                color: ["OFFLINE", "DEGRADED", "BLOCKED"].indexOf(modelData.status) !== -1 ? root.urgent : root.foreground
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width - Style.space(80)
                text: modelData.number || modelData.workerId
                color: root.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }
              Text {
                text: modelData.status
                color: ["OFFLINE", "DEGRADED", "BLOCKED"].indexOf(modelData.status) !== -1 ? root.urgent : root.dim
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        PanelSeparator { visible: root.lineRows.length > 0; foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(7)
          PanelSectionHeader { text: "ACTIVITY"; foreground: root.foreground; fontFamily: root.bar ? root.bar.fontFamily : Style.font.family }
          Text {
            visible: root.activity.length === 0
            width: parent.width
            text: root.connected ? "Waiting for account activity…" : "Connect the Sendblue CLI to begin."
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }
          Repeater {
            model: root.activity.slice(0, 10)
            Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(1)
              Row {
                width: parent.width
                Text {
                  width: parent.width - timestamp.width - Style.space(8)
                  text: modelData.title
                  color: root.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  id: timestamp
                  text: Qt.formatTime(new Date(modelData.occurredAt), "HH:mm")
                  color: root.dim
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }
              Text {
                width: parent.width
                text: modelData.detail + (modelData.recovered ? " · recovered" : "")
                color: root.dim
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }
}
