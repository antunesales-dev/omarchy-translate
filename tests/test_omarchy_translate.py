#!/usr/bin/env python3
"""Regression tests for the translate helper and the review findings."""

from __future__ import annotations

import importlib.machinery
import importlib.util
import io
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
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
            with patch.object(self.mod, "urlopen", side_effect=err):
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

        with patch.object(self.mod, "urlopen", return_value=FakeResponse(body)):
            with self.assertRaises(RuntimeError) as ctx:
                self.mod.http_json("http://example.test/translate")
        self.assertIn("exceeded", str(ctx.exception))


class StaticReviewTests(unittest.TestCase):
    def test_panel_does_not_put_api_key_on_argv(self):
        text = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        self.assertNotIn("--libretranslate-key", text)
        self.assertIn("OMARCHY_TRANSLATE_LT_KEY", text)
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

    def test_manifest_id_is_not_omarchy_reserved(self):
        import json

        manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))
        self.assertFalse(str(manifest["id"]).startswith("omarchy."))
        self.assertEqual(manifest["kinds"], ["bar-widget"])
        self.assertTrue((ROOT / manifest["entryPoints"]["barWidget"]).is_file())


if __name__ == "__main__":
    unittest.main()
