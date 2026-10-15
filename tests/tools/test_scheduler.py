#!/usr/bin/env python3
"""Acceptance test for g2fuzz/py_utils/scheduler.py and its hooks in g2fuzz/generator_mutation.py,
written by the judge during the butler work (2026-10). Run from anywhere:
    uv run -q --python 3.10 python <this file>
"""
import ast, importlib, json, os, random, shutil, sys, tempfile, time, traceback

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "g2fuzz"))   # the tool under test runs from its own folder
sys.path.insert(0, os.getcwd())
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def case(fn):
    """Run one group of checks; an exception fails the group instead of stopping the test."""
    try:
        fn()
    except Exception:
        check(False, "%s raised:\n%s" % (fn.__name__, traceback.format_exc(limit=3)))
    return fn


def new_out(queue_names, relationship=None):
    out = tempfile.mkdtemp(prefix="sched_test_")
    os.makedirs(os.path.join(out, "queue"))
    for n in queue_names:
        if n.startswith("."):
            os.makedirs(os.path.join(out, "queue", n))
        else:
            open(os.path.join(out, "queue", n), "w").close()
    if relationship is not None:
        os.makedirs(os.path.join(out, "mutation_log"))
        json.dump(relationship, open(os.path.join(out, "mutation_log", "relationship.json"), "w"))
    return out


def log_lines(out):
    p = os.path.join(out, "mutation_log", "scheduler.jsonl")
    return [json.loads(l) for l in open(p)] if os.path.exists(p) else []


QUEUE = [
    "id:000000,time:0,execs:0,orig:png-1_1.png",
    "id:000001,time:0,execs:0,orig:png-1_2.png",
    "id:000002,time:0,execs:0,orig:png-2_1.png",
    "id:000003,time:0,execs:0,orig:not_kitty.png",
    "id:000004,src:000000,time:10,execs:5,op:havoc,rep:2,+cov",
    "id:000005,src:000004,time:20,execs:9,op:flip1,pos:3",
    "id:000006,src:000002+000003,time:30,execs:12,op:splice,rep:4",
    "id:000007,src:000003,time:40,execs:15,op:havoc,rep:8,+cov",
    "id:000008,time:0,execs:999,orig:png-3_1.png",
    "id:000009,src:000005+000000,time:50,execs:20,op:splice,rep:2",
    ".state",
    "README.txt",
    "id:xyz,orig:png-9_1.png",
]

try:
    sched = importlib.import_module("py_utils.scheduler")
except Exception:
    check(False, "import py_utils.scheduler:\n" + traceback.format_exc(limit=3))
    print("\n%d failed" % len(failures)); sys.exit(1)


@case
def names():
    check(sched.generator_of("id:000012,time:0,execs:0,orig:png-7_1.png") == "png-7.py", "generator_of: queue seed name")
    check(sched.generator_of("png-7_1.png") == "png-7.py", "generator_of: seed file name")
    check(sched.generator_of("tiff-12_3.tif") == "tiff-12.py", "generator_of: tiff-12_3.tif -> tiff-12.py")
    check(sched.generator_of("id:000003,time:0,execs:0,orig:not_kitty.png") is None, "generator_of: stock seed -> None")
    check(sched.generator_of("id:000004,src:000000,time:10,execs:5,op:havoc,rep:2,+cov") is None, "generator_of: a find -> None")
    check(sched.generator_of("README.txt") is None and sched.generator_of("") is None, "generator_of: junk -> None")


@case
def credits():
    out = new_out(QUEUE)
    c = sched.credit(out)
    check(set(c) == {"png-1.py", "png-2.py", "png-3.py"}, "credit: generators with seeds (got %s)" % sorted(c))
    check(c.get("png-1.py") == {"seeds": 2, "productive": 1, "finds": 3},
          "credit: png-1 = 2 seeds, 1 productive, 3 finds (4, 5 and the splice 9) (got %s)" % c.get("png-1.py"))
    check(c.get("png-2.py") == {"seeds": 1, "productive": 1, "finds": 1}, "credit: png-2 gets the splice 6 (got %s)" % c.get("png-2.py"))
    check(c.get("png-3.py") == {"seeds": 1, "productive": 0, "finds": 0}, "credit: png-3 seed without finds (got %s)" % c.get("png-3.py"))
    empty = tempfile.mkdtemp()
    check(sched.credit(empty) == {}, "credit: no queue folder -> {}")
    os.makedirs(os.path.join(empty, "queue"))
    check(sched.credit(empty) == {}, "credit: empty queue -> {}")


