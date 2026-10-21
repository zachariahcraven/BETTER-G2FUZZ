#!/usr/bin/env python3
"""Judge test for tasks/arm-parity.md on a synthetic campaign tree. Run from the workdir root."""
import csv, hashlib, os, subprocess, sys, tempfile
TOOL = os.path.abspath("experiments/analysis/arm-parity")
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)

def h12(b): return hashlib.sha256(b).hexdigest()[:12]

def camp(root, group, name, target="xml_fuzzer", image="img-A", V=3600, llm=None, envs=None, seeds=None,
         binds=None, fdesc=None, ranking=None, server="0.31 ; --max-model-len 32768", stock="/targets/seeds/xml/*"):
    f = os.path.join(root, group, name); os.makedirs(f)
    open(os.path.join(f, "target.txt"), "w").write(target + "\n")
    if image is not None: open(os.path.join(f, "image-version.txt"), "w").write(image + "\nsecond line\n")
    gen = "python /AFLplusplus/g2fuzz/program_gen.py --output ./o --program x > seedgen.log 2>&1; " if llm else ""
    cp = ("mkdir -p initial_seeds && cp %s initial_seeds/ && " % stock) if stock else ""
    open(os.path.join(f, "run.sh"), "w").write(
        "#!/bin/bash\ncd /eval\n( %s%safl-fuzz -i initial_seeds -o o -c /targets/%s.cmp   -m 1024 -V %d  -k /AFLplusplus/g2fuzz/ -- /targets/%s.afl @@ > fuzz.log 2>&1 ) &\n"
        % (gen, cp, target, V, target))
    env = envs if envs is not None else (["OPENAI_BASE_URL=http://gpu0%d:3%d/v1" % (len(name), len(name)), "PIP_USER=1"] if llm
                                         else ["G2F_PLATEAU_SEC=999999999", "OPENAI_BASE_URL=http://no-llm.invalid/v1", "PIP_USER=1"])
    b = binds if binds is not None else ["/x/g2fuzz:/AFLplusplus/g2fuzz"]
    line = "apptainer exec --cleanenv --bind %s:/eval " % f + "".join("--bind %s " % x for x in b) + \
           "--env %s --bind \"$fast\":/eval/o --env AFL_NO_UI=1 /x/g2fuzz.sif bash /eval/run.sh &\n" % "\\,".join(env)
    open(os.path.join(f, "job.sbatch"), "w").write("#!/bin/bash\n" + line)
    if llm:
        open(os.path.join(f, "llm-version.txt"), "w").write(
            "vLLM server job 1 on gpu0%d\nmodel: %s = org/%s @ abc\nvllm: %s\ngpus: 2 H100\nsettings: %s\n"
            % (len(name), llm, llm, server.split(" ; ")[0], server.split(" ; ")[1]))
    if seeds is not None:
        os.makedirs(os.path.join(f, "initial_seeds", "sub"))
        for k, v in seeds.items(): open(os.path.join(f, "initial_seeds", k), "wb").write(v)
        open(os.path.join(f, "initial_seeds", "sub", "ignored"), "w").write("not counted")
    if fdesc is not None: open(os.path.join(f, "format_desc.txt"), "wb").write(fdesc)
    if ranking is not None: open(os.path.join(f, "oracle_ranking.json"), "wb").write(ranking)
    return f

root = tempfile.mkdtemp(); C = os.path.join(root, "campaigns")
S = {"a.xml": b"<a/>", "b.xml": b"<b/>"}
# experiment xml: baseline x2 identical; codernext x2 (r2 on another image -> within-arm + between UNEXPECTED image)
camp(C, "lineup-1h", "xml-baseline-r1", seeds=S); camp(C, "lineup-1h", "xml-baseline-r2", seeds=S)
camp(C, "lineup-1h", "xml-codernext-r1", llm="Coder", seeds={"g.xml": b"1"}, fdesc=b"xml desc",
     envs=["G2F_FORMAT_DESC_FILE=/eval/format_desc.txt", "OPENAI_BASE_URL=http://g5:5/v1", "PIP_USER=1"])
camp(C, "lineup-1h", "xml-codernext-r2", llm="Coder", image="img-B", seeds={"g.xml": b"2"}, fdesc=b"xml desc",
     envs=["G2F_FORMAT_DESC_FILE=/eval/format_desc.txt", "OPENAI_BASE_URL=http://g6:6/v1", "PIP_USER=1"])
