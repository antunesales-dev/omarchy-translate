import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.antunesales-dev.translate"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var languages: [
    { label: "Detect language", value: "auto" },
    { label: "English", value: "en" },
    { label: "Portuguese", value: "pt" },
    { label: "Spanish", value: "es" },
    { label: "French", value: "fr" },
    { label: "German", value: "de" },
    { label: "Italian", value: "it" },
    { label: "Japanese", value: "ja" },
    { label: "Korean", value: "ko" },
    { label: "Chinese (Simplified)", value: "zh-CN" },
    { label: "Chinese (Traditional)", value: "zh-TW" },
    { label: "Russian", value: "ru" },
    { label: "Arabic", value: "ar" },
    { label: "Hindi", value: "hi" },
    { label: "Dutch", value: "nl" },
    { label: "Polish", value: "pl" },
    { label: "Ukrainian", value: "uk" },
    { label: "Turkish", value: "tr" },
    { label: "Indonesian", value: "id" },
    { label: "Czech", value: "cs" },
    { label: "Greek", value: "el" },
    { label: "Swedish", value: "sv" },
    { label: "Danish", value: "da" },
    { label: "Finnish", value: "fi" },
    { label: "Norwegian", value: "no" },
    { label: "Hebrew", value: "he" },
    { label: "Thai", value: "th" },
    { label: "Vietnamese", value: "vi" },
    { label: "Romanian", value: "ro" },
    { label: "Hungarian", value: "hu" },
    { label: "Catalan", value: "ca" },
    { label: "Galician", value: "gl" },
    { label: "Persian", value: "fa" },
    { label: "Urdu", value: "ur" },
    { label: "Bengali", value: "bn" },
    { label: "Filipino", value: "fil" },
    { label: "Malay", value: "ms" }
  ]

  readonly property var targetLanguages: {
    var out = [{ label: "System language", value: "auto" }]
    for (var i = 0; i < root.languages.length; i++)
      if (root.languages[i].value !== "auto") out.push(root.languages[i])
    return out
  }

  readonly property var engines: [
    { label: "Google", value: "google" },
    { label: "MyMemory", value: "mymemory" },
    { label: "LibreTranslate", value: "libretranslate" }
  ]

  property string sourceLang: root.setting("sourceLang", "auto")
  property string targetLang: root.setting("targetLang", "auto")
  property string engine: root.setting("engine", "google")
  property string grab: root.setting("grab", "clipboard")
  property bool copyResult: root.setting("copyResult", false) === true || root.setting("copyResult", false) === "true"
  property string libretranslateUrl: root.setting("libretranslateUrl", "http://127.0.0.1:5000")
  property string libretranslateKey: root.setting("libretranslateKey", "")
  property string sourceText: ""
  property string resultText: ""
  property string detectedSrc: ""
  property string errorText: ""
  property bool busy: false
  property bool copied: false
  property bool ingesting: false
  property bool triedPrimary: false

  onSettingsChanged: {
    sourceLang = root.setting("sourceLang", "auto")
    targetLang = root.setting("targetLang", "auto")
    engine = root.setting("engine", "google")
    grab = root.setting("grab", "clipboard")
    copyResult = root.setting("copyResult", false) === true || root.setting("copyResult", false) === "true"
    libretranslateUrl = root.setting("libretranslateUrl", "http://127.0.0.1:5000")
    libretranslateKey = root.setting("libretranslateKey", "")
    sourceDropdown.value = sourceLang
    targetDropdown.value = targetLang
    engineDropdown.value = engine
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    if (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url)
  }

  readonly property string helperPath: root.pluginDir + "/bin/omarchy-translate"
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color selectionTint: Style.selectionFillFor(fg, accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.controller.show()
    Qt.callLater(root.ingestSelection)
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  readonly property string clipPath: "/tmp/omarchy-translate-clip.txt"
  readonly property string inPath: "/tmp/omarchy-translate-in.txt"

  function ingestSelection() {
    root.ingesting = true
    root.triedPrimary = false
    if (root.grab === "primary" || root.grab === "auto")
      paste.command = ["bash", "-c", "wl-paste --no-newline --primary > " + root.clipPath]
    else
      paste.command = ["bash", "-c", "wl-paste --no-newline > " + root.clipPath]
    paste.running = true
  }

  function onPasted(raw) {
    var text = String(raw || "").replace(/\s+$/, "")
    if (!text && root.grab === "auto" && !root.triedPrimary) {
      root.triedPrimary = true
      paste.command = ["wl-paste", "--no-newline"]
      paste.running = true
      return
    }
    root.ingesting = false
    if (!text) {
      sourceEdit.forceActiveFocus()
      return
    }
    if (sourceEdit.text === text && root.resultText !== "") return
    sourceEdit.text = text
    root.translate()
  }

  function swapLanguages() {
    var src = root.sourceLang
    var dst = root.targetLang
    if (src === "auto") {
      if (root.detectedSrc === "") return
      src = root.detectedSrc
    }
    if (dst === "auto") return
    root.sourceLang = dst
    root.targetLang = src
    sourceDropdown.value = dst
    targetDropdown.value = src
    root.detectedSrc = ""
    root.persistSettings({ sourceLang: dst, targetLang: src })
    debounce.restart()
  }

  readonly property string outPath: "/tmp/omarchy-translate-out.json"

  function helperCommand() {
    var cmd = [
      "bash", "-c",
      "exec \"$1\" --json --engine \"$2\" --from \"$3\" --to \"$4\" --file \"$5\" > \"$6\"",
      "omarchy-translate",
      root.helperPath,
      root.engine,
      root.sourceLang,
      root.targetLang,
      root.inPath,
      root.outPath
    ]
    if (root.engine === "libretranslate") {
      cmd[2] = "exec \"$1\" --json --engine \"$2\" --from \"$3\" --to \"$4\" --file \"$5\" --libretranslate-url \"$7\" --libretranslate-key \"$8\" > \"$6\""
      cmd.push(root.libretranslateUrl)
      cmd.push(root.libretranslateKey)
    }
    return cmd
  }

  function translate() {
    var text = sourceEdit.text
    if (!text || !String(text).trim()) {
      resultText = ""
      detectedSrc = ""
      errorText = ""
      busy = false
      return
    }
    busy = true
    errorText = ""
    sourceFile.setText(String(text).trim() + "\n")
    Qt.callLater(function() {
      translator.command = root.helperCommand()
      translator.running = true
    })
  }

  function onTranslation(raw) {
    busy = false
    if (!sourceEdit.text) return
    try {
      var payload = JSON.parse(raw)
      resultText = payload.text || ""
      if (root.sourceLang === "auto") detectedSrc = payload.src || payload.detected || ""
      errorText = ""
      if (root.copyResult) root.copyResultToClipboard()
    } catch (e) {
      errorText = "Could not read the translation"
    }
  }

  function copyResultToClipboard() {
    if (!root.resultText) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(root.resultText) + " | wl-copy"])
    root.copied = true
    copyFeedback.restart()
  }

  function clearAll() {
    sourceEdit.text = ""
    resultText = ""
    detectedSrc = ""
    errorText = ""
    debounce.stop()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: sourceEdit
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    Item {
      anchors.fill: parent
      Keys.onEscapePressed: root.close()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab) {
          root.switchPanel(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          event.accepted = true
        }
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(6)

          Dropdown {
            id: sourceDropdown
            width: (parent.width - swapButton.width - Style.space(12)) * 0.5
            label: root.detectedSrc !== "" && root.sourceLang === "auto"
              ? ("From · " + root.detectedSrc)
              : "From"
            options: root.languages
            foreground: root.fg
            fontFamily: root.fontFamily
            Component.onCompleted: value = root.sourceLang
            onChanged: function(value) {
              root.sourceLang = value
              root.detectedSrc = ""
              root.persistSettings({ sourceLang: value })
              if (value !== "auto") sourceEdit.forceActiveFocus()
              debounce.restart()
            }
          }

          Button {
            id: swapButton
            width: Style.space(34)
            iconText: "󰓡"
            iconSize: Style.font.title
            tooltipText: "Swap languages"
            foreground: root.fg
            fontFamily: root.fontFamily
            anchors.bottom: parent.bottom
            onClicked: root.swapLanguages()
          }

          Dropdown {
            id: targetDropdown
            width: (parent.width - swapButton.width - Style.space(12)) * 0.5
            label: "To"
            options: root.targetLanguages
            foreground: root.fg
            fontFamily: root.fontFamily
            Component.onCompleted: value = root.targetLang
            onChanged: function(value) {
              root.targetLang = value
              root.persistSettings({ targetLang: value })
              debounce.restart()
            }
          }
        }

        Dropdown {
          id: engineDropdown
          width: parent.width
          label: "Engine"
          options: root.engines
          foreground: root.fg
          fontFamily: root.fontFamily
          Component.onCompleted: value = root.engine
          onChanged: function(value) {
            root.engine = value
            root.persistSettings({ engine: value })
            debounce.restart()
          }
        }

        Item {
          width: parent.width
          height: Style.space(120)

          HoverHandler {
            id: sourceHover
          }

          BorderSurface {
            anchors.fill: parent
            color: Style.controlFill(sourceEdit.activeFocus, sourceHover.hovered, root.fg, root.accent)
            borderSpec: sourceEdit._borderSpec
            radius: Style.cornerRadius
          }

          Flickable {
            id: sourceScroll
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: Math.max(height, sourceEdit.contentHeight + sourceEdit.topPadding + sourceEdit.bottomPadding)
            interactive: contentHeight > height

            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
                var maxY = Math.max(0, sourceScroll.contentHeight - sourceScroll.height)
                sourceScroll.contentY = Math.max(0, Math.min(maxY, sourceScroll.contentY - dy))
                event.accepted = true
              }
            }

            TextEdit {
              id: sourceEdit
              width: sourceScroll.width
              height: contentHeight + topPadding + bottomPadding
              color: root.fg
              selectionColor: root.selectionTint
              selectedTextColor: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              persistentSelection: true
              leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
              rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
              topPadding: Style.spacing.controlPaddingY + Border.top(_borderSpec)
              bottomPadding: Style.spacing.controlPaddingY + Border.bottom(_borderSpec)

              readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (sourceHover.hovered ? "hover-cursor" : "normal"), root.fg, root.accent)

              onTextChanged: {
                root.sourceText = text
                if (!root.ingesting) debounce.restart()
              }
            }

            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.right: parent.right
              leftPadding: sourceEdit.leftPadding
              rightPadding: sourceEdit.rightPadding
              topPadding: sourceEdit.topPadding
              text: "Select text and press the keybind, or type here…"
              color: Qt.darker(root.fg, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              visible: sourceEdit.text.length === 0
            }

            ScrollBar.vertical: ScrollBar {
              policy: sourceScroll.contentHeight > sourceScroll.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
              implicitWidth: 8
              contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.accent
                opacity: 0.7
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(120)

          BorderSurface {
            anchors.fill: parent
            color: Style.controlFill(false, false, root.fg, root.accent)
            borderSpec: resultEdit._borderSpec
            radius: Style.cornerRadius
          }

          Flickable {
            id: resultScroll
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            contentWidth: width
            contentHeight: Math.max(height, resultEdit.contentHeight + resultEdit.topPadding + resultEdit.bottomPadding)
            interactive: contentHeight > height

            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(event) {
                var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
                var maxY = Math.max(0, resultScroll.contentHeight - resultScroll.height)
                resultScroll.contentY = Math.max(0, Math.min(maxY, resultScroll.contentY - dy))
                event.accepted = true
              }
            }

            TextEdit {
              id: resultEdit
              width: resultScroll.width
              height: contentHeight + topPadding + bottomPadding
              readOnly: true
              text: root.resultText
              color: root.fg
              selectionColor: root.selectionTint
              selectedTextColor: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: TextEdit.Wrap
              selectByMouse: true
              persistentSelection: true
              leftPadding: Style.spacing.controlPaddingX + Border.left(_borderSpec)
              rightPadding: Style.spacing.controlPaddingX + Border.right(_borderSpec)
              topPadding: Style.spacing.controlPaddingY + Border.top(_borderSpec)
              bottomPadding: Style.spacing.controlPaddingY + Border.bottom(_borderSpec)

              readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : "normal", root.fg, root.accent)
            }

            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.right: parent.right
              leftPadding: resultEdit.leftPadding
              rightPadding: resultEdit.rightPadding
              topPadding: resultEdit.topPadding
              text: root.errorText !== "" ? root.errorText : "Translation…"
              color: Qt.darker(root.fg, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              visible: resultEdit.text.length === 0
            }

            ScrollBar.vertical: ScrollBar {
              policy: resultScroll.contentHeight > resultScroll.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
              implicitWidth: 8
              contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.accent
                opacity: 0.7
              }
            }
          }
        }

        Item {
          id: footer
          width: parent.width
          height: copyButton.implicitHeight

          Button {
            id: clearButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            iconText: "󰆴"
            iconSize: Style.font.body
            tooltipText: "Clear text"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: (sourceEdit.text !== "" || resultEdit.text !== "") && !root.busy
            opacity: enabled ? 1 : 0.4
            onClicked: root.clearAll()
          }

          Text {
            anchors.left: clearButton.right
            anchors.leftMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? "Translating…" : ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Button {
            id: copyButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            iconText: root.copied ? "󰄬" : "󰆏"
            iconSize: Style.font.body
            tooltipText: root.copied ? "Copied!" : "Copy translation"
            foreground: root.copied ? root.accent : root.fg
            fontFamily: root.fontFamily
            enabled: root.resultText !== "" && !root.busy
            opacity: enabled ? 1 : 0.4
            onClicked: root.copyResultToClipboard()
          }
        }
      }
    }
  }

  Timer {
    id: debounce
    interval: 600
    onTriggered: root.translate()
  }

  Timer {
    id: copyFeedback
    interval: 700
    onTriggered: root.copied = false
  }

  FileView {
    id: clipFile
    path: root.clipPath
    printErrors: false
    onLoaded: root.onPasted(text())
    onLoadFailed: function() {
      if (root.ingesting)
        root.onPasted("")
    }
  }

  FileView {
    id: sourceFile
    path: root.inPath
    printErrors: false
  }

  Process {
    id: paste
    onExited: function(code) {
      if (code !== 0 && root.ingesting && !(root.grab === "auto" && !root.triedPrimary)) {
        root.onPasted("")
        return
      }
      clipFile.reload()
    }
  }

  FileView {
    id: outFile
    path: root.outPath
    printErrors: false
    onLoaded: root.onTranslation(text())
    onLoadFailed: function() {
      if (root.busy) {
        root.busy = false
        root.errorText = "Translation failed"
      }
    }
  }

  Process {
    id: translator
    onExited: function(code) {
      if (code !== 0) {
        root.busy = false
        root.errorText = "Translation failed"
        return
      }
      outFile.reload()
    }
  }
}
