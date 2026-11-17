#!/usr/bin/env python3
"""Tests for the `uncovered` stall mutator (2026-11-14):
- py_utils/uncovered.py: llvm-cov export JSON -> entries (lines never executed marked, callees never called
  attached, long functions cut to a window), the pick (untried first) and the prompt.
- generator_mutation.py mutation_uncovered, end to end against a fake LLM server (needs the openai package, as in
  the image; skipped without it): with the target's file a step makes a generator and records what it tried;
  without it the step does nothing.
- A06 (2026-11-17): the conditions that only ever went one way (G2F_UNCOVERED_CONDITIONS), and the check of a new
  generator's files against a source-coverage build (G2F_UNCOVERED_CHECK), with a real clang coverage build of a
  small C program (needs clang, llvm-profdata and llvm-cov, as in the image; skipped without them).
Run: python3 g2fuzz/tests/test_uncovered.py
"""
import importlib.util
import json
import os
import random
import shutil
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
CLANG = shutil.which("clang-18") or shutil.which("clang")
HAVE_COV = bool(CLANG and uncovered._tool("llvm-profdata") and uncovered._tool("llvm-cov"))

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
     "regions": [[7, 1, 13, 2, 9, 0, 0, 0], [8, 19, 11, 6, 0, 0, 0, 0]],
     # branches: [line1, col1, line2, col2, true count, false count, file, expanded file, kind]
     "branches": [[8, 9, 8, 17, 0, 9, 0, 0, 4]]},
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

    def test_conditions_that_went_one_way(self):
        e = uncovered.build_entries(EXPORT, read_source)[0]
        self.assertEqual(e["conditions"], [{"line": 8, "text": "tag == 7", "never": "true"}])
        self.assertEqual((e["path"], e["name"], e["missed_lines"]), ("/src/t.c", "parse", [8, 9, 10]))
        self.assertNotIn("tag == 7` was never", uncovered.describe(e, "jhead", "jpg", "x"))
        self.assertIn("- `tag == 7` was never true: make it true.", uncovered.describe(e, "jhead", "jpg", "x", True))
        both = json.loads(json.dumps(EXPORT))
        both["data"][0]["functions"][1]["branches"][0][4] = 3      # went both ways: not a goal
        self.assertEqual(uncovered.build_entries(both, read_source)[0]["conditions"], [])

    def test_solved_and_hopeless_functions_are_skipped(self):
        entries = [{"file": "a.c", "function": n, "missed": 9} for n in "fgh"]
        state = {}
        uncovered.record(state, entries[0], {"reached": 2})
        for _ in range(uncovered.MAX_FAILS):
            uncovered.record(state, entries[1], {"reached": 0})
        uncovered.record(state, entries[2], {"reached": 0})
        self.assertEqual(uncovered.skipped(state), {"a.c:f", "a.c:g"})
        for _ in range(20):   # h was tried, but is the only one left
            self.assertEqual(uncovered.pick(entries, {"a.c:h"}, random, skip=uncovered.skipped(state))["function"], "h")
        self.assertIsNotNone(uncovered.pick(entries[:2], set(), random, skip={"a.c:f", "a.c:g"}))   # all skipped

    def test_feedback(self):
        e = uncovered.build_entries(EXPORT, read_source)[0]
        r = {"runs": 4, "entered": False, "reached": 0, "of": 3, "crashed": 1, "timed_out": 0}
        text = uncovered.feedback(e, "jhead", r)
        self.assertIn("did not call `parse` at all", text)
        self.assertIn("on the 4 files", text)
        self.assertIn("1 of the runs crashed", text)
        self.assertIn("none of the 3 marked lines", uncovered.feedback(e, "jhead", dict(r, entered=True)))
        self.assertNotIn("<", text)

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


PROGRAM = """#include <stdio.h>
static int rare(int n)
{
    return n * 2;
}
static int parse(unsigned char *b, long n)
{
    int r = 0;
    if (n > 2 && b[2] == WANT) {
        r = rare(b[0]);
        r += 1;
    }
    return r;
}
int main(int argc, char **argv)
{
    unsigned char b[64];
    FILE *f = argc > 1 ? fopen(argv[1], "rb") : NULL;
    if (!f) return 1;
    long n = (long)fread(b, 1, sizeof b, f);
    fclose(f);
    return parse(b, n) > 1000;
}
"""


def coverage_build(want):
    """A source-coverage build of PROGRAM (its marked lines need byte 2 == want), laid out as build-uncovered.sh
    does (<builds>/prog/build/prog.afl), and its entries after one run that does not reach them."""
    root = tempfile.mkdtemp(prefix="uncovered-build.")
    build = os.path.join(root, "prog", "build")
    os.makedirs(build)
    src = os.path.join(root, "prog.c")
    with open(src, "w") as f:
        f.write(PROGRAM)
    subprocess.run([CLANG, "-fprofile-instr-generate", "-fcoverage-mapping", "-g", "-DWANT=%d" % want, src, "-o",
                    os.path.join(build, "prog.afl")], check=True)
    with open(os.path.join(build, "prog.args"), "w") as f:
        f.write("@@\n")
    first = os.path.join(root, "first")
    with open(first, "wb") as f:
        f.write(b"\xff\xd8base")
    raw = os.path.join(root, "first.profraw")
    subprocess.run([os.path.join(build, "prog.afl"), first], env=dict(os.environ, LLVM_PROFILE_FILE=raw))
    subprocess.run([uncovered._tool("llvm-profdata"), "merge", "-sparse", raw, "-o", raw + ".data"], check=True)
    out = subprocess.run([uncovered._tool("llvm-cov"), "export", os.path.join(build, "prog.afl"),
                          "-instr-profile=" + raw + ".data", "-format=text"], check=True, stdout=subprocess.PIPE)

    def read(path):
        with open(path) as f:
            return f.read().split("\n")
    return root, uncovered.build_entries(json.loads(out.stdout), read)