camp(C, "seed-controls", "xml-ctl-junk-r1", seeds={"j": b"junk1"}, stock=None)
camp(C, "seed-controls", "xml-ctl-junk-r2", seeds={"j": b"junk2"}, stock=None)
camp(C, "seed-controls", "xml-ctl-llmseeds-r1", seeds={"l": b"ll"}, stock=None)
# bandit: scheduler differs (allowed); -V differs (UNEXPECTED)
camp(C, "bandit", "bandit-xml-bandit-r1", llm="Coder", envs=["G2F_SCHEDULER=bandit", "G2F_PLATEAU_SEC=5", "OPENAI_BASE_URL=http://g1:1/v1"])
camp(C, "bandit", "bandit-xml-random-r1", llm="Coder", V=7200, envs=["G2F_SCHEDULER=random", "G2F_PLATEAU_SEC=5", "OPENAI_BASE_URL=http://g2:2/v1"])
camp(C, "bandit", "bandit-xml-oracle-r1", llm="Coder", ranking=b"[\"a\"]",
     envs=["G2F_SCHEDULER=oracle", "G2F_ORACLE_RANKING=/eval/oracle_ranking.json", "G2F_PLATEAU_SEC=5", "OPENAI_BASE_URL=http://g3:3/v1"])
# wadp: format_desc differs (allowed); spec arm also has an extra targets bind (UNEXPECTED); server settings differ within bare (allowed)
camp(C, "wad-prompt", "wadp-bare-codernext-r1", target="doom_wad", llm="Coder", stock="/targets/seeds/doom_wad/*")
camp(C, "wad-prompt", "wadp-bare-codernext-r2", target="doom_wad", llm="Coder", stock="/targets/seeds/doom_wad/*", server="0.31 ; --max-model-len 131072")
camp(C, "wad-prompt", "wadp-spec-codernext-r1", target="doom_wad", llm="Coder", stock="/targets/seeds/doom_wad/*", fdesc=b"spec text",
     envs=["G2F_FORMAT_DESC_FILE=/eval/format_desc.txt", "OPENAI_BASE_URL=http://g9:9/v1"],
     binds=["/x/g2fuzz:/AFLplusplus/g2fuzz", '"/home/u/tg:/targets:ro"'])
# a reference arm whose campaigns have no target.txt (early campaigns): value 'missing'
f0 = camp(C, "lineup-1h", "xml-old-r1", seeds=S); os.remove(os.path.join(f0, "target.txt"))
# edge cases: an afl-fuzz command split over two lines (backslash-newline) and an empty initial_seeds/ folder
fe = camp(C, "lineup-1h", "png-baseline-r1", target="png_t", stock="/targets/seeds/png/*")
open(os.path.join(fe, "run.sh"), "w").write("#!/bin/bash\n( afl-fuzz -i initial_seeds -o o \\\n   -V 3600 -- /targets/png_t.afl @@ > fuzz.log ) &\n")
os.makedirs(os.path.join(fe, "initial_seeds"))
fe2 = camp(C, "lineup-1h", "png-baseline-r2", target="png_t", stock="/targets/seeds/png/*")
open(os.path.join(fe2, "run.sh"), "w").write("#!/bin/bash\n( afl-fuzz -i initial_seeds -o o -V 3600 -- /targets/png_t.afl @@ > fuzz.log ) &\n")
os.makedirs(os.path.join(fe2, "initial_seeds"))
# excluded campaign with a wild config: must not appear anywhere
camp(C, "lineup-1h", "xml-baseline-r3", image="WILD", V=1, seeds={"z": b"z"})

def write_cov(path, names):
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow("campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges".split(","))
        for n in names: w.writerow([n, "t", "m", 1, 1, 1, 0, 0, 5])
def write_stats(path, triples):
    with open(path, "w", newline="") as f:
        w = csv.writer(f); w.writerow("experiment,metric,arm,reference,n_arm,n_ref".split(","))
        for e, a, r in triples:
            for metric in ("coverage", "crash_sites"): w.writerow([e, metric, a, r, 1, 1])
