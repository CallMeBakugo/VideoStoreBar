import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Ui as Ui

Panel {
  id: root
  moduleName: "bakugo.videostorebar"
  ipcTarget: "bakugo.videostorebar"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stateDir: Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")

  property var state: null
  readonly property bool downloading: !!state && state.state === "downloading"
  readonly property real pct: Math.max(0, Math.min(100, Number(state?.pct) || 0))
  readonly property string lastStatus: ["completed", "cancelled", "failed"].includes(state?.last) ? state.last : "none"

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property string daemonPath: decodeURIComponent(String(Qt.resolvedUrl("vsb-daemon")).replace(/^file:\/\//, ""))
  property string startError: ""
  property bool settingsOpen: false

  function open() {
    settingsOpen = false
    startError = ""
    controller.show()
  }

  function close() {
    settingsOpen = false
    controller.hide()
  }

  function toggleSettings() {
    controller.hide()
    settingsOpen = !settingsOpen
    if (settingsOpen) settingsFile.reload()
  }

  function go() {
    startError = ""
    if (!startProcess.running) startProcess.running = true
  }

  function cancelDownload() {
    Quickshell.execDetached([daemonPath, "cancel"])
  }

  function refreshStatus() {
    if (!statusProbe.running) statusProbe.running = true
  }

  Component.onCompleted: refreshStatus()
  onOpenedChanged: if (opened) refreshStatus()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProbe
    command: [root.daemonPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.parseState(text)
    }
  }

  Process {
    id: startProcess
    command: [root.daemonPath, "start"]
    stdout: StdioCollector { id: startOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        const result = JSON.parse(startOutput.text)
        if (exitCode === 0 && result.started === true) {
          stateFile.reload()
          root.close()
          return
        }
        root.startError = String(result.error || "Could not start the download.")
      } catch (error) {
        root.startError = "Could not start the download."
      }
    }
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/videostorebar/state.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.state = null
  }

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.state = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.state = null
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function settings(): void { if (!root.settingsOpen) root.toggleSettings() }
    function refresh(): string { root.refreshStatus(); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    hasVisualContent: true
    labelVisible: false
    fixedWidth: vertical ? -1 : Math.max(Style.bar.iconSlot, chip.width + 4)
    fixedHeight: vertical ? Style.bar.iconSlot : -1
    tooltipText: "VideoStore · " + (root.downloading ? Math.round(root.pct) + "%" : "Last download: " + root.lastStatus)
      + "\nLeft click: paste link · Right click: settings"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.toggleSettings()
      else if (mouseButton === Qt.LeftButton) root.toggle()
    }

    BorderSurface {
      id: chip
      anchors.centerIn: parent
      width: root.downloading && !button.vertical ? 70 : Math.max(height, chipLabel.implicitWidth + 10)
      height: Style.bar.iconSize
      radius: height / 2
      scale: button.pressScale
      color: root.alpha(root.foreground, 0.08)
      borderSpec: Border.flat(root.alpha(root.downloading ? root.urgent : root.foreground, 0.58), 1)

      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: root.downloading
        width: (parent.width - 6) * root.pct / 100
        height: parent.height - 6
        radius: height / 2
        color: root.alpha(root.urgent, 0.33)

        Behavior on width {
          NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutQuad }
        }
      }

      Text {
        id: chipLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.downloading ? Math.round(root.pct) + "%" : "VSB"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 12
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }

  // ---- click panel: paste / cancel -------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshStatus()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "VideoStore"
            meta: root.downloading ? "DOWNLOADING " + Math.round(root.pct) + "%" : "Ready"
            detail: ""
            foreground: root.downloading ? root.urgent : root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                BorderSurface {
                  anchors.fill: parent
                  radius: Math.min(Style.cornerRadius, height / 2)
                  color: root.alpha(root.foreground, 0.06)
                  borderSpec: Border.flat(root.alpha(root.foreground, 0.35), 1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "\u25B6"
                    color: root.downloading ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(Style.font.display * 0.62)
                  }
                }
              }
            }
          }

          // ---------- Paste / Cancel ----------
          PanelSectionHeader {
            width: parent.width
            text: "GRAB"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          WidgetButton {
            width: parent.width
            bar: root.bar
            text: startProcess.running ? "Reading clipboard…" : "Paste link"
            visible: !root.downloading
            enabled: !startProcess.running
            foreground: root.downloading ? root.dim : root.foreground
            active: false
            fontSize: Style.font.body
            horizontalMargin: 12
            verticalPadding: 8
            onPressed: function() { root.go() }
          }

          WidgetButton {
            width: parent.width
            bar: root.bar
            text: "Cancel download"
            visible: root.downloading
            foreground: root.downloading ? root.urgent : root.dim
            active: false
            fontSize: Style.font.body
            horizontalMargin: 12
            verticalPadding: 8
            onPressed: function() {
              root.cancelDownload()
              root.close()
            }
          }

          Text {
            width: parent.width
            visible: root.startError !== ""
            textFormat: Text.PlainText
            text: root.startError
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---------- Last result ----------
          PanelSeparator { foreground: root.foreground }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Last download: " + (root.downloading ? "in progress" : root.lastStatus)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }
  }

  // ---- settings panel (right-click) ------------------------------------------

  property var settingsJson: null

  FileView {
    id: settingsFile
    path: root.stateDir + "/videostorebar/settings.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.settingsJson = JSON.parse(text())
      } catch (e) {
        root.settingsJson = null
      }
    }
    onLoadFailed: root.settingsJson = null
  }

  KeyboardPanel {
    id: settingsPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.settingsOpen
    focusTarget: settingsKeyCatcher
    contentWidth: settingsPanel.fittedContentWidth(Style.space(360))
    contentHeight: settingsPanel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: settingsKeyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()

      Flickable {
        id: settingsFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "VideoStore Settings"
            meta: "FORMAT & FOLDER"
            detail: ""
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                BorderSurface {
                  anchors.fill: parent
                  radius: Math.min(Style.cornerRadius, height / 2)
                  color: root.alpha(root.foreground, 0.06)
                  borderSpec: Border.flat(root.alpha(root.foreground, 0.35), 1)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "\u2699"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(Style.font.display * 0.62)
                  }
                }
              }
            }
          }

          PanelSectionHeader {
            width: parent.width
            text: "FORMAT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: [
              ["Best video+audio", "label_best"],
              ["Best ≤1080p", "label_1080"],
              ["Best ≤720p", "label_720"],
              ["Audio only (mp3)", "label_audio_mp3"],
              ["Audio only (best)", "label_audio_best"]
            ]

            WidgetButton {
              id: fmtBtn
              required property var modelData
              readonly property bool chosen: (root.settingsJson?.format || "label_best") === modelData[1]
              width: parent.width
              bar: root.bar
              keepSpace: true
              text: (chosen ? "\u2713 " : "    ") + modelData[0]
              foreground: chosen ? root.urgent : root.foreground
              active: chosen
              fontSize: Style.font.caption
              horizontalMargin: 12
              verticalPadding: 8
              onPressed: function() {
                Quickshell.execDetached([
                  root.daemonPath, "set",
                  "format=" + modelData[1]
                ])
                root.settingsOpen = false
              }

              // highlighted box around the chosen row — a border + tint
              BorderSurface {
                z: -1
                anchors.fill: parent
                anchors.margins: -Style.space(3)
                radius: Math.min(Style.cornerRadius, height / 2)
                visible: fmtBtn.chosen
                color: root.alpha(root.urgent, 0.12)
                borderSpec: Border.flat(root.urgent, 1)
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "DOWNLOAD FOLDER"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Ui.TextField {
            id: outdirField
            width: parent.width
            foreground: root.foreground
            accent: root.urgent
            placeholderText: "~/Downloads"
            text: root.settingsJson?.outdir || "~/Downloads"
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            onAccepted: apply()

            function apply() {
              var path = text.trim()
              if (path === "") return
              Quickshell.execDetached([
                root.daemonPath, "set",
                "outdir=" + path
              ])
              root.settingsOpen = false
            }
          }

          WidgetButton {
            width: parent.width
            bar: root.bar
            keepSpace: true
            text: "Save folder"
            active: true
            fontSize: Style.font.caption
            horizontalMargin: 12
            verticalPadding: 7
            onPressed: function() { outdirField.apply() }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Defaults to ~/Downloads — the box above shows the current folder; type a new path and press Enter or Save."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }
      }
    }
  }
}