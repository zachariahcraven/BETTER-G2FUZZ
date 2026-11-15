#!/usr/bin/env python3
"""Tests for the `uncovered` stall mutator (2026-11-14):
- py_utils/uncovered.py: llvm-cov export JSON -> entries (lines never executed marked, callees never called
  attached, long functions cut to a window), the pick (untried first) and the prompt.
- generator_mutation.py mutation_uncovered, end to end against a fake LLM server (needs the openai package, as in
  the image; skipped without it): with the target's file a step makes a generator and records what it tried;
  without it the step does nothing.
Run: python3 g2fuzz/tests/test_uncovered.py
"""
import importlib.util
import json
import os
import random
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
G2F = os.path.dirname(HERE)
sys.path.insert(0, G2F)
from py_utils import uncovered  # noqa: E402

HAVE_OPENAI = importlib.util.find_spec("openai") is not None

SOURCE = """#include <stdio.h>
static void rare(int n)
{
    printf("%d", n);
}
int parse(int tag, int len)
{
    if (tag == 7) {
        rare(len);
        len += 1;
    }
    return len;
}
int never(void)
{
    return 1;
}
""".split("\n")
# regions: [line1, col1, line2, col2, count, file, expanded file, kind]
EXPORT = {"data": [{"functions": [
    {"name": "t.c:rare", "count": 0, "filenames": ["/src/t.c"], "regions": [[3, 1, 5, 2, 0, 0, 0, 0]]},
    {"name": "parse", "count": 9, "filenames": ["/src/t.c"],
     "regions": [[7, 1, 13, 2, 9, 0, 0, 0], [8, 19, 11, 6, 0, 0, 0, 0]]},
    {"name": "never", "count": 0, "filenames": ["/src/t.c"], "regions": [[15, 1, 17, 2, 0, 0, 0, 0]]},
]}]}


def read_source(path):
    return SOURCE if path == "/src/t.c" else None


class EntriesTest(unittest.TestCase):
    def test_entered_functions_with_missed_lines(self):
        entries = uncovered.build_entries(EXPORT, read_source)
        self.assertEqual([e["function"] for e in entries], ["parse"])      # rare and never were not entered
        e = entries[0]
        self.assertEqual((e["file"], e["missed"]), ("t.c", 3))
        lines = e["source"].split("\n")
        self.assertIn(uncovered.PLAIN + "int parse(int tag, int len)", lines)   # the signature, above the region
        self.assertIn(uncovered.MARK + "        rare(len);", lines)
        self.assertIn(uncovered.PLAIN + "    return len;", lines)
        self.assertIn(uncovered.PLAIN + "    }", lines)                         # a brace is never marked
        self.assertEqual([c["function"] for c in e["callees"]], ["rare"])       # called from a missed line
        self.assertIn("static void rare(int n)", e["callees"][0]["source"])

    def test_fully_covered_function_is_left_out(self):
        export = json.loads(json.dumps(EXPORT))
        export["data"][0]["functions"][1]["regions"][1][4] = 5
        self.assertEqual(uncovered.build_entries(export, read_source), [])

    def test_long_function_is_cut_to_a_window(self):
        annotated = [uncovered.PLAIN + "a"] * 200 + [uncovered.MARK + "b"] * 5 + [uncovered.PLAIN + "c"] * 200
        cut = uncovered._window(annotated)
        self.assertLessEqual(len(cut), uncovered.MAX_LINES + 2)
        self.assertEqual(sum(1 for line in cut if line.startswith(uncovered.MARK)), 5)
        self.assertIn("lines above left out", cut[0])
        self.assertIn("lines below left out", cut[-1])

    def test_pick_prefers_untried(self):
        entries = [{"file": "a.c", "function": "f", "missed": 100}, {"file": "a.c", "function": "g", "missed": 2}]
        for _ in range(20):
            self.assertEqual(uncovered.pick(entries, {"a.c:f"}, random)["function"], "g")
        self.assertIn(uncovered.pick(entries, {"a.c:f", "a.c:g"}, random)["function"], ("f", "g"))
        self.assertIsNone(uncovered.pick([], set()))

    def test_target_name_and_prompt(self):
        self.assertEqual(uncovered.target_of("/eval/jhead_output/default"), "jhead")
        e = uncovered.build_entries(EXPORT, read_source)[0]
        prompt = uncovered.describe(e, "jhead", "jpg", "print('gen')")
        for part in ("print('gen')", "program `jhead`", "function `parse` in `t.c`", uncovered.MARK + "        rare(len);",
                     "/* rare, t.c */", "generates jpg files"):
            self.assertIn(part, prompt)
        self.assertNotIn("<", prompt.replace("<stdio.h>", "").replace("<Generated Code>", ""))


