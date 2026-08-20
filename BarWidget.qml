import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.antunesales-dev.translate"

  property bool foreignHint: false
  readonly property bool watchClipboard: setting("watchClipboard", false) === true || setting("watchClipboard", false) === "true"
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    if (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url)
  }

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

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
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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

  Loader {
    id: overlayLoader
    active: true
    source: Qt.resolvedUrl("Overlay.qml")
    visible: false
    onLoaded: {
      if (!overlayLoader.item) return
      overlayLoader.item.shell = root.bar && root.bar.shell ? root.bar.shell : null
      overlayLoader.item.manifest = { id: root.moduleName }
    }
  }

  IpcHandler {
    target: "io.github.antunesales-dev.translate"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗊"
    tooltipText: root.foreignHint ? "Clipboard looks like another language — click to translate" : "Translate selection"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Rectangle {
      visible: root.foreignHint
      width: 7
      height: 7
      radius: 4
      color: root.bar ? root.bar.foreground : "#ffffff"
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 2
      anchors.topMargin: 2
    }
  }

  Process {
    id: clipWatch
    running: root.watchClipboard
    command: ["wl-paste", "--watch", "echo", "clip"]
    stdout: SplitParser {
      onRead: function(line) { detectProc.running = true }
    }
  }

  Process {
    id: detectProc
    command: [root.pluginDir + "/bin/omarchy-translate", "detect", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var payload = JSON.parse(String(text || "{}"))
          var detected = payload.detected || ""
          var systemLang = payload.system || "en"
          root.foreignHint = detected !== "" && detected !== systemLang
        } catch (e) {
          root.foreignHint = false
        }
      }
    }
  }
}
