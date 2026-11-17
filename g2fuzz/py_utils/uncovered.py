"""ALFRED (2026-11-14): the `uncovered` stall mutator's data (G2F_STALL_MUTATORS=...+uncovered).

The other stall mutators change a generator without knowing what the target has not executed. This one shows the
LLM source code of the target that earlier campaigns ran into but never finished: a function that was entered, with
the lines no input has reached marked.

Two halves, no dependencies beyond the standard library:
- build_entries(): from `llvm-cov export` JSON of a source-coverage build that replayed a queue (scripts/uncovered
  runs it on Tempest) to a list of entries, saved as <targets>/<target>.uncovered.json.
- load(), pick(), describe(): what generator_mutation.py's mutation_uncovered uses in a step.

ALFRED (2026-11-17, round A06), two switches, both off by default:
- G2F_UNCOVERED_CONDITIONS=1: the prompt also names the conditions of the function that have only ever gone one way
  (llvm-cov's branch records), as explicit goals.
- G2F_UNCOVERED_CHECK=N (1-5): the files of a new generator are run through the target's source-coverage build
  (/uncovered/<target>/build, what build/targets/build-uncovered.sh made the list with). If they reach none of the
  marked lines the LLM is told so and asked again, at most N times. A function whose lines were reached is not
  picked again in this campaign, nor is one that failed MAX_FAILS steps.
"""
import glob
import json
import math
import os
import random
import re
import shlex
import shutil
import subprocess

MARK = ">>> "
PLAIN = "    "
MAX_LINES = 120     # of one function shown to the LLM
CONTEXT = 30        # lines kept around the largest missed block of a longer function
MAX_CALLEES = 2
MAX_CALLEE_LINES = 60
MAX_CONDITIONS = 8
MAX_FAILS = 3           # checked steps without a marked line reached, after which a function is left alone
CHECK_FILES = 16        # of one generator run through the coverage build
CHECK_RUN_SEC = 5
CHECK_COV_SEC = 180


def _line_counts(regions, file_id=0):
    """{line: count} for one function from llvm-cov's regions [l1, c1, l2, c2, count, file, expanded, kind]:
    each line gets the count of the smallest code region (kind 0) that holds it."""
    code = [r for r in regions if r[7] == 0 and r[5] == file_id]
    code.sort(key=lambda r: (r[2] - r[0], r[3] - r[1]), reverse=True)   # widest first, narrower ones overwrite
    counts = {}
    for r in code:
        for line in range(r[0], r[2] + 1):
            counts[line] = r[4]
    return counts


def _is_code(text):
    s = text.strip()
    return bool(s) and s not in ("{", "}", "};", "else", "} else {", "break;") and not s.startswith(("//", "/*", "*"))


def _annotate(lines, first, last, counts):
    out = []
    for n in range(first, last + 1):
        text = lines[n - 1] if n <= len(lines) else ""
        missed = counts.get(n) == 0 and _is_code(text)
        out.append((MARK if missed else PLAIN) + text.rstrip("\n"))
    return out