ALL = ["xml-baseline-r1", "xml-baseline-r2", "xml-baseline-r3", "xml-codernext-r1", "xml-codernext-r2", "xml-ctl-junk-r1",
       "xml-ctl-junk-r2", "xml-ctl-llmseeds-r1", "bandit-xml-bandit-r1", "bandit-xml-random-r1", "bandit-xml-oracle-r1",
       "wadp-bare-codernext-r1", "wadp-bare-codernext-r2", "wadp-spec-codernext-r1", "xml-old-r1", "png-baseline-r1", "png-baseline-r2"]
TRI = [("xml", "codernext", "baseline"), ("xml", "ctl-junk", "baseline"), ("xml", "ctl-llmseeds", "ctl-junk"),
       ("xml", "ctl-llmseeds", "baseline"), ("xml", "old", "baseline"), ("png", "baseline", "baseline"), ("bandit-xml", "bandit", "random"), ("bandit-xml", "oracle", "random"),
       ("bandit-xml", "oracle", "bandit"), ("wadp", "spec-codernext", "bare-codernext")]
cov = os.path.join(root, "cov.csv"); st = os.path.join(root, "stats.csv"); ex = os.path.join(root, "ex.csv"); out = os.path.join(root, "p.csv")
write_cov(cov, ALL); write_stats(st, TRI)
open(ex, "w").write("campaign,reason\nxml-baseline-r3,short run\n")

def run(*extra, cov_=cov, st_=st, out_=out):
    return subprocess.run([sys.executable, TOOL, "--campaigns", C, "--cov", cov_, "--stats", st_, "--exclude", ex, "--out", out_] + list(extra),
                          capture_output=True, text=True)
p = run()
check(p.returncode == 1, "exit 1 when UNEXPECTED rows exist (rc %s, stderr %s)" % (p.returncode, p.stderr[-300:]))
rows = list(csv.DictReader(open(out))) if os.path.exists(out) else []
check(rows and list(rows[0].keys()) == "experiment,arm,reference,field,arm_values,ref_values,status".split(","), "columns")
R = {(r["experiment"], r["arm"], r["reference"], r["field"]): r for r in rows}
def has(k, status, av=None, rv=None):
    r = R.get(k)
    ok = r is not None and r["status"] == status and (av is None or r["arm_values"] == av) and (rv is None or r["ref_values"] == rv)
    check(ok, "row %s -> %s %s %s (got %s)" % (k, status, av or "", rv or "", r and (r["status"], r["arm_values"], r["ref_values"])))
def hasnot(k): check(k not in R, "no row %s (got %s)" % (k, R.get(k) and R[k]["status"]))

