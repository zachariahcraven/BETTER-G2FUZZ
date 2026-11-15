"""ALFRED (2026-11-14): the `uncovered` stall mutator's data (G2F_STALL_MUTATORS=...+uncovered).

The other stall mutators change a generator without knowing what the target has not executed. This one shows the
LLM source code of the target that earlier campaigns ran into but never finished: a function that was entered, with
the lines no input has reached marked.

Two halves, no dependencies beyond the standard library:
- build_entries(): from `llvm-cov export` JSON of a source-coverage build that replayed a queue (scripts/uncovered
  runs it on Tempest) to a list of entries, saved as <targets>/<target>.uncovered.json.
- load(), pick(), describe(): what generator_mutation.py's mutation_uncovered uses in a step.
"""
import json
import math
import os
import random
import re

MARK = ">>> "
PLAIN = "    "
MAX_LINES = 120     # of one function shown to the LLM
CONTEXT = 30        # lines kept around the largest missed block of a longer function
MAX_CALLEES = 2
MAX_CALLEE_LINES = 60


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
                        "source": "\n".join(_window(annotated)), "callees": callees})
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


def pick(entries, tried, rng=random):
    """One entry: among those not tried in this campaign (all of them once every one was tried), weighted by the
    square root of its missed lines, so big gaps come first without starving the small ones."""
    pool = [e for e in entries if key(e) not in tried] or list(entries)
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
<CALLEES>
Work out what an input file must contain so that the program executes the marked lines: which field values, sizes, counts, flags, tag or chunk types, or which broken data the conditions around those lines test for. Then change the code above so that the files it saves into `./tmp/` contain exactly that. If you are not sure, save several files that try different ways. If the marked lines handle another file format that the program also reads, the files may be of that format instead of <FROMAT>.

Please respond according to the following template:
Here's a version of the code whose files make the program execute the marked lines of `<FUNCTION>`:
```
<Generated Code>
```
Please use Markdown syntax to represent code blocks. Please ensure that there is only one code block. You don't need to tell me which libraries need to be installed.
"""


def describe(entry, program, file_format, generator_code):
    """The user prompt for one entry."""
    callees = ""
    if entry.get("callees"):
        callees = "\nFunctions those lines call, which no input has reached either:\n" + "".join(
            "```\n/* %s, %s */\n%s\n```\n" % (c["function"], c["file"], c["source"]) for c in entry["callees"])
    prompt = PROMPT.replace("<TARGET_GENERATOR>", generator_code).replace("<FROMAT>", file_format)
    prompt = prompt.replace("<PROGRAM>", program).replace("<FUNCTION>", entry["function"])
    return prompt.replace("<FILE>", entry["file"]).replace("<SOURCE>", entry["source"]).replace("<CALLEES>", callees)
