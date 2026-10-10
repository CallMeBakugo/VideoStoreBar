import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// VideoStoreBar: paste-to-download video grabber chip. Left click: panel with
// a one-click "Paste" (reads clipboard via the vsb-daemon). Right click:
// refresh/restart the chip. While downloading, the chip becomes a progress
// bar. No names, no memory — last status only.
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
  readonly property real pct: state && state.pct ? Number(state.pct) : 0
  readonly property string lastStatus: state && state.last ? String(state.last) : "none"

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function go() {
    Quickshell.execDetached(["/home/bakugo/.local/bin/vsb-daemon", "start"])
  }

  function cancelDownload() {
    Quickshell.execDetached(["/home/bakugo/.local/bin/vsb-daemon", "cancel"])
  }

  onOpenedChanged: if (opened) {
    stateFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  visible: true
  implicitWidth: chipBackdrop.width
  implicitHeight: button.implicitHeight

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
    function settings(): void { settingsPanel.openState = true }
    function refresh(): string { stateFile.reload(); return "ok" }
  }

  // ---- bar chip: double-width; VSB idle, progress bar downloading -----------

  BorderSurface {
    id: chipBackdrop
    anchors.verticalCenter: parent.verticalCenter
    x: 0
    width: root.downloading ? Style.space(72) : Style.space(36)  // ~double width
    height: Style.space(18)
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.downloading ? root.alpha(root.urgent, 0.22) : root.alpha(root.foreground, 0.06)
    borderSpec: Border.flat(
      root.downloading ? root.urgent : root.alpha(root.foreground, 0.35), 1)

    // downloading: fill bar (button text sits on top via keepSpace)
    Rectangle {
      visible: root.downloading
      anchors.fill: parent
      anchors.margins: 4
      radius: height / 2
      color: root.alpha(root.foreground, 0.10)

      Rectangle {
        width: Math.max(height, parent.width * (root.pct / 100))
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        radius: height / 2
        color: root.urgent

        Behavior on width {
          NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: chipBackdrop
    bar: root.bar
    keepSpace: true
    text: root.downloading ? "" : "VSB"
    foreground: root.foreground
    active: false
    fontSize: Style.font.caption
    horizontalMargin: 7
    verticalPadding: 5
    tooltipText: {
      var tip = "Left click: paste download link\nRight click: settings"
      tip += "\nLast download: " + (root.downloading ? "in progress" : root.lastStatus)
      return tip
    }
    onPressed: function(buttonCode) {
      console.log("[VSB] chip pressed, button:", buttonCode)
      if (buttonCode === Qt.RightButton) settingsPanel.openState = true
      else root.toggle()
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
        if (t === "r" || t === "R") stateFile.reload()
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
            text: root.downloading ? "Downloading… (greyed)" : "Paste"
            enabled: !root.downloading
            foreground: root.downloading ? root.dim : root.foreground
            active: false
            fontSize: Style.font.body
            horizontalMargin: 12
            verticalPadding: 8
            onPressed: function() {
              root.go()
              root.close()
            }
          }

          WidgetButton {
            width: parent.width
            bar: root.bar
            text: root.downloading ? "Cancel" : "Cancel (greyed)"
            enabled: root.downloading
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

          // ---------- Settings hint ----------
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
    open: settingsPanel.openState
    property bool openState: false
    focusTarget: settingsKeyCatcher
    contentWidth: settingsPanel.fittedContentWidth(Style.space(360))
    contentHeight: settingsPanel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: settingsKeyCatcher
      anchors.fill: parent

      onCloseRequested: settingsPanel.openState = false
      onTextKey: function(t) {}

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
              readonly property bool chosen: root.settingsJson
                && root.settingsJson.format === modelData[1]
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
                  "/home/bakugo/.local/bin/vsb-daemon", "set",
                  "format=" + modelData[1]
                ])
                if (root.settingsJson) root.settingsJson.format = modelData[1]
                else root.settingsJson = { format: modelData[1], outdir: "" }
                settingsPanel.openState = false
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

          TextField {
            id: outdirField
            width: parent.width
            foreground: root.foreground
            accent: root.urgent
            placeholderText: "~/Downloads"
            text: root.settingsJson ? (root.settingsJson.outdir || "~/Downloads") : "~/Downloads"
            font.pixelSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            onAccepted: {
              outdirSave.apply()
            }

            function apply() {
              var path = text.trim()
              if (path === "") return
              Quickshell.execDetached([
                "/home/bakugo/.local/bin/vsb-daemon", "set",
                "outdir=" + path
              ])
              if (root.settingsJson) root.settingsJson.outdir = path
              else root.settingsJson = { format: "label_best", outdir: path }
              settingsPanel.openState = false
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