@case
def speed():
    names = ["id:%06d,time:0,execs:0,orig:png-%d_1.png" % (i, i) for i in range(200)]
    names += ["id:%06d,src:%06d,time:%d,execs:1,op:havoc,rep:2" % (i, i - 1 if i % 7 else i % 200, i) for i in range(200, 20000)]
    out = new_out(names)
    t = time.time()
    c = sched.credit(out)
    check(time.time() - t < 2.0, "credit: 20,000 entries in under 2 s (%.2f s)" % (time.time() - t))
    check(sum(v["seeds"] for v in c.values()) == 200, "credit: 200 seeds counted in the big queue")


@case
def families():
    rel = {"png-1.py": ["png-3.py"], "png-3.py": ["png-4.py"], "png-4.py": ["png-1.py"]}
    check(sched.family("png-1.py", rel) == {"png-1.py", "png-3.py", "png-4.py"}, "family: transitive, and stops on a cycle")
    check(sched.family("png-2.py", rel) == {"png-2.py"}, "family: a generator without children")


@case
def random_mode():
    os.environ.pop("G2F_SCHEDULER", None)
    out = new_out(QUEUE)
    cands = ["png-1.py", "png-2.py", "png-3.py", "png-4.py"]
    a, b = random.Random(5), random.Random(5)
    picks = [sched.pick_generator(cands, out, rng=a) for _ in range(30)]
    check(picks == [b.choice(cands) for _ in range(30)], "random mode: pick_generator draws exactly like rng.choice")
    os.environ["G2F_SCHEDULER"] = "random"
    a, b = random.Random(9), random.Random(9)
    muts = [sched.pick_mutator(["feature", "structure", "pattern"], out, rng=a) for _ in range(30)]
    check(muts == [b.choice(["feature", "structure", "pattern"]) for _ in range(30)], "random mode: pick_mutator draws exactly like rng.choice")
    check(log_lines(out) == [], "random mode: no scheduler.jsonl lines")
    os.environ["G2F_SCHEDULER"] = "nonsense"
    a, b = random.Random(3), random.Random(3)
    check(sched.pick_generator(cands, out, rng=a) == b.choice(cands), "unknown G2F_SCHEDULER value acts as random")
    os.environ.pop("G2F_SCHEDULER", None)
    # the module's default rng is the global random module, as before
    random.seed(11); x = sched.pick_generator(cands, out)
    random.seed(11); check(x == random.choice(cands), "random mode: default rng is the random module")


@case
def bandit_generator():
    # png-1 family: 50 seeds all productive; png-2: 50 seeds none productive
    names, i = [], 0
    for g, productive in (("png-1", True), ("png-2", False)):
        for k in range(50):
            names.append("id:%06d,time:0,execs:0,orig:%s_%d.png" % (i, g, k + 1)); seed = i; i += 1
            if productive:
                names.append("id:%06d,src:%06d,time:9,execs:1,op:havoc,rep:2,+cov" % (i, seed)); i += 1
    out = new_out(names, relationship={})
    os.environ["G2F_SCHEDULER"] = "bandit"
    picks = [sched.pick_generator(["png-1.py", "png-2.py"], out, rng=random.Random(s)) for s in range(200)]
    check(picks.count("png-1.py") >= 190, "bandit: the productive generator wins (%d/200)" % picks.count("png-1.py"))
    lines = log_lines(out)
    check(len(lines) == 200, "bandit: one log line per pick (%d)" % len(lines))
    l = lines[0] if lines else {}
    check(l.get("kind") == "generator" and l.get("choice") in ("png-1.py", "png-2.py") and l.get("queue") == len(names)
          and set(l.get("arms", {})) == {"png-1.py", "png-2.py"}, "bandit: log line has kind, choice, queue size and both arms")
    arm = l.get("arms", {}).get("png-1.py", {})
    check(arm.get("a") == 51 and arm.get("b") == 1 and 0 <= arm.get("sample", -1) <= 1, "bandit: png-1 arm is Beta(51, 1) with its sample (got %s)" % arm)
    # a new generator with no seeds yet is Beta(1, 1), so it still gets tried
    picks = [sched.pick_generator(["png-2.py", "png-new.py"], out, rng=random.Random(s)) for s in range(200)]
    check(picks.count("png-new.py") >= 150, "bandit: an untried generator beats a known-bad one (%d/200)" % picks.count("png-new.py"))
    # family credit: a child generator's productive seeds count for its parent
    out2 = new_out(names, relationship={"png-2.py": ["png-1.py"]})
    l2 = None
    sched.pick_generator(["png-2.py"], out2, rng=random.Random(0))
    l2 = log_lines(out2)[-1]["arms"]["png-2.py"]
    check((l2["a"], l2["b"]) == (51, 51), "bandit: family sums the parent's and child's seeds (got %s)" % ((l2["a"], l2["b"]),))
    os.environ.pop("G2F_SCHEDULER", None)


