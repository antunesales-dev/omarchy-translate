import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string sourceText: ""
  property string resultText: ""
  property string errorText: ""
  property bool busy: false
  property int cursorX: 40
  property int cursorY: 40

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    if (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url)
  }
  readonly property string helperPath: root.pluginDir + "/bin/omarchy-translate"
  readonly property string runtimeDir: {
    var dir = Quickshell.env("XDG_RUNTIME_DIR")
    if (!dir)
      dir = (Quickshell.env("HOME") || "/tmp") + "/.cache"
    return dir + "/omarchy-translate"
  }
  readonly property string inPath: root.runtimeDir + "/in.txt"
  readonly property string outPath: root.runtimeDir + "/out.json"
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
    root.resultText = ""
    cursorProc.running = true
    pasteProc.running = true
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.antunesales-dev.translate")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function translateClipboard(text) {
    var cleaned = String(text || "").replace(/\s+$/, "")
    root.sourceText = cleaned
    if (!cleaned) {
      root.errorText = "Clipboard is empty"
      return
    }
    root.busy = true
    inFile.setText(cleaned + "\n")
    Qt.callLater(function() {
      helper.command = [
        "bash", "-c",
        "exec \"$1\" --json --file \"$2\" > \"$3\"",
        "omarchy-translate",
        root.helperPath,
        root.inPath,
        root.outPath
      ]
      helper.running = true
    })
  }

  IpcHandler {
    target: "io.github.antunesales-dev.translate-popup"

    function open(): void { root.open("{}") }
    function close(): void { root.dismiss() }
    function toggle(): void { root.toggle() }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-translate-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Style.space(360)
      height: col.implicitHeight + Style.space(24)
      x: Math.min(Math.max(8, root.cursorX), Math.max(8, panel.width - width - 8))
      y: Math.min(Math.max(8, root.cursorY), Math.max(8, panel.height - height - 8))
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius

      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.dismiss()
      }

      Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: root.sourceText !== "" ? root.sourceText : "No selection"
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          opacity: 0.7
        }

        Text {
          width: parent.width
          text: root.busy ? "Translating…" : (root.errorText !== "" ? root.errorText : (root.resultText !== "" ? root.resultText : ""))
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          maximumLineCount: 8
          elide: Text.ElideRight
        }

        Row {
          spacing: Style.space(6)

          Button {
            text: "Copy"
            foreground: root.foreground
            fontFamily: Style.font.menuFamily
            enabled: root.resultText !== ""
            onClicked: {
              Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.resultText) + " | wl-copy"])
              root.dismiss()
            }
          }
          Button {
            text: "Paste"
            foreground: root.foreground
            fontFamily: Style.font.menuFamily
            enabled: root.resultText !== ""
            onClicked: {
              Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.resultText) + " | wl-copy"])
              root.dismiss()
              Quickshell.execDetached([root.pluginDir + "/bin/omarchy-translate-paste"])
            }
          }
          Button {
            text: "Full"
            foreground: root.foreground
            fontFamily: Style.font.menuFamily
            onClicked: {
              root.dismiss()
              Quickshell.execDetached(["omarchy-shell", "shell", "summon", "io.github.antunesales-dev.translate", "{}"])
            }
          }
        }
      }

    }
  }

  Process {
    id: prepareDir
    command: [root.helperPath, "ensure-dir"]
    running: true
  }

  FileView {
    id: inFile
    path: root.inPath
    printErrors: false
  }

  FileView {
    id: outFile
    path: root.outPath
    printErrors: false
    onLoaded: {
      root.busy = false
      try {
        var payload = JSON.parse(text())
        root.resultText = payload.text || ""
      } catch (e) {
        root.errorText = "Translation failed"
      }
    }
  }

  Process {
    id: helper
    onExited: function(code) {
      if (code !== 0) {
        root.busy = false
        root.errorText = "Translation failed"
        return
      }
      outFile.reload()
    }
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.translateClipboard(String(text || ""))
    }
  }

  Process {
    id: cursorProc
    command: ["hyprctl", "cursorpos"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim().split(",")
        if (raw.length >= 2) {
          root.cursorX = parseInt(raw[0], 10) || 40
          root.cursorY = parseInt(raw[1], 10) || 40
        }
      }
    }
  }
}