GENERATOR = """import os
os.makedirs('./tmp', exist_ok=True)
with open('./tmp/base.jpg', 'wb') as f:
    f.write(b'\\xff\\xd8base')
"""
MUTATED = """```python
import os
os.makedirs('./tmp', exist_ok=True)
with open('./tmp/tag7.jpg', 'wb') as f:
    f.write(b'\\xff\\xd8\\x07')
```"""


class FakeLLM(BaseHTTPRequestHandler):
    prompts = []

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        FakeLLM.prompts.append(body["messages"][-1]["content"])
        data = json.dumps({"id": "x", "object": "chat.completion", "created": 0, "model": body["model"],
                           "choices": [{"index": 0, "finish_reason": "stop", "message": {
                               "role": "assistant", "content": "Here's a version of the code:\n" + MUTATED}}],
                           "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *_):
        pass


@unittest.skipUnless(HAVE_OPENAI, "needs the openai package (run in the image)")
class UncoveredMutatorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeLLM)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def campaign(self, with_data=True):
        camp = tempfile.mkdtemp(prefix="uncovered-test.")
        out = os.path.join(camp, "prog_output", "default")
        for d in ("generators", "queue", "gen_seeds", "mutation_log"):
            os.makedirs(os.path.join(out, d))
        with open(os.path.join(out, "generators", "jpg-1.py"), "w") as f:
            f.write(GENERATOR)
        open(os.path.join(out, "queue", "id:000000,time:0,execs:0,orig:jpg-1_1.jpg"), "w").close()
        with open(os.path.join(camp, "model_setting.json"), "w") as f:
            json.dump({"model": ["fake-model"]}, f)
        with open(os.path.join(camp, "openai_key.txt"), "w") as f:
            f.write("dummy")
        data = os.path.join(camp, "targets")
        os.makedirs(data)
        if with_data:
            with open(os.path.join(data, "prog.uncovered.json"), "w") as f:
                json.dump({"target": "prog", "entries": uncovered.build_entries(EXPORT, read_source)}, f)
        return camp, out, data

    def step(self, camp, out, data):
        env = dict(os.environ, G2F_STALL_MUTATORS="uncovered", G2F_GENERATOR_SCHEDULER="random", G2F_LLM_RETRIES="0",
                   G2F_UNCOVERED_DIR=data, OPENAI_BASE_URL="http://127.0.0.1:%d/v1" % self.server.server_address[1])
        env.pop("G2F_FONT_HINT", None)
        return subprocess.run([sys.executable, os.path.join(G2F, "generator_mutation.py"), "--output", out],
                              cwd=camp, env=env, capture_output=True, text=True, timeout=120)

    def test_step_makes_a_generator_for_missed_lines(self):
        camp, out, data = self.campaign()
        r = self.step(camp, out, data)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        self.assertIn("cur_mutator: uncovered", r.stdout)
        self.assertIn("uncovered: t.c:parse (3 lines never executed), 1 of 1 functions tried", r.stdout)
        self.assertIn(uncovered.MARK + "        rare(len);", FakeLLM.prompts[-1])
        self.assertIn("program `prog`", FakeLLM.prompts[-1])
        self.assertTrue(os.path.exists(os.path.join(out, "generators", "jpg-2.py")))
        self.assertEqual(os.listdir(os.path.join(out, "gen_seeds")), ["jpg-2_1.jpg"])
        with open(os.path.join(out, "mutation_log", "relationship.json")) as f:
            self.assertEqual(json.load(f), {"jpg-1.py": ["jpg-2.py"]})
        with open(os.path.join(out, "mutation_log", "uncovered_tried.json")) as f:
            self.assertEqual(json.load(f), ["t.c:parse"])
        step = [json.loads(l[len("---- step: "):]) for l in r.stdout.split("\n") if l.startswith("---- step: ")]
        self.assertEqual(step[-1], {"file": "t.c", "function": "parse", "generator": "jpg-2.py", "missed": 3,
                                    "uncovered": "generator"})

    def test_no_data_makes_nothing(self):
        camp, out, data = self.campaign(with_data=False)
        r = self.step(camp, out, data)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        self.assertIn("no prog.uncovered.json", r.stdout)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "generators"))), ["jpg-1.py"])


if __name__ == "__main__":
    unittest.main()