def _window(annotated):
    """A function longer than MAX_LINES: the largest run of marked lines with CONTEXT lines around it."""
    if len(annotated) <= MAX_LINES:
        return annotated
    best, start = (0, 0), None
    for i, line in enumerate(annotated + [PLAIN]):
        if line.startswith(MARK):
            start = i if start is None else start
        elif start is not None:
            if i - start > best[1] - best[0]:
                best = (start, i)
            start = None
    a = max(0, best[0] - CONTEXT)
    b = min(len(annotated), max(best[1] + CONTEXT, a + MAX_LINES // 2))
    b = min(b, a + MAX_LINES)
    head = [PLAIN + "/* ... %d lines above left out ... */" % a] if a else []
    tail = [PLAIN + "/* ... %d lines below left out ... */" % (len(annotated) - b)] if b < len(annotated) else []
    return head + annotated[a:b] + tail


def _conditions(branches, lines, missed_lines):
    """Conditions that only ever went one way, from llvm-cov's branch records [l1, c1, l2, c2, true count, false
    count, file, expanded, kind]: the MAX_CONDITIONS nearest to a line never executed, in source order."""
    found = {}
    for b in branches or []:
        if len(b) < 7 or b[6] != 0 or (b[4] == 0) == (b[5] == 0):
            continue
        l1, c1, l2, c2 = b[:4]
        if l1 > len(lines):
            continue
        text = lines[l1 - 1][c1 - 1:c2 - 1] if l1 == l2 else lines[l1 - 1][c1 - 1:].rstrip() + " ..."
        text = " ".join(text.split())
        if not text or len(text) > 160:
            continue
        found.setdefault((l1, c1, text), "true" if b[4] == 0 else "false")
    near = sorted(found, key=lambda k: (min([abs(k[0] - m) for m in missed_lines] or [0]), k))[:MAX_CONDITIONS]
    return [{"line": k[0], "text": k[2], "never": found[k]} for k in sorted(near)]


def build_entries(export, read_source, min_missed=2):
    """export: parsed `llvm-cov export -format=text` JSON. read_source(path) -> list of lines, or None.
    One entry per function that was entered (count > 0) and has at least min_missed code lines never executed;
    functions never called that those lines name are added as its callees."""
    functions = export["data"][0]["functions"]
    sources = {}

    def source(path):
        if path not in sources:
            sources[path] = read_source(path)
        return sources[path]

    def short(name):   # llvm-cov names a static function "file.c:name"
        return name.split(":")[-1]

    never = {}
    for f in functions:
        if f["count"] == 0 and f["regions"]:
            never.setdefault(short(f["name"]), f)
    entries = []
    for f in functions:
        if f["count"] == 0 or not f["regions"] or not f.get("filenames"):
            continue
        path = f["filenames"][0]
        lines = source(path)
        if not lines:
            continue
        counts = _line_counts(f["regions"])
        if not counts:
            continue
        first, last = max(1, min(counts) - 2), max(counts)   # 2 lines up: the signature (regions start at "{")
        annotated = _annotate(lines, first, last, counts)
        missed = [a[len(MARK):] for a in annotated if a.startswith(MARK)]
        if len(missed) < min_missed:
            continue
        missed_lines = [first + i for i, a in enumerate(annotated) if a.startswith(MARK)]
        callees = []
        for name in dict.fromkeys(re.findall(r"\b([A-Za-z_]\w*)\s*\(", "\n".join(missed))):
            g = never.get(name)
            if g is None or len(callees) >= MAX_CALLEES or name == short(f["name"]):
                continue
            glines = source(g["filenames"][0]) if g.get("filenames") else None
            gcounts = _line_counts(g["regions"])
            if not glines or not gcounts:
                continue
            body = [glines[n - 1].rstrip("\n")
                    for n in range(max(1, min(gcounts) - 2), min(max(gcounts), len(glines)) + 1)]
            callees.append({"function": name, "file": os.path.basename(g["filenames"][0]),
                            "source": "\n".join(body[:MAX_CALLEE_LINES])})
        entries.append({"function": short(f["name"]), "file": os.path.basename(path), "first_line": first,
                        "missed": len(missed), "lines": last - first + 1,
                        "source": "\n".join(_window(annotated)), "callees": callees,
                        # for the check of a new generator's files (check()): where llvm-cov finds the function
                        "path": path, "name": f["name"], "missed_lines": missed_lines,
                        "conditions": _conditions(f.get("branches"), lines, missed_lines)})
    entries.sort(key=lambda e: (-e["missed"], e["file"], e["function"]))
    return entries


def target_of(output_path):
    """generator_mutation.py's --output is <campaign>/<target>_output/default: the target's name."""
    name = os.path.basename(os.path.dirname(os.path.abspath(output_path)))
    return name[:-len("_output")] if name.endswith("_output") else name


def load(target, folder=None):
    """The target's entries, or [] if no source-coverage replay was made for it."""
    folder = folder or os.environ.get("G2F_UNCOVERED_DIR") or "/targets"
    path = os.path.join(folder, target + ".uncovered.json")
    try:
        with open(path) as f:
            return json.load(f)["entries"]
    except (OSError, ValueError, KeyError):
        return []


def key(entry):
    return "%s:%s" % (entry["file"], entry["function"])


def pick(entries, tried, rng=random, skip=()):
    """One entry: among those not tried in this campaign (all of them once every one was tried), weighted by the
    square root of its missed lines, so big gaps come first without starving the small ones. skip: keys left alone
    while any other entry remains (skipped(): solved, or failed too often)."""
    left = [e for e in entries if key(e) not in skip] or list(entries)
    pool = [e for e in left if key(e) not in tried] or left
    if not pool:
        return None
    return rng.choices(pool, weights=[math.sqrt(e["missed"]) for e in pool], k=1)[0]


PROMPT = """
```
<TARGET_GENERATOR>
```

The code above generates <FROMAT> files. They are test inputs for the program `<PROGRAM>`. Below is part of that program's source code: the function `<FUNCTION>` in `<FILE>`. The program has run this function on thousands of input files already, but the lines marked with `>>>` have never been executed by any of them.
```
<SOURCE>
```
<CALLEES><CONDITIONS>
Work out what an input file must contain so that the program executes the marked lines: which field values, sizes, counts, flags, tag or chunk types, or which broken data the conditions around those lines test for. Then change the code above so that the files it saves into `./tmp/` contain exactly that. If you are not sure, save several files that try different ways. If the marked lines handle another file format that the program also reads, the files may be of that format instead of <FROMAT>.

Please respond according to the following template:
Here's a version of the code whose files make the program execute the marked lines of `<FUNCTION>`:
```
<Generated Code>
```
Please use Markdown syntax to represent code blocks. Please ensure that there is only one code block. You don't need to tell me which libraries need to be installed.
"""


def describe(entry, program, file_format, generator_code, conditions=False):
    """The user prompt for one entry. conditions: also name the conditions that only ever went one way."""
    callees = ""
    if entry.get("callees"):
        callees = "\nFunctions those lines call, which no input has reached either:\n" + "".join(
            "```\n/* %s, %s */\n%s\n```\n" % (c["function"], c["file"], c["source"]) for c in entry["callees"])
    prompt = PROMPT.replace("<TARGET_GENERATOR>", generator_code).replace("<FROMAT>", file_format)
    prompt = prompt.replace("<PROGRAM>", program).replace("<FUNCTION>", entry["function"])
    goals = ""
    if conditions and entry.get("conditions"):
        goals = "\nIn all those runs these conditions of `%s` always had the same result. An input that gives the " \
                "other result takes the program somewhere it has not been:\n" % entry["function"] + "".join(
                    "- `%s` was never %s: make it %s.\n" % (c["text"], c["never"], c["never"])
                    for c in entry["conditions"])
    prompt = prompt.replace("<FILE>", entry["file"]).replace("<SOURCE>", entry["source"])
    return prompt.replace("<CALLEES>", callees).replace("<CONDITIONS>", goals)


# --- G2F_UNCOVERED_CHECK: a new generator's files against the source-coverage build ---------------------------------

def setting(name, most):
    """An integer switch from the environment, 0 (off) to most."""
    try:
        return max(0, min(most, int(os.environ.get(name, "0"))))
    except ValueError:
        return 0


def coverage_build(target, folder=None):
    """(binary, argument list with @@) of the target's source-coverage build, or None if there is none."""
    folder = folder or os.environ.get("G2F_UNCOVERED_BUILDS") or "/uncovered"
    binary = os.path.join(folder, target, "build", target + ".afl")
    if not os.access(binary, os.X_OK):
        return None
    try:
        with open(os.path.join(folder, target, "build", target + ".args")) as f:
            args = shlex.split(f.read())
    except (OSError, ValueError):
        args = []
    return binary, args or ["@@"]


def _tool(name):
    return shutil.which(name + "-18") or shutil.which(name)


def _run_limits():
    import resource
    for kind, value in ((resource.RLIMIT_AS, 4 << 30), (resource.RLIMIT_FSIZE, 64 << 20), (resource.RLIMIT_CORE, 0)):
        try:
            resource.setrlimit(kind, (value, value))
        except (ValueError, OSError):
            pass


def check(entry, build, files_dir, work):
    """Runs up to CHECK_FILES files of files_dir through the coverage build and reads the entry's function from
    llvm-cov. Returns {"runs", "entered", "reached", "of", "crashed", "timed_out"}, or None if it could not be
    measured (old list without "path", no llvm tools, no file, llvm-cov failed). work: an empty scratch folder."""
    profdata, cov = _tool("llvm-profdata"), _tool("llvm-cov")
    if not (profdata and cov and entry.get("path") and entry.get("missed_lines")):
        return None
    binary, args = build
    files = [os.path.join(files_dir, n) for n in sorted(os.listdir(files_dir))] if os.path.isdir(files_dir) else []
    files = [f for f in files if os.path.isfile(f) and os.path.getsize(f) <= 10 << 20][:CHECK_FILES]
    if not files:
        return None
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    result = {"runs": 0, "entered": False, "reached": 0, "of": len(entry["missed_lines"]), "crashed": 0, "timed_out": 0}
    env = dict(os.environ, LLVM_PROFILE_FILE=os.path.join(work, "%m.profraw"))
    one = os.path.join(work, "input")   # a plain name: tiffcp reads the commas of other names as "file,image"
    try:
        for f in files:
            shutil.copyfile(f, one)
            try:
                r = subprocess.run([binary] + [one if a == "@@" else a.replace("@@", one) for a in args], cwd=work,
                                   env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                   stderr=subprocess.DEVNULL, timeout=CHECK_RUN_SEC, preexec_fn=_run_limits)
                result["crashed"] += r.returncode < 0
            except subprocess.TimeoutExpired:
                result["timed_out"] += 1
            result["runs"] += 1
        raws = glob.glob(os.path.join(work, "*.profraw"))
        if not raws:
            return None
        merged = os.path.join(work, "all.profdata")
        subprocess.run([profdata, "merge", "-sparse"] + raws + ["-o", merged], check=True, timeout=CHECK_COV_SEC,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        out = subprocess.run([cov, "export", binary, "-instr-profile=" + merged, "-format=text", entry["path"]],
                             check=True, timeout=CHECK_COV_SEC, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        functions = json.loads(out.stdout)["data"][0]["functions"]
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
        return None
    finally:
        shutil.rmtree(work, ignore_errors=True)
    name = entry.get("name") or entry["function"]
    for f in functions:
        if f["name"] == name and f.get("filenames") and f["filenames"][0] == entry["path"]:
            counts = _line_counts(f["regions"])
            result["entered"] = f["count"] > 0
            result["reached"] = sum(1 for n in entry["missed_lines"] if counts.get(n, 0) > 0)
            return result
    return None


FEEDBACK = """I ran `<PROGRAM>` on the <RUNS> files that this code saved and measured which lines of `<FUNCTION>` were executed.
<RESULT>
Change the code so that its files make the program execute the marked lines of `<FUNCTION>`. Respond with the same template as before: one code block with the whole code."""


def feedback(entry, program, result):
    """What the LLM is told after a check that reached none of the marked lines."""
    if not result["entered"]:
        text = ("Result: the program did not call `%s` at all for any of the files. It probably rejected them before "
                "that, for example for a wrong header, size or checksum. The files must be valid enough for the "
                "program to parse them up to this function." % entry["function"])
    else:
        text = ("Result: the program called `%s`, but none of the %d marked lines were executed. The conditions "
                "that lead to the marked lines were not met by any file." % (entry["function"], result["of"]))
    if result["crashed"] or result["timed_out"]:
        text += " (%d of the runs crashed, %d ran into the %d second limit.)" % (
            result["crashed"], result["timed_out"], CHECK_RUN_SEC)
    return FEEDBACK.replace("<PROGRAM>", program).replace("<RUNS>", str(result["runs"])).replace(
        "<FUNCTION>", entry["function"]).replace("<RESULT>", text)


def skipped(state):
    """Keys pick() leaves alone: state is {key: {"solved": bool, "fails": n}} of this campaign's checked steps."""
    return {k for k, v in state.items() if v.get("solved") or v.get("fails", 0) >= MAX_FAILS}


def record(state, entry, result):
    """Adds one checked step to the state."""
    s = state.setdefault(key(entry), {"solved": False, "fails": 0})
    if result["reached"]:
        s["solved"] = True
    else:
        s["fails"] = s.get("fails", 0) + 1
    return state
