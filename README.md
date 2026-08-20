# Translate

![Translate preview](preview.png)

Translate selected or copied text from the Omarchy bar. The panel
auto-detects the source language and translates into the **system
language** (`LANG` / `LC_MESSAGES`).

This is a Quattro `bar-widget` plugin: one bar icon, one details panel.
It runs inside the existing `omarchy-shell` process.

License: [MIT](LICENSE).

## Install

```sh
omarchy plugin add https://github.com/antunesales-dev/omarchy-translate.git --enable
```

Install does **not** change Hyprland keybindings or other user config.
A keybind is optional; see Usage below.

## Usage

**With no text selected:** click the translate icon on the bar. The panel
opens empty so you can type. Translation updates as you type.

**With selected text:** copy it (`SUPER + C`, or the optional keybind
below), then open the panel. On open it reads the clipboard and
translates automatically.

- Pick source language (**Detect language** by default) and target
  (**System language** by default).
- Swap languages with the swap button.
- Change the engine in the panel. Preferences persist in `shell.json`.
- Copy the translation with the copy button. Press Escape to close.
- Long text scrolls in both boxes (mouse wheel, scrollbar, Page Up/Down).
- `Ctrl+Shift+C` copies the translation. `Ctrl+Enter` re-runs. `Ctrl+Shift+L` clears.

Optional keybind — add the contents of
[`extras/bindings.lua.example`](extras/bindings.lua.example) to
`~/.config/hypr/bindings.lua`. That copies the current selection, then
summons the panel (`SUPER + SHIFT + T`).

```sh
omarchy-shell shell summon io.github.antunesales-dev.translate '{}'
omarchy-shell shell hide io.github.antunesales-dev.translate
```

## Configure

```sh
omarchy bar move io.github.antunesales-dev.translate --section right
```

Panel settings persist in `~/.config/omarchy/shell.json`:

| Setting | Default | Meaning |
|---|---|---|
| `sourceLang` | `auto` | Detect the source language |
| `targetLang` | `auto` | System language (`en_US` → `en`) |
| `engine` | `google` | `google`, `mymemory`, or `libretranslate` |
| `grab` | `clipboard` | `clipboard`, `primary`, or `auto` |
| `copyResult` | `false` | Copy the translation as soon as it arrives |
| `libretranslateUrl` | `http://127.0.0.1:5000` | Used when `engine` is `libretranslate` |
| `libretranslateKey` | empty | Optional API key for hosted LibreTranslate |

## Engines

| Engine | What it is | Key | Sends text off-machine |
|---|---|---|---|
| **google** (default) | Unofficial free Google Translate endpoint (`translate.googleapis.com`, `client=gtx`) | No | Yes |
| **mymemory** | Free Translated.net API. Mix of translation memory and machine translation. About 5,000 characters/day without an email. | No | Yes |
| **libretranslate** | Open-source [LibreTranslate](https://github.com/LibreTranslate/LibreTranslate) / Argos Translate. Point `libretranslateUrl` at a local instance, or a public one plus `libretranslateKey`. | Optional | Only if the URL is remote |

## Dependencies

Already on a typical Omarchy install:

- Python 3.11+ (stdlib only; no pip packages)
- `wl-clipboard` (`wl-copy` / `wl-paste`)
- Network access, unless you run LibreTranslate locally

The helper is `bin/omarchy-translate`. It is invoked by the panel and also
works as a CLI:

```sh
bin/omarchy-translate --json --text "Olá mundo"
```

## Privacy

The plugin runs unsandboxed inside `omarchy-shell`, with your user
permissions. It does not start a second Quickshell process.

By default, the selected or typed text is sent to Google's translate
endpoint over HTTPS. Switch the engine to **LibreTranslate** on
`http://127.0.0.1:5000` to keep translation on your machine.

## Remove

```sh
omarchy plugin remove io.github.antunesales-dev.translate
```

That removes the plugin. It does not revert a keybind you added yourself.

## License

[MIT](LICENSE) © 2026 Tiago Sales