# within-arm image difference
has(("xml", "codernext", "", "image"), "UNEXPECTED", "img-A (n=1) | img-B (n=1)", "")
# between: image set {A,B} vs {A}: unexpected; model/seedgen/seeds/env OPENAI/PLATEAU allowed
has(("xml", "codernext", "baseline", "image"), "UNEXPECTED", "img-A (n=1) | img-B (n=1)", "img-A (n=2)")
has(("xml", "codernext", "baseline", "model"), "allowed", "Coder = org/Coder @ abc (n=2)", "none (n=2)")
has(("xml", "codernext", "baseline", "seedgen"), "allowed", "llm (n=2)", "none (n=2)")
has(("xml", "codernext", "baseline", "seeds"), "allowed", "llm-generated (n=2)")
has(("xml", "codernext", "baseline", "env:OPENAI_BASE_URL"), "allowed", "llm (n=2)", "none (n=2)")
has(("xml", "codernext", "baseline", "env:G2F_PLATEAU_SEC"), "allowed", "unset (n=2)", "999999999 (n=2)")
has(("xml", "codernext", "baseline", "server"), "allowed")
has(("xml", "codernext", "baseline", "format_desc"), "allowed", "%s (n=2)" % h12(b"xml desc"), "none (n=2)")
has(("xml", "codernext", "baseline", "env:G2F_FORMAT_DESC_FILE"), "allowed", "/eval/format_desc.txt (n=2)", "unset (n=2)")
hasnot(("xml", "codernext", "", "env:OPENAI_BASE_URL"))          # host/port differ but normalized to llm
hasnot(("xml", "codernext", "baseline", "afl_cmd")); hasnot(("xml", "codernext", "baseline", "binds"))
hasnot(("xml", "codernext", "baseline", "target")); hasnot(("xml", "codernext", "baseline", "env:PIP_USER"))
# baseline seeds hash: from the two files (subfolder ignored), identical across reps -> no within-arm row
lines = "".join("%s:%s\n" % (k, hashlib.sha256(S[k]).hexdigest()) for k in sorted(S))
hasnot(("xml", "baseline", "", "seeds"))
# ctl-junk: seeds differ within arm -> allowed; vs baseline stock_seeds none vs path -> UNEXPECTED, seeds allowed
has(("xml", "ctl-junk", "", "seeds"), "allowed")
has(("xml", "ctl-junk", "baseline", "seeds"), "allowed", None, "%s (n=2)" % h12(lines.encode()))
has(("xml", "ctl-junk", "baseline", "stock_seeds"), "allowed", "none (n=2)", "/targets/seeds/xml/* (n=2)")
hasnot(("xml", "ctl-junk", "baseline", "afl_cmd"))
# ctl-llmseeds vs ctl-junk: both no-llm, only seeds differ -> allowed only
has(("xml", "ctl-llmseeds", "ctl-junk", "seeds"), "allowed", "%s (n=1)" % h12(("l:%s\n" % hashlib.sha256(b"ll").hexdigest()).encode()))
has(("xml", "old", "baseline", "target"), "UNEXPECTED", "missing (n=1)", "xml_fuzzer (n=2)")
hasnot(("xml", "old", "baseline", "seeds"))
# png: afl_cmd across the line break normalizes to "... -o o \\ -V 3600 ..." (backslash kept, whitespace collapsed)
has(("png", "baseline", "", "afl_cmd"), "UNEXPECTED",
    "afl-fuzz -i initial_seeds -o o -V 3600 -- /targets/png_t.afl @@ (n=1) | afl-fuzz -i initial_seeds -o o \\ -V 3600 -- /targets/png_t.afl @@ (n=1)")
check(R.get(("png", "baseline", "", "seeds")) is None, "empty initial_seeds hashed identically")
# seeds value of an empty folder = first 12 hex of sha256 of the empty string
cov5 = os.path.join(root, "cov5.csv"); st5 = os.path.join(root, "st5.csv"); out5 = os.path.join(root, "p5b.csv")
camp(C, "lineup-1h", "png-ctl-junk-r1", target="png_t", stock=None, seeds={})
write_cov(cov5, ["png-baseline-r2", "png-ctl-junk-r1"]); write_stats(st5, [("png", "ctl-junk", "baseline")])
p5 = run(cov_=cov5, st_=st5, out_=out5)
r5 = {(r["arm"], r["reference"], r["field"]): r for r in csv.DictReader(open(out5))} if os.path.exists(out5) else {}
check(("ctl-junk", "baseline", "seeds") not in r5, "empty seed sets compare equal (got %s)" % r5.get(("ctl-junk", "baseline", "seeds")))
h_empty = hashlib.sha256(b"").hexdigest()[:12]
camp(C, "lineup-1h", "png-ctl-llmseeds-r1", target="png_t", stock=None, seeds={"x": b"x"})
write_cov(cov5, ["png-ctl-junk-r1", "png-ctl-llmseeds-r1"]); write_stats(st5, [("png", "ctl-llmseeds", "ctl-junk")])
p5 = run(cov_=cov5, st_=st5, out_=out5)
r5 = {(r["arm"], r["reference"], r["field"]): r for r in csv.DictReader(open(out5))} if os.path.exists(out5) else {}
check(r5.get(("ctl-llmseeds", "ctl-junk", "seeds"), {}).get("ref_values") == "%s (n=1)" % h_empty,
      "empty initial_seeds -> sha256 of the empty text (got %s)" % r5.get(("ctl-llmseeds", "ctl-junk", "seeds")))
