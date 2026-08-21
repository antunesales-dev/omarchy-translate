#!/usr/bin/env python3
"""Regression tests for the translate helper and the review findings."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import os
import re
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omarchy-translate"


def load_helper():
    name = "omarchy_translate_helper"
    if name in sys.modules:
        return sys.modules[name]
    loader = importlib.machinery.SourceFileLoader(name, str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    loader.exec_module(mod)
    return mod


class HelperMixin(unittest.TestCase):
    def setUp(self):
        self.mod = load_helper()
        self._tmpdir = tempfile.TemporaryDirectory()
        base = Path(self._tmpdir.name)
        self.mod.CONFIG_DIR = base
        self.mod.CONFIG_PATH = base / "config.toml"
        self.mod.HISTORY_PATH = base / "history.json"
        self.mod.CACHE_PATH = base / "cache.json"
        self.mod.GLOSSARY_PATH = base / "glossary.json"

    def tearDown(self):
        self._tmpdir.cleanup()


class SpeakSplitTests(HelperMixin):
    def test_split_utterances_keeps_sentences_under_limit(self):
        parts = self.mod.split_utterances("Hello there. How are you today? Fine.", 20)
        self.assertTrue(parts)
        self.assertTrue(all(len(p) <= 20 for p in parts))
        self.assertIn("Hello there.", parts)


class EngineOrderTests(HelperMixin):
    def test_libretranslate_never_includes_google_or_mymemory(self):
        cfg = self.mod.Config(engine="libretranslate", fallback=True)
        self.assertEqual(self.mod.engine_order(cfg), ["libretranslate"])

    def test_google_fallback_still_tries_other_engines(self):
        cfg = self.mod.Config(engine="google", fallback=True)
        self.assertEqual(self.mod.engine_order(cfg), ["google", "mymemory", "libretranslate"])

    def test_no_fallback_is_only_chosen_engine(self):
        cfg = self.mod.Config(engine="google", fallback=False)
        self.assertEqual(self.mod.engine_order(cfg), ["google"])


class KeyHandlingTests(HelperMixin):
    def test_env_key_wins_over_cli_flag(self):
        args = self.mod.parse_args(["--engine", "libretranslate", "--libretranslate-key", "cli-secret"])
        cfg = self.mod.Config()
        with patch.dict(os.environ, {"OMARCHY_TRANSLATE_LT_KEY": "env-secret"}):
            cfg = self.mod.apply_overrides(cfg, args)
        self.assertEqual(cfg.libretranslate_api_key, "env-secret")

    def test_cli_key_used_when_env_missing(self):
        args = self.mod.parse_args(["--libretranslate-key", "cli-secret"])
        cfg = self.mod.apply_overrides(self.mod.Config(), args)
        self.assertEqual(cfg.libretranslate_api_key, "cli-secret")

    def test_key_file_used_when_env_and_cli_missing(self):
        key = Path(self._tmpdir.name) / "omarchy-translate" / "lt.key"
        key.parent.mkdir(parents=True)
        key.write_text("file-secret\n", encoding="utf-8")
        args = self.mod.parse_args(["--engine", "libretranslate"])
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": self._tmpdir.name}):
            cfg = self.mod.apply_overrides(self.mod.Config(), args)
        self.assertEqual(cfg.libretranslate_api_key, "file-secret")


class LibreTranslateIsolationTests(HelperMixin):
    def test_lt_translate_failure_does_not_call_google(self):
        cfg = self.mod.Config(engine="libretranslate", fallback=True, target="en", source="pt")
        with (
            patch.object(self.mod, "translate_google") as google,
            patch.object(self.mod, "translate_mymemory") as mymemory,
            patch.object(self.mod, "translate_libretranslate", side_effect=RuntimeError("down")),
            patch.object(self.mod, "detect_language", return_value="pt"),
            patch.object(self.mod, "history_add"),
            patch.object(self.mod, "cache_get", return_value=None),
            patch.object(self.mod, "cache_put"),
        ):
            with self.assertRaises(RuntimeError):
                self.mod.translate_text(cfg, "O gato")
            google.assert_not_called()
            mymemory.assert_not_called()

    def test_lt_detect_does_not_call_google(self):
        cfg = self.mod.Config(engine="libretranslate")
        with (
            patch.object(self.mod, "detect_libretranslate", return_value="pt") as detect,
            patch.object(self.mod, "translate_google") as google,
            patch.object(self.mod, "translate_mymemory") as mymemory,
        ):
            self.assertEqual(self.mod.detect_language(cfg, "Olá mundo"), "pt")
            detect.assert_called_once()
            google.assert_not_called()
            mymemory.assert_not_called()

    def test_lt_detect_failure_does_not_fall_back_to_google(self):
        cfg = self.mod.Config(engine="libretranslate")
        with (
            patch.object(self.mod, "detect_libretranslate", side_effect=RuntimeError("down")),
            patch.object(self.mod, "translate_google") as google,
            patch.object(self.mod, "translate_mymemory") as mymemory,
        ):
            self.assertEqual(self.mod.detect_language(cfg, "Olá mundo"), "")
            google.assert_not_called()
            mymemory.assert_not_called()


class RedactAndSkipTests(HelperMixin):
    def test_github_token_is_redacted(self):
        text, mapping, used = self.mod.redact_secrets("token ghp_abcdefghijklmnopqrstuvwxyz123456 rest")
        self.assertTrue(used)
        self.assertNotIn("ghp_", text)
        self.assertTrue(any(v.startswith("ghp_") for v in mapping.values()))

    def test_email_and_url_are_redacted(self):
        text, mapping, used = self.mod.redact_secrets("see https://example.com and a@b.com")
        self.assertTrue(used)
        self.assertNotIn("example.com", text)
        self.assertNotIn("a@b.com", text)
        self.assertEqual(len(mapping), 2)

    def test_same_language_is_skipped_without_engines(self):
        cfg = self.mod.Config(engine="google", source="auto", target="en")
        with (
            patch.object(self.mod, "detect_language", return_value="en"),
            patch.object(self.mod, "translate_google") as google,
            patch.object(self.mod, "history_add"),
        ):
            result = self.mod.translate_text(cfg, "Hello there")
        self.assertTrue(result.skipped)
        self.assertEqual(result.engine, "skip")
        self.assertEqual(result.text, "Hello there")
        google.assert_not_called()

    def test_glossary_term_is_protected(self):
        protected, mapping = self.mod.protect_terms("I use Omarchy and Hyprland", ["Omarchy", "Hyprland"])
        self.assertNotIn("Omarchy", protected)
        self.assertNotIn("Hyprland", protected)
        restored = self.mod.restore_tokens(protected, mapping)
        self.assertEqual(restored, "I use Omarchy and Hyprland")


class PrivateFileTests(HelperMixin):
    def test_config_is_written_mode_600(self):
        self.mod.save_config(self.mod.Config(libretranslate_api_key="secret"))
        mode = stat.S_IMODE(self.mod.CONFIG_PATH.stat().st_mode)
        self.assertEqual(mode, 0o600)
        body = self.mod.CONFIG_PATH.read_text(encoding="utf-8")
        self.assertIn("secret", body)

    def test_runtime_dir_is_0700_and_not_world_tmp_file(self):
        with patch.dict(os.environ, {"XDG_RUNTIME_DIR": self._tmpdir.name}):
            path = self.mod.runtime_dir()
        self.assertEqual(path, Path(self._tmpdir.name) / "omarchy-translate")
        self.assertTrue(path.is_dir())
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)


class HttpLimitTests(HelperMixin):
    def test_read_limited_accepts_body_at_cap(self):
        cap = 16
        stream = io.BytesIO(b"a" * cap)
        self.assertEqual(len(self.mod.read_limited(stream, cap)), cap)

    def test_read_limited_rejects_body_over_cap(self):
        stream = io.BytesIO(b"a" * 32)
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.read_limited(stream, 16)
        self.assertIn("exceeded 16 bytes", str(ctx.exception))

    def test_read_limited_rejects_content_length_header(self):
        stream = io.BytesIO(b"ignored")
        stream.headers = {"Content-Length": "99999"}
        with self.assertRaises(RuntimeError):
            self.mod.read_limited(stream, 16)

    def test_http_json_error_does_not_slurp_unbounded_body(self):
        huge = b"x" * (self.mod.MAX_HTTP_ERROR_BODY + 50_000)
        err = HTTPError("http://example.test/translate", 500, "boom", hdrs={}, fp=io.BytesIO(huge))
        try:
            with patch.object(self.mod._OPENER, "open", side_effect=err):
                with self.assertRaises(RuntimeError) as ctx:
                    self.mod.http_json("http://example.test/translate")
            self.assertIn("HTTP 500", str(ctx.exception))
            self.assertLessEqual(len(str(ctx.exception)), 400)
        finally:
            err.close()

    def test_http_json_success_over_limit_raises(self):
        cap = self.mod.MAX_HTTP_BODY
        body = b"{" + b"a" * (cap + 8) + b"}"

        class FakeResponse:
            def __init__(self, payload):
                self.headers = {}
                self._buf = io.BytesIO(payload)

            def read(self, n=-1):
                return self._buf.read() if n < 0 else self._buf.read(n)

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

        with patch.object(self.mod._OPENER, "open", return_value=FakeResponse(body)):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.http_json("http://example.test/translate")
        self.assertIn("exceeded", str(ctx.exception))


class InputGuardTests(HelperMixin):
    def test_file_url_is_rejected_as_libretranslate_endpoint(self):
        with self.assertRaises(RuntimeError):
            self.mod.validate_libretranslate_url("file:///etc/passwd")
        with self.assertRaises(RuntimeError):
            self.mod.validate_libretranslate_url("ftp://127.0.0.1:5000")
        with self.assertRaises(RuntimeError):
            self.mod.validate_libretranslate_url("http://127.0.0.1:5000/?api_key=secret")
        self.assertEqual(
            self.mod.validate_libretranslate_url("http://127.0.0.1:5000/"),
            "http://127.0.0.1:5000",
        )

    def test_http_json_rejects_non_http_scheme(self):
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.http_json("file:///etc/passwd")
        self.assertIn("http", str(ctx.exception).lower())

    def test_oversized_input_is_rejected(self):
        cfg = self.mod.Config(engine="google", source="en", target="pt")
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.translate_text(cfg, "a" * (self.mod.MAX_TEXT_CHARS + 8))
        self.assertIn("too large", str(ctx.exception))

    def test_symlink_input_file_is_rejected(self):
        real = Path(self._tmpdir.name) / "note.txt"
        link = Path(self._tmpdir.name) / "alias.txt"
        real.write_text("hello", encoding="utf-8")
        link.symlink_to(real)
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.read_input_file(link)
        self.assertIn("symlink", str(ctx.exception).lower())

    def test_oversized_input_file_is_rejected(self):
        path = Path(self._tmpdir.name) / "big.txt"
        path.write_bytes(b"a" * (self.mod.MAX_TEXT_BYTES + 8))
        with self.assertRaises(RuntimeError) as ctx:
            self.mod.read_input_file(path)
        self.assertIn("too large", str(ctx.exception))


class OcrLangsTests(HelperMixin):
    def test_list_ocr_langs_treats_por_as_installed(self):
        fake = Mock(stdout="List of available languages:\neng\nosd\npor\n")
        with (
            patch.object(self.mod, "have", return_value=True),
            patch.object(self.mod, "run", return_value=fake),
        ):
            data = self.mod.list_ocr_langs()
        self.assertEqual(data["installed"], ["eng", "por"])
        por = next(item for item in data["available"] if item["code"] == "por")
        self.assertTrue(por["installed"])


class StaticReviewTests(unittest.TestCase):
    def test_panel_does_not_put_api_key_on_argv(self):
        text = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertNotIn("--libretranslate-key", text)
        self.assertNotIn("OMARCHY_TRANSLATE_LT_KEY", text)
        self.assertIn("lt.key", text)
        self.assertIn("--no-fallback", text)

    def test_scratch_files_are_not_world_tmp(self):
        for name in ("Panel.qml", "Overlay.qml"):
            text = (ROOT / name).read_text(encoding="utf-8")
            self.assertNotIn("/tmp/omarchy-translate-", text, name)
            self.assertIn("XDG_RUNTIME_DIR", text)
        ocr = (ROOT / "bin" / "omarchy-translate-ocr").read_text(encoding="utf-8")
        self.assertNotIn('CLIP="/tmp/omarchy-translate-clip.txt"', ocr)
        self.assertIn("XDG_RUNTIME_DIR", ocr)

    def test_setup_lt_is_digest_pinned(self):
        text = (ROOT / "bin" / "omarchy-translate-setup-lt").read_text(encoding="utf-8")
        self.assertRegex(text, r'IMAGE="libretranslate/libretranslate:v1\.9\.6@sha256:[0-9a-f]{64}"')
        self.assertNotRegex(text, r'IMAGE="[^"]*:latest"')
        self.assertIn("-p 127.0.0.1:5000:5000", text)
        self.assertNotRegex(text, r"-p 5000:5000")

    def test_drop_requires_txt_or_srt_suffix(self):
        text = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn('lower.endsWith(".txt")', text)
        self.assertIn('path.indexOf("..")', text)
        self.assertIn("/^[a-z0-9_]+$/", text)

    def test_user_facing_text_is_plain(self):
        for name in ("Overlay.qml", "Panel.qml"):
            text = (ROOT / name).read_text(encoding="utf-8")
            opens = len(re.findall(r"^\s*Text \{", text, re.M))
            plains = text.count("textFormat: Text.PlainText")
            self.assertGreater(opens, 0, name)
            self.assertEqual(opens, plains, f"{name}: every Text must set Text.PlainText")
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "Overlay.qml").read_text(encoding="utf-8")
        self.assertIn("textFormat: TextEdit.PlainText", panel)
        self.assertIn("Qt.Key_F1", panel)
        self.assertIn('"history"', panel)
        self.assertIn("helpText", panel)
        self.assertIn("How to use", panel)
        self.assertIn("Engines", panel)
        self.assertIn("Privacy", panel)
        self.assertIn("helpFlick", panel)
        self.assertIn("histFlick", panel)
        self.assertIn("historyMeta", panel)
        helperSrc = (ROOT / "bin" / "omarchy-translate").read_text(encoding="utf-8")
        self.assertIn('fail("missing-espeak", 2)', helperSrc)
        self.assertIn("root.sourceText", overlay)
        self.assertIn("root.resultText", overlay)
        self.assertIn("root.definitionText", panel)

    def test_untrusted_copy_is_not_fed_to_kit_buttons_or_tooltips(self):
        """qs.Ui Button/ToolTip use Text without PlainText. Don't hand them
        clipboard or endpoint strings."""
        for name in ("Overlay.qml", "Panel.qml", "BarWidget.qml"):
            text = (ROOT / name).read_text(encoding="utf-8")
            for prop in ("tooltipText:",):
                for i, line in enumerate(text.splitlines()):
                    if prop not in line:
                        continue
                    self.assertNotRegex(
                        line,
                        r"modelData|resultText|sourceText|definitionText|errorText|detectedSrc",
                        f"{name}:{i+1} {prop} carries untrusted copy",
                    )
            self.assertNotRegex(
                text,
                r"Button\s*\{[^}]*text:\s*String\(modelData",
                f"{name}: history/user string on qs.Ui Button",
            )
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertIn("histFlick", panel)
        self.assertIn("histBlock", panel)
        self.assertNotIn("tooltipText: String(modelData", panel)

    def test_shell_snippets_do_not_concatenate_user_data(self):
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        overlay = (ROOT / "Overlay.qml").read_text(encoding="utf-8")
        self.assertNotIn("Util.shellQuote", panel)
        self.assertNotIn("Util.shellQuote", overlay)
        self.assertNotIn('printf %s "$1" | wl-copy', panel)
        self.assertNotIn('printf %s "$1" | wl-copy', overlay)
        self.assertIn('"copy", "--file"', panel)
        self.assertIn('"copy", "--file"', overlay)
        self.assertIn('tesseract-data-$1', panel)
        self.assertIn('omarchy pkg add "$1"', panel)
        self.assertIn('"espeak-ng"', panel)
        self.assertNotIn("tesseract-data-\" + code", panel)
        self.assertIn('"ocr-langs"', panel)
        self.assertIn("ocrPorReady", panel)
        self.assertIn("omarchy-translate-ocr", panel)
        self.assertIn("OCR a region", panel)
        self.assertIn('wl-paste --no-newline > "$1"', panel)
        self.assertNotIn("wl-paste --no-newline\" + flag", panel)
        self.assertIn("File is too large", panel)
        self.assertIn("Clipboard is too large", overlay)

    def test_manifest_id_is_not_omarchy_reserved(self):
        import json

        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertFalse(str(manifest["id"]).startswith("omarchy."))
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())


if __name__ == "__main__":
    unittest.main()
