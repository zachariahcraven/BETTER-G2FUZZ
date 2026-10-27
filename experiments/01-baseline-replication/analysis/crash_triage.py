#!/usr/bin/env python3
"""Reruns one campaign's crash files on the ASan binary and buckets them (called by 02-crashes.sbatch).

Each crash file is run once as `<binary> <args with @@ = file>` with a 30 s timeout. Outcomes:
  asan       an AddressSanitizer report; bucket = bug type + the top 3 frames (function + file:line, or
             module+offset when unsymbolized), skipping sanitizer/interceptor frames (UNIFUZZ's top-3 rule)
  signal:N   died from a signal without an ASan report (e.g. a SIGKILL from the kernel)
  timeout    did not finish in 30 s (a hang under ASan, not a bug by the paper's count)
  no-crash   exited normally: the AFL++ crash did not reproduce on the ASan build
Output: <out>/<campaign>.tsv (file, afl_sig, outcome, bug_type, bucket, frames) and <out>/<campaign>.json
(buckets with counts, plus totals). Unique bugs for the campaign = number of distinct asan buckets.
"""
import argparse, collections, hashlib, json, os, re, subprocess, sys

p = argparse.ArgumentParser()
for a in ("campaign", "program", "arm", "rep", "crashes", "args", "binary", "workdir", "out"): p.add_argument("--" + a, required=True)
p.add_argument("--asan-extra", default="", help="extra ASAN_OPTIONS, e.g. max_allocation_size_mb=1024:allocator_may_return_null=0 "
               "(then an allocation over 1 GB is an 'allocation-size-too-big' report, like afl-fuzz -m 1024 treating it as a crash)")
a = p.parse_args()
ASAN_OPTIONS = ("abort_on_error=1:symbolize=1:external_symbolizer_path=/usr/lib/llvm-16/bin/llvm-symbolizer:"
                "detect_leaks=0:allocator_may_return_null=1:handle_abort=1:dedup_token_length=3")
if a.asan_extra: ASAN_OPTIONS += ":" + a.asan_extra   # later options win in ASan's parser
ERR = re.compile(r"ERROR: AddressSanitizer: ([\w-]+)")
SYM = re.compile(r"^\s+#(\d+) 0x[0-9a-f]+ in (\S+) (\S+)")              # symbolized: "in func file:line:col"
RAW = re.compile(r"^\s+#(\d+) 0x[0-9a-f]+\s+\((\S+)\+0x([0-9a-f]+)\)")  # unsymbolized: "(module+0xoff)"
SKIP = ("__interceptor_", "__asan", "__sanitizer", "__ubsan", "__lsan", "libclang_rt", "libasan")

def frames(report):
    """Top 3 frames of the first stack in the report, as 'func file:line' (column dropped) or 'module+off'."""
    out, seen_stack = [], False
    for line in report.splitlines():
        m = SYM.match(line) or RAW.match(line)
        if not m:
            if seen_stack and not line.strip(): break   # blank line ends the first stack
            continue
        seen_stack = True
        if m.re is SYM:
            func, loc = m.group(2), m.group(3)
            loc = os.path.basename(loc); loc = ":".join(loc.split(":")[:2])   # file:line
            fr = f"{func} {loc}"
        else:
            fr = f"{os.path.basename(m.group(2))}+0x{m.group(3)}"
        if any(s in fr for s in SKIP): continue
        out.append(fr)
        if len(out) == 3: break
    return out

files = sorted(f for f in os.listdir(a.crashes) if f.startswith("id:"))
rows, buckets, buckets_fn = [], collections.Counter(), collections.Counter()
outcomes = collections.Counter()
for f in files:
    path = os.path.join(a.crashes, f)
    cmd = [a.binary] + [path if t == "@@" else t for t in a.args.split()]
    env = dict(os.environ, ASAN_OPTIONS=ASAN_OPTIONS)
    try:
        r = subprocess.run(cmd, cwd=a.workdir, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=30)
        err = r.stderr.decode("utf-8", "replace"); rc = r.returncode
    except subprocess.TimeoutExpired as e:
        err = (e.stderr or b"").decode("utf-8", "replace"); rc = None
    m = ERR.search(err)
    afl_sig = (re.search(r",sig:(\d+)", f) or [None, ""])[1]
    if m:
        bug, fr = m.group(1), frames(err)
        if bug == "requested": bug = "allocation-size-too-big"   # "requested allocation size ... exceeds maximum supported size"
        key = bug + " | " + " <- ".join(fr)
        bucket = hashlib.sha1(key.encode()).hexdigest()[:10]
        outcome = "asan"; buckets[(bucket, key)] += 1
        buckets_fn[bug + " | " + " <- ".join(f.split(" ")[0] for f in fr)] += 1   # coarser: function names only
    elif rc is None: bug, fr, bucket, outcome = "", [], "", "timeout"
    elif rc < 0: bug, fr, bucket, outcome = "", [], "", f"signal:{-rc}"
    else: bug, fr, bucket, outcome = "", [], "", "no-crash"
    outcomes[outcome] += 1
    rows.append((f, afl_sig, outcome, bug, bucket, " <- ".join(fr)))

with open(os.path.join(a.out, a.campaign + ".tsv"), "w") as h:
    h.write("file\tafl_sig\toutcome\tbug_type\tbucket\tframes\n")
    for r in rows: h.write("\t".join(r) + "\n")
res = dict(campaign=a.campaign, program=a.program, arm=a.arm, rep=int(a.rep), crash_files=len(files),
           outcomes=dict(outcomes), unique_bugs=len(buckets), unique_bugs_fn=len(buckets_fn),
           buckets_fn=sorted(buckets_fn),
           buckets=[dict(bucket=b, key=k, count=n) for (b, k), n in sorted(buckets.items(), key=lambda x: -x[1])])
with open(os.path.join(a.out, a.campaign + ".json"), "w") as h: json.dump(res, h, indent=1)
print(f"{a.campaign}: {len(files)} crash files -> {dict(outcomes)}, unique ASan buckets {len(buckets)}")
