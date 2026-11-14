#!/usr/bin/env python3
"""Tests for Alfred's tweak switches in G2FUZZ's own code (2026-11-09):
- G2F_STALL_MUTATORS (generator_mutation.py): which stall mutators a step may pick; unset is upstream's set.
  G2F_WEB_SOURCES: the web mutator's sources (the mutator itself is tested in test_web.py).
- the rare stall mutator: Rare-Feature Directed Mutation in a stall step, end to end against a fake LLM server
  that replays fixed answers (needs the openai package, as in the image; skipped without it).
- G2F_RFDM_ALL_FORMATS (program_gen.py): setup rounds per format.
- G2F_FONT_HINT (py_utils/font_hint.py): the fontTools note on the font formats' generator prompts; off, or another
  format: the prompt is unchanged. Its skeleton is run where fontTools is installed (skipped elsewhere).
Run: python3 g2fuzz/tests/test_mutators.py   (in the image: all tests; elsewhere the end-to-end ones are skipped)
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
G2F = os.path.dirname(HERE)
sys.path.insert(0, G2F)
import generator_mutation  # noqa: E402  (module level: no LLM client, no openai needed)
import program_gen  # noqa: E402

from py_utils import font_hint  # noqa: E402  (no dependencies)

HAVE_OPENAI = importlib.util.find_spec("openai") is not None
HAVE_FONTTOOLS = importlib.util.find_spec("fontTools") is not None


class StallMutatorsTest(unittest.TestCase):
    def test_default_is_upstream(self):
        self.assertEqual(generator_mutation.stall_mutators(None, False), ["feature", "structure"])
        self.assertEqual(generator_mutation.stall_mutators(None, True), ["feature", "structure", "pattern"])

    def test_rare_added(self):
        self.assertEqual(generator_mutation.stall_mutators("feature+structure+pattern+rare", True),
                         ["feature", "structure", "rare", "pattern"])
        self.assertEqual(generator_mutation.stall_mutators("rare", True), ["rare"])

    def test_web(self):
        self.assertEqual(generator_mutation.stall_mutators("web", False), ["web"])
        self.assertEqual(generator_mutation.stall_mutators("pattern+web+rare+feature", True),
                         ["feature", "rare", "web", "pattern"])

    def test_web_sources(self):
        self.assertEqual(generator_mutation.web_sources(None), list(generator_mutation.WEB_SOURCES))
        self.assertEqual(generator_mutation.web_sources("links+wikipedia"), ["wikipedia", "links"])
        with self.assertRaises(SystemExit):
            generator_mutation.web_sources("wikipedia+google")

    def test_no_pattern(self):
        self.assertEqual(generator_mutation.stall_mutators("feature+structure", True), ["feature", "structure"])

    def test_pattern_only_waits_for_a_pattern(self):
        self.assertEqual(generator_mutation.stall_mutators("pattern", False), [])
        self.assertEqual(generator_mutation.stall_mutators("pattern", True), ["pattern"])

    def test_unknown_refused(self):
        with self.assertRaises(SystemExit):
            generator_mutation.stall_mutators("feature+havoc", False)


class SetupEpochsTest(unittest.TestCase):
    def setUp(self):
        self.saved = os.environ.pop("G2F_RFDM_ALL_FORMATS", None)

    def tearDown(self):
        os.environ.pop("G2F_RFDM_ALL_FORMATS", None)
        if self.saved is not None:
            os.environ["G2F_RFDM_ALL_FORMATS"] = self.saved

    def test_upstream(self):
        self.assertEqual(program_gen.setup_epochs(1), 3)
        self.assertEqual(program_gen.setup_epochs(2), 1)
        self.assertEqual(program_gen.setup_epochs(9), 1)

    def test_all_formats(self):
        os.environ["G2F_RFDM_ALL_FORMATS"] = "1"
        self.assertEqual(program_gen.setup_epochs(9), 3)
        self.assertEqual(program_gen.setup_epochs(1), 3)
        os.environ["G2F_RFDM_ALL_FORMATS"] = "0"
        self.assertEqual(program_gen.setup_epochs(9), 1)


class FontHintTest(unittest.TestCase):
    PROMPT = "Generate 'x' files.\n```\nfeature\n```\nPlease ensure that there is only one code block.\n"

    def setUp(self):
        self.saved = os.environ.pop("G2F_FONT_HINT", None)

    def tearDown(self):
        os.environ.pop("G2F_FONT_HINT", None)
        if self.saved is not None:
            os.environ["G2F_FONT_HINT"] = self.saved

    def test_off_is_unchanged(self):
        for value in (None, "0", ""):
            if value is not None:
                os.environ["G2F_FONT_HINT"] = value
            for fmt in ("ttf", "woff2", "png"):
                self.assertEqual(font_hint.with_font_hint(self.PROMPT, fmt), self.PROMPT)

    def test_on_font_format(self):
        os.environ["G2F_FONT_HINT"] = "1"
        for fmt in ("ttf", "otf", "woff", "woff2", "TTF"):
            got = font_hint.with_font_hint(self.PROMPT, fmt)
            self.assertEqual(got, self.PROMPT + font_hint.HINT)
            self.assertIn("fontTools.fontBuilder", got)

    def test_on_other_format_is_unchanged(self):
        os.environ["G2F_FONT_HINT"] = "1"
        for fmt in ("png", "jpg", "pdf", "tiff", "binary_large_object_BLOB"):
            self.assertEqual(font_hint.with_font_hint(self.PROMPT, fmt), self.PROMPT)

    @unittest.skipUnless(HAVE_OPENAI, "py_utils/func.py needs the openai package")
    def test_the_prompts_that_write_generators(self):
        """func.py's two prompt builders: off, exactly the template with its placeholders filled; on, + the hint."""
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "openai_key.txt"), "w") as f:   # llm_utils reads it on import
                f.write("dummy")
            cwd = os.getcwd()
            os.chdir(d)
            try:
                import py_utils.func as F
            finally:
                os.chdir(cwd)
        new = F.code_gen_prompt.replace("<TARGET>", "ttf").replace("<TARGET_FEATURES>", "1. Kerning")
        ext = (F.generator_mutation_prompt.replace("<FROMAT>", "ttf").replace("<NEW_FEATURE>", "Kerning")
               .replace("<FEATURE_DES>", "1. Kerning").replace("<TARGET_GENERATOR>", "print(1)"))
        self.assertEqual(F.messages_for_code_gen("ttf", "1. Kerning")[-1]["content"], new)
        self.assertEqual(F.messages_for_generator_mutation("ttf", "Kerning", "1. Kerning", "print(1)")[-1]["content"], ext)
        os.environ["G2F_FONT_HINT"] = "1"
        self.assertEqual(F.messages_for_code_gen("ttf", "1. Kerning")[-1]["content"], new + font_hint.HINT)
        self.assertEqual(F.messages_for_generator_mutation("ttf", "Kerning", "1. Kerning", "print(1)")[-1]["content"],
                         ext + font_hint.HINT)
        self.assertEqual(F.messages_for_code_gen("png", "1. Kerning")[-1]["content"],
                         F.code_gen_prompt.replace("<TARGET>", "png").replace("<TARGET_FEATURES>", "1. Kerning"))

    @unittest.skipUnless(HAVE_FONTTOOLS, "needs fontTools (the hint was checked against 4.65.0)")
    def test_the_skeleton_runs(self):
        """The hint's code block, run as a generator would be: it must write a font fontTools can read back."""
        blocks = font_hint.HINT.split("```")
        self.assertEqual(len(blocks), 3)   # one code block
        with tempfile.TemporaryDirectory() as d:
            script = os.path.join(d, "skeleton.py")
            with open(script, "w") as f:
                f.write(blocks[1])
            r = subprocess.run([sys.executable, script], cwd=d, capture_output=True, text=True, timeout=120)
            self.assertEqual(r.returncode, 0, r.stderr[-2000:])
            from fontTools.ttLib import TTFont
            font = TTFont(os.path.join(d, "tmp", "font.ttf"))
            self.assertEqual(font.getBestCmap(), {0x41: "A"})
            for tag in ("glyf", "hmtx", "name", "OS/2", "gasp", "zzzz", "GPOS"):
                self.assertIn(tag, font)

    @unittest.skipUnless(HAVE_FONTTOOLS, "needs fontTools")
    def test_the_names_to_avoid_do_not_exist(self):
        from fontTools.fontBuilder import FontBuilder
        from fontTools.ttLib import TTFont, newTable
        for name in ("setupName", "setupHmtx", "addGlyph"):
            self.assertFalse(hasattr(FontBuilder, name), name)
        self.assertFalse(hasattr(TTFont, "newTable"))
        self.assertFalse(hasattr(newTable("cmap"), "newSubtable"))
        self.assertFalse(hasattr(newTable("name"), "NameRecord"))
        for module, name in (("fontTools.varLib.builder", "FontBuilder"), ("fontTools.feaLib.builder", "FontBuilder"),
                             ("fontTools.ttLib.tables._c_m_a_p", "CmapTable"),
                             ("fontTools.ttLib.tables._c_m_a_p", "CmapSubtableFormat4"),
                             ("fontTools.ttLib.tables._g_l_y_f", "GlyfTable"),
                             ("fontTools.ttLib.tables._g_l_y_f", "GlyphSet"),
                             ("fontTools.ttLib.tables._h_m_t_x", "HmtxTable"),
                             ("fontTools.ttLib.tables._h_e_a_d", "HeadTable"),
                             ("fontTools.ttLib.tables.otTables", "NameRecord"),
                             ("fontTools.ttLib.tables.otTables", "OS_2")):
            self.assertFalse(hasattr(importlib.import_module(module), name), module + "." + name)
        for module in ("_cmap", "_head", "_glyf", "_o_s_2"):
            self.assertIsNone(importlib.util.find_spec("fontTools.ttLib.tables." + module), module)