@unittest.skipUnless(HAVE_COV, "needs clang, llvm-profdata and llvm-cov (run in the image)")
class CheckTest(unittest.TestCase):
    def test_check_measures_the_marked_lines(self):
        root, entries = coverage_build(7)
        e = [x for x in entries if x["function"] == "parse"][0]
        self.assertEqual([(c["text"], c["never"]) for c in e["conditions"]],
                         [("n > 2", "false"), ("b[2] == WANT", "true")])
        build = uncovered.coverage_build("prog", root)
        self.assertEqual(build[1], ["@@"])
        self.assertIsNone(uncovered.coverage_build("other", root))
        files, work = os.path.join(root, "files"), os.path.join(root, "work")
        os.makedirs(files)
        self.assertIsNone(uncovered.check(e, build, files, work))             # no file
        with open(os.path.join(files, "a,b.bin"), "wb") as f:
            f.write(b"\x01\x02\x03")
        r = uncovered.check(e, build, files, work)
        self.assertEqual((r["runs"], r["entered"], r["reached"], r["of"]), (1, True, 0, e["missed"]))
        with open(os.path.join(files, "hit.bin"), "wb") as f:
            f.write(b"\x01\x02\x07")
        r = uncovered.check(e, build, files, work)
        self.assertEqual((r["runs"], r["entered"], r["reached"]), (2, True, e["missed"]))
        self.assertFalse(os.path.exists(work))
        self.assertIsNone(uncovered.check(dict(e, path=None), build, files, work))   # a list made before A06


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

    def step(self, camp, out, data, **more):
        env = dict(os.environ, G2F_STALL_MUTATORS="uncovered", G2F_GENERATOR_SCHEDULER="random", G2F_LLM_RETRIES="0",
                   G2F_UNCOVERED_DIR=data, OPENAI_BASE_URL="http://127.0.0.1:%d/v1" % self.server.server_address[1])
        for name in ("G2F_FONT_HINT", "G2F_UNCOVERED_CHECK", "G2F_UNCOVERED_CONDITIONS", "G2F_UNCOVERED_BUILDS"):
            env.pop(name, None)
        env.update(more)
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

    def checked_step(self, want):
        """A step with G2F_UNCOVERED_CHECK=1 against a build whose marked lines need byte 2 == want (the fake LLM's
        generator writes 7 there)."""
        root, entries = coverage_build(want)
        camp, out, data = self.campaign(with_data=False)
        with open(os.path.join(data, "prog.uncovered.json"), "w") as f:
            json.dump({"target": "prog", "entries": [e for e in entries if e["function"] == "parse"]}, f)
        FakeLLM.prompts.clear()
        r = self.step(camp, out, data, G2F_UNCOVERED_CHECK="1", G2F_UNCOVERED_CONDITIONS="1", G2F_UNCOVERED_BUILDS=root)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        step = [json.loads(l[len("---- step: "):]) for l in r.stdout.split("\n") if l.startswith("---- step: ")][-1]
        with open(os.path.join(out, "mutation_log", "uncovered_state.json")) as f:
            state = json.load(f)
        self.assertEqual(os.listdir(os.path.join(out, "gen_seeds")), ["jpg-2_1.jpg"])
        self.assertEqual(sorted(os.listdir(os.path.join(out, "mutation_log"))),
                         ["relationship.json", "uncovered_state.json", "uncovered_tried.json"])
        return step, state, list(FakeLLM.prompts)

    @unittest.skipUnless(HAVE_COV, "needs clang, llvm-profdata and llvm-cov (run in the image)")
    def test_checked_step_that_reaches_the_lines(self):
        step, state, prompts = self.checked_step(7)
        self.assertEqual((step["entered"], step["asked"], step["uncovered"]), (True, 0, "generator"))
        self.assertGreater(step["reached"], 0)
        self.assertEqual(state, {"prog.c:parse": {"solved": True, "fails": 0}})
        self.assertEqual(len(prompts), 1)
        self.assertIn("was never true: make it true.", prompts[0])

    @unittest.skipUnless(HAVE_COV, "needs clang, llvm-profdata and llvm-cov (run in the image)")
    def test_checked_step_that_does_not_is_asked_again(self):
        step, state, prompts = self.checked_step(9)
        self.assertEqual((step["entered"], step["reached"], step["asked"]), (True, 0, 1))
        self.assertEqual(state, {"prog.c:parse": {"solved": False, "fails": 1}})
        self.assertEqual(len(prompts), 2)
        self.assertIn("the program called `parse`, but none of the", prompts[1])

    def test_no_data_makes_nothing(self):
        camp, out, data = self.campaign(with_data=False)
        r = self.step(camp, out, data)
        self.assertEqual(r.returncode, 0, r.stdout[-2000:] + r.stderr[-2000:])
        self.assertIn("no prog.uncovered.json", r.stdout)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "generators"))), ["jpg-1.py"])


if __name__ == "__main__":
    unittest.main()
