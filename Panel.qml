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
    var seen = {}
    var out = [{ label: "System language", value: "auto" }]
    var recents = root.recentTargets || []
    for (var r = 0; r < recents.length; r++) {
      for (var i = 0; i < root.languages.length; i++) {
        if (root.languages[i].value === recents[r] && recents[r] !== "auto") {
          out.push({ label: "★ " + root.languages[i].label, value: recents[r] })
          seen[recents[r]] = true
        }
      }
    }
    for (var j = 0; j < root.languages.length; j++)
      if (root.languages[j].value !== "auto" && !seen[root.languages[j].value])
        out.push(root.languages[j])
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
  property string definitionText: ""
  property bool skipped: false
  property bool fromCache: false
  property bool busy: false
  property bool copied: false
  property bool ingesting: false
  property bool triedPrimary: false
  property bool translateQueued: false
  property bool speakQueued: false
  property string speakLang: "en"
  property bool pairPinned: root.setting("pairPinned", false) === true || root.setting("pairPinned", false) === "true"
  property bool watchClipboard: root.setting("watchClipboard", false) === true || root.setting("watchClipboard", false) === "true"
  property bool historyOpen: false
  property var recentTargets: []
  property var historyItems: []

  readonly property int boxHeight: Style.space(200)
  readonly property int scrollGutter: 12
  readonly property string clipPath: "/tmp/omarchy-translate-clip.txt"
  readonly property string inPath: "/tmp/omarchy-translate-in.txt"
  readonly property string outPath: "/tmp/omarchy-translate-out.json"
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    if (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url)
  }
  readonly property string helperPath: root.pluginDir + "/bin/omarchy-translate"
  readonly property string historyPath: {
    var home = Quickshell.env("HOME") || ""
    return home + "/.config/omarchy-translate/history.json"
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
    pairPinned = root.setting("pairPinned", false) === true || root.setting("pairPinned", false) === "true"
    watchClipboard = root.setting("watchClipboard", false) === true || root.setting("watchClipboard", false) === "true"
    try { root.recentTargets = JSON.parse(root.setting("recentTargets", "[]")) } catch (e) { root.recentTargets = [] }
    sourceDropdown.value = sourceLang
    targetDropdown.value = targetLang
    engineDropdown.value = engine
  }

  function rememberTarget(code) {
    if (!code || code === "auto") return
    var next = [code]
    var recents = root.recentTargets || []
    for (var i = 0; i < recents.length; i++)
      if (recents[i] !== code) next.push(recents[i])
    root.recentTargets = next.slice(0, 5)
    root.persistSettings({ recentTargets: JSON.stringify(root.recentTargets) })
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
      definitionText = ""
      skipped = false
      fromCache = false
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
    if (root.speakQueued) {
      root.speakQueued = false
      speakProc.command = [root.helperPath, "speak", "--from", root.speakLang, "--file", root.inPath]
      speakProc.running = true
      return
    }
    if (!root.translateQueued) return
    root.translateQueued = false
    translator.command = root.helperCommand()
    translator.running = true
  }

  function speak(which) {
    var text = which === "source" ? sourceBox.text : root.resultText
    var lang = which === "source" ? (root.detectedSrc || root.sourceLang) : root.targetLang
    if (!text || !String(text).trim()) return
    if (lang === "auto") lang = "en"
    root.speakLang = lang
    root.speakQueued = true
    sourceFile.setText(String(text).trim() + "\n")
    helperFallback.restart()
  }

  function pasteBack() {
    if (!root.resultText) return
    root.copyResultToClipboard()
    root.close()
    Quickshell.execDetached([root.pluginDir + "/bin/omarchy-translate-paste"])
  }

  function loadHistory(raw) {
    try {
      var data = JSON.parse(raw || "[]")
      root.historyItems = Array.isArray(data) ? data.slice(0, 20) : []
    } catch (e) {
      root.historyItems = []
    }
  }

  function loadDroppedFile(url) {
    var path = String(url || "").replace(/^file:\/\//, "")
    var lower = path.toLowerCase()
    if (lower.indexOf(".txt") < 0 && lower.indexOf(".srt") < 0) return
    dropFile.path = path
    dropFile.reload()
  }

  function installOcrLang(code) {
    Quickshell.execDetached([
      "xdg-terminal-exec",
      "-e",
      "bash",
      "-c",
      "omarchy pkg add tesseract-data-" + code + "; echo; echo Done. Press Enter.; read"
    ])
  }

  function restoreHistory(item) {
    if (!item) return
    sourceBox.text = item.source || ""
    root.resultText = item.text || ""
    sourceBox.resetScroll()
    resultBox.resetScroll()
    root.historyOpen = false
  }

  function onTranslation(raw) {
    busy = false
    if (!sourceBox.text) return
    try {
      var payload = JSON.parse(raw)
      resultText = payload.text || ""
      if (root.sourceLang === "auto") detectedSrc = payload.src || payload.detected || ""
      definitionText = payload.definition || ""
      skipped = payload.skipped === true
      fromCache = payload.cached === true
      errorText = ""
      resultBox.resetScroll()
      if (root.copyResult && !root.skipped) root.copyResultToClipboard()
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
    definitionText = ""
    skipped = false
    fromCache = false
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

    readonly property color boxFill: Style.controlFill(editor.activeFocus, hover.hovered, root.fg, root.accent)
    readonly property bool boxFillLight: boxFill.a > 0.4 && (0.2126 * boxFill.r + 0.7152 * boxFill.g + 0.0722 * boxFill.b) > 0.55
    readonly property color boxInk: boxFillLight ? "#000000" : root.fg

    BorderSurface {
      anchors.fill: parent
      color: field.boxFill
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
        color: field.boxInk
        selectionColor: root.selectionTint
        selectedTextColor: field.boxInk
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
        color: Qt.darker(field.boxInk, 1.6)
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

      DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) {
          if (drop.hasUrls && drop.urls.length)
            root.loadDroppedFile(String(drop.urls[0]))
        }
      }
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
          return
        }
        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
          root.pasteBack()
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
            width: (parent.width - swapButton.width - pinButton.width - Style.space(18)) * 0.5
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

          Button {
            id: pinButton
            width: Style.space(34)
            iconText: root.pairPinned ? "󰐃" : "󰤱"
            iconSize: Style.font.title
            tooltipText: root.pairPinned ? "Unpin language pair" : "Pin this language pair"
            foreground: root.pairPinned ? root.accent : root.fg
            fontFamily: root.fontFamily
            anchors.bottom: parent.bottom
            onClicked: {
              root.pairPinned = !root.pairPinned
              root.persistSettings({ pairPinned: root.pairPinned })
            }
          }

          Dropdown {
            id: targetDropdown
            width: (parent.width - swapButton.width - pinButton.width - Style.space(18)) * 0.5
            label: "To"
            options: root.targetLanguages
            foreground: root.fg
            fontFamily: root.fontFamily
            Component.onCompleted: value = root.targetLang
            onChanged: function(value) {
              root.targetLang = value
              root.persistSettings({ targetLang: value })
              root.rememberTarget(value)
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

        Row {
          width: parent.width
          spacing: Style.space(6)

          Button {
            width: Style.space(28)
            iconText: "󰆒"
            iconSize: Style.font.body
            tooltipText: "Paste translation into the focused app"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.resultText !== ""
            opacity: enabled ? 1 : 0.4
            onClicked: root.pasteBack()
          }
          Button {
            width: Style.space(28)
            iconText: "󰆏"
            iconSize: Style.font.body
            tooltipText: root.copyResult ? "Auto-copy on" : "Auto-copy off"
            foreground: root.copyResult ? root.accent : root.fg
            fontFamily: root.fontFamily
            onClicked: {
              root.copyResult = !root.copyResult
              root.persistSettings({ copyResult: root.copyResult })
            }
          }
          Button {
            width: Style.space(28)
            iconText: root.watchClipboard ? "󰈈" : "󰈉"
            iconSize: Style.font.body
            tooltipText: root.watchClipboard ? "Clipboard watch on" : "Clipboard watch off"
            foreground: root.watchClipboard ? root.accent : root.fg
            fontFamily: root.fontFamily
            onClicked: {
              root.watchClipboard = !root.watchClipboard
              root.persistSettings({ watchClipboard: root.watchClipboard })
            }
          }
          Button {
            width: Style.space(28)
            iconText: "󰋚"
            iconSize: Style.font.body
            tooltipText: "History"
            foreground: root.historyOpen ? root.accent : root.fg
            fontFamily: root.fontFamily
            onClicked: root.historyOpen = !root.historyOpen
          }
          Button {
            width: Style.space(28)
            iconText: "󰺯"
            iconSize: Style.font.body
            tooltipText: "Install Portuguese OCR language"
            foreground: root.fg
            fontFamily: root.fontFamily
            onClicked: root.installOcrLang("por")
          }
        }

        Item {
          width: parent.width
          height: Math.max(origLabel.implicitHeight, speakSource.implicitHeight)

          Text {
            id: origLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Original"
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: speakSource
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            iconText: "󰕾"
            iconSize: Style.font.body
            tooltipText: "Speak original"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: sourceBox.text !== ""
            opacity: enabled ? 1 : 0.4
            onClicked: root.speak("source")
          }
        }

        ScrollField {
          id: sourceBox
          placeholder: "Select text and press the keybind, or type here…"
          onTextChanged: {
            root.sourceText = text
            if (!root.ingesting) debounce.restart()
          }
        }

        Item {
          width: parent.width
          height: Math.max(transLabel.implicitHeight, speakResult.implicitHeight)

          Text {
            id: transLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.skipped ? ("Already " + (root.detectedSrc || "this language")) : (root.fromCache ? "Translation (cached)" : "Translation")
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: speakResult
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(28)
            iconText: "󰕾"
            iconSize: Style.font.body
            tooltipText: "Speak translation"
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.resultText !== ""
            opacity: enabled ? 1 : 0.4
            onClicked: root.speak("result")
          }
        }

        ScrollField {
          id: resultBox
          readOnly: true
          text: root.resultText
          placeholder: root.errorText !== "" ? root.errorText : "Translation…"
        }

        Text {
          width: parent.width
          visible: root.definitionText !== ""
          height: visible ? implicitHeight : 0
          text: root.definitionText
          color: Qt.darker(root.fg, 1.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
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

        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.historyOpen
          height: visible ? implicitHeight : 0

          Text {
            text: root.historyItems.length ? "Recent translations" : "No history yet"
            color: Qt.darker(root.fg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.historyItems

            Button {
              required property var modelData
              width: contentColumn.width
              text: String(modelData.source || "").replace(/\n/g, " ").slice(0, 48)
              tooltipText: String(modelData.text || "").slice(0, 200)
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.restoreHistory(modelData)
            }
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

  FileView {
    id: dropFile
    printErrors: false
    onLoaded: {
      sourceBox.text = text()
      sourceBox.resetScroll()
      root.translate()
    }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onFileChanged: reload()
  }

  Process {
    id: speakProc
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