# --- the rare stall mutator, end to end -----------------------------------------------------------------------
GENERATOR = """import os
os.makedirs('./tmp', exist_ok=True)
with open('./tmp/base.tif', 'wb') as f:
    f.write(b'II*\\x00base')
"""
MUTATED = """```python
import os
os.makedirs('./tmp', exist_ok=True)
with open('./tmp/tiled.tif', 'wb') as f:
    f.write(b'II*\\x00tiled')
```"""


class FakeLLM(BaseHTTPRequestHandler):
    features = ""      # the answer to "what (other) features can ... files have?"
    prompts = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        prompt = body["messages"][-1]["content"]
        FakeLLM.prompts.append(prompt)
        if "features can '" in prompt:
            answer = FakeLLM.features
        elif "additional `" in prompt:
            answer = "Here's an extended version of the code that generates a tiff file:\n" + MUTATED
        else:
            answer = "?"
        data = json.dumps({"id": "x", "object": "chat.completion", "created": 0, "model": body["model"],
                           "choices": [{"index": 0, "finish_reason": "stop",
                                        "message": {"role": "assistant", "content": answer}}],
                           "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


@unittest.skipUnless(HAVE_OPENAI, "needs the openai package (run in the image)")
class RareMutatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeLLM)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def campaign(self):
        """A campaign folder as the worker runs a step in: model_setting.json and the key in the current folder,
        one generator (tiff-1.py), its seed in the queue, and the setup's feature pool for tiff."""
        camp = tempfile.mkdtemp(prefix="rare-test.")
        out = os.path.join(camp, "out", "default")
        for d in ("generators", "queue", "gen_seeds", "mutation_log"):
            os.makedirs(os.path.join(out, d))
        with open(os.path.join(out, "generators", "tiff-1.py"), "w") as f:
            f.write(GENERATOR)
        open(os.path.join(out, "queue", "id:000000,time:0,execs:0,orig:tiff-1_1.tif"), "w").close()
        with open(os.path.join(out, "feature_pool-tiff.json"), "w") as f:
            json.dump({"Multi-page support": "1. Multi-page support: several images in one file"}, f)
        with open(os.path.join(camp, "model_setting.json"), "w") as f:
            json.dump({"model": ["fake-model"]}, f)
        with open(os.path.join(camp, "openai_key.txt"), "w") as f:
            f.write("dummy")
        return camp, out

    def step(self, camp, out, **switches):
        env = dict(os.environ, G2F_STALL_MUTATORS="rare", G2F_GENERATOR_SCHEDULER="random",
                   OPENAI_BASE_URL="http://127.0.0.1:%d/v1" % self.server.server_address[1], G2F_LLM_RETRIES="0")
        env.pop("G2F_FONT_HINT", None)
        env.update(switches)
        return subprocess.run([sys.executable, os.path.join(G2F, "generator_mutation.py"), "--output", out],
                              cwd=camp, env=env, capture_output=True, text=True, timeout=120)

    def test_adds_a_new_feature(self):
        FakeLLM.features = ("1. Multi-page support: several images in one file\n"
                            "2. Tiled layout: the image is stored in tiles\n")
        camp, out = self.campaign()
        r = self.step(camp, out)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        self.assertIn("cur_mutator: rare", r.stdout)
        self.assertIn("rare features offered: 2, new: 1", r.stdout)
        self.assertIn("Apart from the above features", FakeLLM.prompts[-2])   # asked beyond the known pool
        self.assertTrue(os.path.exists(os.path.join(out, "generators", "tiff-2.py")))
        self.assertEqual(os.listdir(os.path.join(out, "gen_seeds")), ["tiff-2_1.tif"])
        with open(os.path.join(out, "feature_pool-tiff.json")) as f:
            self.assertIn("Tiled layout", json.load(f))
        with open(os.path.join(out, "mutation_log", "relationship.json")) as f:
            self.assertEqual(json.load(f), {"tiff-1.py": ["tiff-2.py"]})

    def test_nothing_new_makes_nothing(self):
        FakeLLM.features = "1. Multi-page support: several images in one file\n"
        camp, out = self.campaign()
        r = self.step(camp, out)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        self.assertIn("rare features offered: 1, new: 0", r.stdout)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "generators"))), ["tiff-1.py"])
        self.assertEqual(os.listdir(os.path.join(out, "gen_seeds")), [])

    def test_font_hint_reaches_the_stall_prompts(self):
        """G2F_FONT_HINT in a step: a ttf parent's feature and rare prompts end with the hint; off, or a tiff
        parent, they don't have it. (The fake LLM's answers don't matter here.)"""
        FakeLLM.features = "1. Kerning: pair adjustments\n2. Hinting: instructions\n"
        for mutator, marker in (("feature", "more complex file features"), ("rare", "additional `")):
            for fmt, hint, want in (("ttf", "1", True), ("ttf", "0", False), ("ttf", None, False), ("tiff", "1", False)):
                camp, out = self.campaign()
                os.rename(os.path.join(out, "generators", "tiff-1.py"), os.path.join(out, "generators", fmt + "-1.py"))
                del FakeLLM.prompts[:]
                switches = {"G2F_STALL_MUTATORS": mutator}
                if hint is not None:
                    switches["G2F_FONT_HINT"] = hint
                r = self.step(camp, out, **switches)
                self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
                asked = [q for q in FakeLLM.prompts if marker in q]
                self.assertTrue(asked, (mutator, fmt, hint))
                self.assertEqual(asked[0].endswith(font_hint.HINT), want, (mutator, fmt, hint))
                self.assertEqual("fontBuilder" in asked[0], want, (mutator, fmt, hint))


if __name__ == "__main__":
    unittest.main(verbosity=2)
