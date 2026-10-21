#!/usr/bin/env python3
"""Judge test for tasks/oracle.md. Run from the workdir root."""
import json, os, random, subprocess, sys, tempfile
sys.path.insert(0, os.path.abspath("g2fuzz/py_utils"))
import scheduler as S
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)
def mkout(queue):
    out = tempfile.mkdtemp(prefix="orc_"); os.makedirs(os.path.join(out, "queue")); os.makedirs(os.path.join(out, "mutation_log"))
    for n in queue: open(os.path.join(out, "queue", n), "w").write("x")
    return out
# pool: xml-1 seeds with 3 finds, xml-2 with 1 find, xml-3 seed with 0, xml-4 with 3 finds but 2 seeds productive
q = ["id:000000,time:0,execs:0,orig:xml-1_1.xml", "id:000001,time:0,execs:0,orig:xml-2_1.xml",
     "id:000002,time:0,execs:0,orig:xml-3_1.xml", "id:000003,time:0,execs:0,orig:xml-4_1.xml",
     "id:000004,time:0,execs:0,orig:xml-4_2.xml", "id:000005,time:0,execs:0,orig:small.xml",
     "id:000006,src:000000,time:1,execs:1,op:havoc", "id:000007,src:000006,time:1,execs:1,op:havoc",
     "id:000008,src:000000,time:1,execs:1,op:havoc", "id:000009,src:000001,time:1,execs:1,op:havoc",
     "id:000010,src:000003,time:1,execs:1,op:havoc", "id:000011,src:000004,time:1,execs:1,op:havoc",
     "id:000012,src:000010,time:1,execs:1,op:havoc"]
pool = mkout(q)
cred = S.credit(pool)
p = subprocess.run([sys.executable, "experiments/analysis/lib/oracle_ranking.py", pool], capture_output=True, text=True)
check(p.returncode == 0, "oracle_ranking runs (%s)" % p.stderr[-300:])
try: rank = json.loads(p.stdout)
except Exception: rank = None
want = sorted(cred, key=lambda g: (-cred[g]["finds"], -cred[g]["productive"], -cred[g]["seeds"], g))
check(rank == want, "ranking order finds/productive/seeds/name (got %s, want %s)" % (rank, want))
check(rank is not None and rank[:2] == ["xml-4.py", "xml-1.py"], "tie on finds broken by productive (xml-4 has 2 productive seeds)")
empty = mkout(["id:000000,time:0,execs:0,orig:small.xml"])
p2 = subprocess.run([sys.executable, "experiments/analysis/lib/oracle_ranking.py", empty], capture_output=True, text=True)
check(p2.returncode == 1, "no generators -> exit 1")
rf = os.path.join(pool, "rank.json"); json.dump(want, open(rf, "w"))
os.environ["G2F_SCHEDULER"] = "oracle"; os.environ["G2F_ORACLE_RANKING"] = rf
out = mkout([])
def pg(c, r):
    try: return S.pick_generator(c, out, r)
    except Exception as e: return "ERR %r" % e
check(pg(["xml-3.py", "xml-1.py", "xml-9.py"], random.Random(1)) == "xml-1.py", "picks the best-ranked candidate")
check(pg(["xml-9.py", "xml-8.py"], random.Random(1)) in ("xml-9.py", "xml-8.py"), "unranked candidates -> one of them")
picks = {pg(["xml-9.py", "xml-8.py"], random.Random(s)) for s in range(40)}
check(picks == {"xml-9.py", "xml-8.py"}, "unranked fallback is random (both chosen over seeds)")
try: lines = [json.loads(l) for l in open(os.path.join(out, "mutation_log", "scheduler.jsonl"))]
except Exception: lines = []
check(len(lines) == 42 and lines[0]["mode"] == "oracle" and lines[0]["ranked"] is True and lines[1]["ranked"] is False
      and lines[0]["choice"] == "xml-1.py", "every oracle pick is logged with mode/choice/ranked")
m = {S.pick_mutator(["feature", "structure", "pattern"], out, random.Random(s)) for s in range(40)}
check(m == {"feature", "structure", "pattern"}, "oracle mutator choice is random")
for bad, label in ((None, "unset"), (os.path.join(pool, "nope.json"), "missing"), ("BADJSON", "not a JSON list")):
    if bad is None: os.environ.pop("G2F_ORACLE_RANKING", None)
    elif bad == "BADJSON":
        bf = os.path.join(pool, "bad.json"); open(bf, "w").write('{"a": 1}'); os.environ["G2F_ORACLE_RANKING"] = bf
    else: os.environ["G2F_ORACLE_RANKING"] = bad
    try:
        S.pick_generator(["xml-1.py"], out, random.Random(1)); check(False, "%s ranking -> RuntimeError" % label)
    except RuntimeError: check(True, "%s ranking -> RuntimeError" % label)
os.environ["G2F_SCHEDULER"] = "random"
check(S.pick_generator(["a", "b", "c"], out, random.Random(5)) == random.Random(5).choice(["a", "b", "c"]), "random mode unchanged")
print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