# bandit
has(("bandit-xml", "bandit", "random", "env:G2F_SCHEDULER"), "allowed", "bandit (n=1)", "random (n=1)")
has(("bandit-xml", "bandit", "random", "afl_cmd"), "UNEXPECTED")
has(("bandit-xml", "oracle", "random", "afl_cmd"), "UNEXPECTED")
has(("bandit-xml", "oracle", "random", "oracle_ranking"), "allowed", "%s (n=1)" % h12(b"[\"a\"]"), "none (n=1)")
has(("bandit-xml", "oracle", "random", "env:G2F_ORACLE_RANKING"), "allowed", "/eval/oracle_ranking.json (n=1)", "unset (n=1)")
hasnot(("bandit-xml", "oracle", "bandit", "afl_cmd")); hasnot(("bandit-xml", "bandit", "random", "model"))
# wadp
has(("wadp", "spec-codernext", "bare-codernext", "format_desc"), "allowed", "%s (n=1)" % h12(b"spec text"), "none (n=2)")
has(("wadp", "spec-codernext", "bare-codernext", "env:G2F_FORMAT_DESC_FILE"), "allowed")
has(("wadp", "spec-codernext", "bare-codernext", "binds"), "UNEXPECTED",
    "/AFLplusplus/g2fuzz<-/x/g2fuzz /targets<-/home/u/tg (n=1)", "/AFLplusplus/g2fuzz<-/x/g2fuzz (n=2)")
has(("wadp", "bare-codernext", "", "server"), "allowed")
has(("wadp", "spec-codernext", "bare-codernext", "server"), "UNEXPECTED")   # same model, server settings differ
has(("wadp", "spec-codernext", "bare-codernext", "env:PIP_USER"), "UNEXPECTED", "unset (n=1)", "1 (n=2)")
# excluded campaign nowhere
check(not any("WILD" in r["arm_values"] + r["ref_values"] or "V 1 " in r["arm_values"] + r["ref_values"] for r in rows),
      "excluded campaign's config appears nowhere")
check(all(r["status"] in ("allowed", "UNEXPECTED") for r in rows), "status values")
keys = [(r["experiment"], r["arm"], r["reference"], r["field"]) for r in rows]
check(keys == sorted(keys), "rows sorted"); check(len(keys) == len(set(keys)), "no duplicate rows (stats has 2 metrics per comparison)")
check("xml: 5 comparisons, 14 allowed, 3 UNEXPECTED" in p.stdout.splitlines() and "wadp: 1 comparisons, 3 allowed, 3 UNEXPECTED" in p.stdout.splitlines(),
      "stdout summary per experiment (%s)" % p.stdout[:300])
b1 = open(out, "rb").read(); run(); check(open(out, "rb").read() == b1, "deterministic")

# clean subset -> exit 0
cov2 = os.path.join(root, "cov2.csv"); st2 = os.path.join(root, "st2.csv"); out2 = os.path.join(root, "p2.csv")
write_cov(cov2, ["xml-baseline-r1", "xml-baseline-r2", "xml-ctl-junk-r1", "xml-ctl-junk-r2", "xml-ctl-llmseeds-r1"])
write_stats(st2, [("xml", "ctl-llmseeds", "ctl-junk")])
p = run(cov_=cov2, st_=st2, out_=out2)
check(p.returncode == 0, "exit 0 when all differences are allowed (rc %s, %s)" % (p.returncode, p.stderr[-200:]))
r2 = list(csv.DictReader(open(out2))) if os.path.exists(out2) else []
check([(r["arm"], r["reference"], r["field"], r["status"]) for r in r2] ==
      [("ctl-junk", "", "seeds", "allowed"), ("ctl-llmseeds", "ctl-junk", "seeds", "allowed")], "clean subset rows (got %s)" % r2)

# errors -> exit 2
cov3 = os.path.join(root, "cov3.csv"); write_cov(cov3, ["xml-baseline-r1", "xml-nofolder-r1"])
p = run(cov_=cov3, st_=st2, out_=os.path.join(root, "p3.csv"))
check(p.returncode == 2 and "xml-nofolder-r1" in p.stderr, "missing folder -> exit 2 naming it")
st4 = os.path.join(root, "st4.csv"); write_stats(st4, [("xml", "ghost", "baseline")])
p = run(cov_=cov2, st_=st4, out_=os.path.join(root, "p4.csv"))
check(p.returncode == 2 and "ghost" in p.stderr, "stats arm without campaigns -> exit 2")
camp(C, "dup", "xml-baseline-r1", seeds=S)
p = run(cov_=cov2, st_=st2, out_=os.path.join(root, "p5.csv"))
check(p.returncode == 2 and "xml-baseline-r1" in p.stderr, "campaign folder found twice -> exit 2")

print("%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
