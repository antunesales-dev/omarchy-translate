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
  property bool translateQueued: false

  readonly property int boxHeight: Style.space(200)
  readonly property int scrollGutter: 12
  readonly property string clipPath: "/tmp/omarchy-translate-clip.txt"
  readonly property string inPath: "/tmp/omarchy-translate-in.txt"
  readonly property string outPath: "/tmp/omarchy-translate-out.json"
  readonly property string helperPath: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    if (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url) + "/bin/omarchy-translate"
  }
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color selectionTint: Style.selectionFillFor(fg, accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int charCount: String(sourceBox.text || "").length

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

  function pasteCommand(primary) {
    var flag = primary ? " --primary" : ""
    return ["bash", "-c", "wl-paste --no-newline" + flag + " > " + root.clipPath]
  }

  function ingestSelection() {
    root.ingesting = true
    root.triedPrimary = false
    paste.command = root.pasteCommand(root.grab === "primary" || root.grab === "auto")
    paste.running = true
  }

  function onPasted(raw) {
    var text = String(raw || "").replace(/\s+$/, "")
    if (!text && root.grab === "auto" && !root.triedPrimary) {
      root.triedPrimary = true
      paste.command = root.pasteCommand(false)
      paste.running = true
      return
    }
    root.ingesting = false
    if (!text) {
      sourceBox.editor.forceActiveFocus()
      return
    }
    if (sourceBox.text === text && root.resultText !== "") return
    sourceBox.text = text
    sourceBox.resetScroll()
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
    var incoming = root.resultText
    root.sourceLang = dst
    root.targetLang = src
    sourceDropdown.value = dst
    targetDropdown.value = src
    root.detectedSrc = ""
    root.persistSettings({ sourceLang: dst, targetLang: src })
    if (incoming && incoming.length) {
      sourceBox.text = incoming
      sourceBox.resetScroll()
    }
    debounce.restart()
  }

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
    var text = sourceBox.text
    if (!text || !String(text).trim()) {
      resultText = ""
      detectedSrc = ""
      errorText = ""
      busy = false
      return
    }
    busy = true
    errorText = ""
    root.translateQueued = true
    sourceFile.setText(String(text).trim() + "\n")
    helperFallback.restart()
  }

  function startHelper() {
    if (!root.translateQueued) return
    root.translateQueued = false
    translator.command = root.helperCommand()
    translator.running = true
  }

  function onTranslation(raw) {
    busy = false
    if (!sourceBox.text) return
    try {
      var payload = JSON.parse(raw)
      resultText = payload.text || ""
      if (root.sourceLang === "auto") detectedSrc = payload.src || payload.detected || ""
      errorText = ""
      resultBox.resetScroll()
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
    sourceBox.text = ""
    resultText = ""
    detectedSrc = ""
    errorText = ""
    sourceBox.resetScroll()
    resultBox.resetScroll()
    debounce.stop()
    sourceBox.editor.forceActiveFocus()
  }

  component ScrollField: Item {
    id: field
    property alias text: editor.text
    property alias readOnly: editor.readOnly
    property alias editor: editor
    property string placeholder: ""
    property bool activeLooks: editor.activeFocus

    function resetScroll() {
      flick.contentY = 0
    }

    function scrollBy(dy) {
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + dy))
    }

    width: parent.width
    height: root.boxHeight

    HoverHandler {
      id: hover
    }

    BorderSurface {
      anchors.fill: parent
      color: Style.controlFill(editor.activeFocus, hover.hovered, root.fg, root.accent)
      borderSpec: editor._borderSpec
      radius: Style.cornerRadius
    }

    Flickable {
      id: flick
      anchors.fill: parent
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      contentWidth: width
      contentHeight: Math.max(height, editor.contentHeight + editor.topPadding + editor.bottomPadding)
      interactive: contentHeight > height

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8
          field.scrollBy(-dy)
          event.accepted = true
        }
      }

      TextEdit {
        id: editor
        width: Math.max(1, flick.width - root.scrollGutter)
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

        readonly property var _borderSpec: Border.controlSpec(activeFocus ? "focus" : (hover.hovered ? "hover-cursor" : "normal"), root.fg, root.accent)

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_PageDown) {
            field.scrollBy(flick.height * 0.85)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            field.scrollBy(-flick.height * 0.85)
            event.accepted = true
          } else if (event.key === Qt.Key_Home && (event.modifiers & Qt.ControlModifier)) {
            flick.contentY = 0
            event.accepted = true
          } else if (event.key === Qt.Key_End && (event.modifiers & Qt.ControlModifier)) {
            field.scrollBy(flick.contentHeight)
            event.accepted = true
          }
        }
      }

      Text {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: parent.right
        leftPadding: editor.leftPadding
        rightPadding: editor.rightPadding
        topPadding: editor.topPadding
        text: field.placeholder
        color: Qt.darker(root.fg, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        visible: editor.text.length === 0
      }

      ScrollBar.vertical: ScrollBar {
        policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: sourceBox.editor
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    Item {
      anchors.fill: parent
      Keys.onEscapePressed: root.close()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Tab) {
          root.switchPanel(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
          root.copyResultToClipboard()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return && (event.modifiers & Qt.ControlModifier)) {
          root.translate()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
          root.clearAll()
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
              if (value !== "auto") sourceBox.editor.forceActiveFocus()
              debounce.restart()
            }
          }

          Button {
            id: swapButton
            width: Style.space(34)
            iconText: "󰓡"
            iconSize: Style.font.title
            tooltipText: "Swap languages and text"
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

        TextField {
          width: parent.width
          visible: root.engine === "libretranslate"
          height: visible ? implicitHeight : 0
          text: root.libretranslateUrl
          placeholderText: "LibreTranslate URL"
          foreground: root.fg
          font.family: root.fontFamily
          onEditingFinished: root.persistSettings({ libretranslateUrl: text })
        }

        Text {
          width: parent.width
          text: "Original"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        ScrollField {
          id: sourceBox
          placeholder: "Select text and press the keybind, or type here…"
          onTextChanged: {
            root.sourceText = text
            if (!root.ingesting) debounce.restart()
          }
        }

        Text {
          width: parent.width
          text: "Translation"
          color: Qt.darker(root.fg, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        ScrollField {
          id: resultBox
          readOnly: true
          text: root.resultText
          placeholder: root.errorText !== "" ? root.errorText : "Translation…"
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
            tooltipText: "Clear (Ctrl+Shift+L)"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: (sourceBox.text !== "" || resultBox.text !== "") && !root.busy
            opacity: enabled ? 1 : 0.4
            onClicked: root.clearAll()
          }

          Text {
            anchors.left: clearButton.right
            anchors.leftMargin: Style.space(8)
            anchors.right: copyButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? "Translating…" : (root.charCount > 0 ? (root.charCount + " chars") : "")
            color: root.busy ? root.accent : Qt.darker(root.fg, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: copyButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            iconText: root.copied ? "󰄬" : "󰆏"
            iconSize: Style.font.body
            tooltipText: root.copied ? "Copied!" : "Copy translation (Ctrl+Shift+C)"
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
    id: helperFallback
    interval: 150
    onTriggered: root.startHelper()
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
    onSaved: root.startHelper()
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
