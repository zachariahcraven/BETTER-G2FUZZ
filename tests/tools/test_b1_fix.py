#!/usr/bin/env python3
"""Judge test for tasks/b1-fix-record.md. Run from the workdir root (holding g2fuzz/)."""
import copy, json, os, random, sys, tempfile, traceback
sys.path.insert(0, os.path.abspath("g2fuzz"))
os.environ["G2F_SCHEDULER"] = "random"
import generator_mutation as gm
from py_utils import scheduler
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)

def setup():
    out = tempfile.mkdtemp(prefix="b1fix_")
    for d in ("tmp", "gen_seeds", "generators", "mutation_log", "queue"):
        os.makedirs(os.path.join(out, d))
    open(os.path.join(out, "generators", "xml-1.py"), "w").write("print('gen')\n")
    open(os.path.join(out, "generators", "xml-2.py"), "w").write("print('gen2')\n")
    return out

def records(out):
    p = os.path.join(out, "mutation_log", "scheduler.json")
    return json.load(open(p))["mutations"] if os.path.exists(p) else []

for name in ("copy", "json", "random"):
    setattr(gm, name, {"copy": copy, "json": json, "random": random}[name])
gm.count_files_in_directory = lambda p: len(os.listdir(p))
gm.mv_files = lambda *a, **k: None
gm.self_debug = lambda code, *a, **k: code
gm.format_text = lambda token: token   # imported by generator_mutation's __main__ (from py_utils.func import *)

check(hasattr(gm, "run_step"), "run_step exists")
for mut in ("feature", "structure", "pattern"):
    out = setup()
    def boom(*a, **k): raise ConnectionError("LLM API error (test)")
    gm.gen_code_debug = boom
    pat = [["xml-1.py", "xml-2.py"]]
    raised = None
    try:
        gm.run_step("m", os.path.join(out, "tmp"), os.path.join(out, "gen_seeds"), os.path.join(out, "generators"),
                    out, os.path.join(out, "mutation_log"), {"xml-1.py": ["xml-2.py"]}, pat, mut)
    except BaseException as e:
        raised = e
    r = records(out)
    check(isinstance(raised, ConnectionError) and "test" in str(raised), "%s: the original exception propagates" % mut)
    check(len(r) == 1 and r[0]["mutator"] == mut and r[0]["child"] is None, "%s: exactly one failure record on exception (got %s)" % (mut, r))
    # success path: exactly one record naming the new generator
    out = setup()
    gm.gen_code_debug = lambda *a, **k: ("print('new')\n", "raw")
    try:
        res = gm.run_step("m", os.path.join(out, "tmp"), os.path.join(out, "gen_seeds"), os.path.join(out, "generators"),
                          out, os.path.join(out, "mutation_log"), {"xml-1.py": ["xml-2.py"]}, pat, mut)
    except Exception:
        traceback.print_exc(); res = None
    r = records(out)
    check(res is not None and len(r) == 1 and r[0]["child"] == res, "%s: success -> exactly one record with the new generator (got %s, %s)" % (mut, res, r))
src = open("g2fuzz/generator_mutation.py").read()
main = src.split('if __name__ == "__main__":', 1)[1]
check("run_step(" in main and "mutation_based_on_pattern(" not in main and "mutation_based_on_predefined_mutators(" not in main,
      "__main__ dispatches through run_step only")
print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