@case
def mutators():
    out = new_out(QUEUE)
    os.environ["G2F_BANDIT_PENDING_SEC"] = "300"
    t0 = 1000000.0
    sched.record_mutation(out, "feature", None, now=t0)            # failed mutation
    sched.record_mutation(out, "feature", "png-1.py", now=t0)      # png-1 has a productive seed: success
    sched.record_mutation(out, "structure", "png-3.py", now=t0)    # no productive seed
    sched.record_mutation(out, "pattern", "png-3.py", now=t0 + 900)  # too recent at t0+1000: pending
    st = json.load(open(os.path.join(out, "mutation_log", "scheduler.json")))
    check(len(st.get("mutations", [])) == 4 and st["mutations"][0] == {"mutator": "feature", "child": None, "time": t0},
          "record_mutation: stored in scheduler.json")
    s = sched.mutator_stats(out, now=t0 + 1000)
    check(s.get("feature") == [2, 2], "mutator_stats: feature 1 success + 1 failure -> [2, 2] (got %s)" % s.get("feature"))
    check(s.get("structure") == [1, 2], "mutator_stats: structure failed after the wait -> [1, 2] (got %s)" % s.get("structure"))
    check(s.get("pattern") == [1, 1], "mutator_stats: pattern still pending -> [1, 1] (got %s)" % s.get("pattern"))
    s = sched.mutator_stats(out, now=t0 + 100)
    check(s.get("structure") == [1, 1], "mutator_stats: structure pending before the wait (got %s)" % s.get("structure"))
    # restart: a fresh import reads the same state
    importlib.reload(sched)
    check(sched.mutator_stats(out, now=t0 + 1000).get("feature") == [2, 2], "state survives a new process (module reload)")
    os.environ["G2F_SCHEDULER"] = "bandit"
    for k in range(20):
        sched.record_mutation(out, "structure", None, now=t0)
    picks = [sched.pick_mutator(["feature", "structure"], out, rng=random.Random(s)) for s in range(200)]
    check(picks.count("feature") >= 170, "bandit: pick_mutator avoids the failing mutator (%d/200)" % picks.count("feature"))
    m = [l for l in log_lines(out) if l.get("kind") == "mutator"]
    check(len(m) == 200 and set(m[0].get("arms", {})) == {"feature", "structure"}, "bandit: one mutator log line per pick")
    os.environ.pop("G2F_SCHEDULER", None)


@case
def robustness():
    out = new_out(QUEUE)
    os.makedirs(os.path.join(out, "mutation_log"), exist_ok=True)
    open(os.path.join(out, "mutation_log", "scheduler.json"), "w").write("{not json")
    open(os.path.join(out, "mutation_log", "relationship.json"), "w").write("[1, 2")
    os.environ["G2F_SCHEDULER"] = "bandit"
    check(sched.pick_generator(["png-1.py"], out, rng=random.Random(1)) == "png-1.py", "corrupt JSON files: pick_generator still works")
    check(sched.pick_mutator(["feature"], out, rng=random.Random(1)) == "feature", "corrupt JSON files: pick_mutator still works")
    sched.record_mutation(out, "feature", None)
    check(len(json.load(open(os.path.join(out, "mutation_log", "scheduler.json")))["mutations"]) == 1, "corrupt scheduler.json is replaced on record")
    bare = tempfile.mkdtemp()
    check(sched.pick_generator(["a-1.py", "a-2.py"], bare, rng=random.Random(1)) in ("a-1.py", "a-2.py"), "no queue or mutation_log folder: still picks")
    os.environ.pop("G2F_SCHEDULER", None)


@case
def hooks():
    src = open("generator_mutation.py").read()
    tree = ast.parse(src)
    calls = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)]
    named = lambda obj, attr: [c for c in calls if c.func.attr == attr and isinstance(c.func.value, ast.Name) and c.func.value.id == obj]
    check(len(named("scheduler", "pick_generator")) == 2, "generator_mutation.py: 2 scheduler.pick_generator calls")
    check(len(named("scheduler", "pick_mutator")) == 1, "generator_mutation.py: 1 scheduler.pick_mutator call")
    check(len(named("scheduler", "record_mutation")) >= 1, "generator_mutation.py: scheduler.record_mutation called")
    check(len(named("random", "choice")) == 1, "generator_mutation.py: only the mutation_pattern pick still uses random.choice")
    fns = {n.name: n for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)}
    for f in ("mutation_based_on_pattern", "mutation_based_on_predefined_mutators"):
        rets = [r for r in ast.walk(fns.get(f, ast.parse(""))) if isinstance(r, ast.Return)]
        consts = [r.value.value for r in rets if isinstance(r.value, ast.Constant)]
        check(rets and True not in consts and False not in consts, "%s returns the new generator name or None, not True/False" % f)
    check("from py_utils import scheduler" in src, "generator_mutation.py imports py_utils.scheduler")


print("\n%d failed" % len(failures) if failures else "\nall passed")
sys.exit(1 if failures else 0)
