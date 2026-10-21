#!/usr/bin/env python3
"""Rebuilds the seed-control sets next to this file from finished campaigns (run from the project
root): <tgt>-llmseeds = that campaign's initial_seeds as they are; <tgt>-junk = the same stock files,
plus random bytes for each generated file, the same size and keeping its first 4 bytes (seed 591).
Demo junk keeps each generated demo's 13-byte header and randomizes its tic commands (never 0x80 at a command
start) before the final 0x80, so it plays the same map and players for as long as the generated demo.
Usage: make-controls.py [tgt ...]; no arguments rebuilds wad and xml exactly as the published sets (they share one
generator seeded 591, wad first): rebuild those two only this way. tiff, png, demo and wadp each have their own
generator (wadp = the WAD prompt test's spec arm, wad junk rule)."""
import os, random, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))

TARGETS = {
    "wad":  ("lineup-1h/wad-codernext-r1",  "freedoom2-"),
    "xml":  ("lineup-1h/xml-codernext-r1",  "small_document"),
    "tiff": ("lineup-1h/tiff-codernext-r1", "not_kitty"),
    "png":  ("lineup-1h/png-codernext-r1",  "not_kitty"),
    "demo": ("demo/demo-codernext-r1",      "freedoom2-demo"),
    # follow-up of the WAD prompt test (pre-registered in experiments/recipes/wad-prompt.sh): the best arm's r1
    "wadp": ("wad-prompt/wadp-spec-codernext-r1", "freedoom2-"),
}

def build_target(tgt, gen):
    src_rel, stock = TARGETS[tgt]
    s = os.path.join("results/campaigns", src_rel, "initial_seeds")
    a = os.path.join(HERE, tgt + "-llmseeds")
    j = os.path.join(HERE, tgt + "-junk")
    for d in (a, j):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    for f in sorted(os.listdir(s)):
        p = os.path.join(s, f)
        if not os.path.isfile(p):
            continue
        shutil.copy(p, a)
        if f.startswith(stock):
            shutil.copy(p, j)
        else:
            b = open(p, "rb").read()
            if tgt == "demo" and len(b) >= 14:
                out = bytearray(b[:13])
                for i in range(13, len(b) - 1):
                    if (i - 13) % 4 == 0:
                        x = gen.getrandbits(8)
                        while x == 0x80:
                            x = gen.getrandbits(8)
                        out.append(x)
                    else:
                        out.append(gen.getrandbits(8))
                out.append(0x80)
                open(os.path.join(j, "junk-" + f), "wb").write(bytes(out))
            else:
                open(os.path.join(j, "junk-" + f), "wb").write(
                    b[:4] + bytes(gen.getrandbits(8) for _ in range(max(0, len(b) - 4))))
    print(tgt, len(os.listdir(a)), len(os.listdir(j)))

random.seed(591)
targets = sys.argv[1:] or ["wad", "xml"]
for tgt in targets:
    if tgt not in TARGETS:
        print(f"error: unknown target: {tgt}", file=sys.stderr)
        sys.exit(1)
for tgt in targets:
    s = os.path.join("results/campaigns", TARGETS[tgt][0], "initial_seeds")
    if not os.path.isdir(s):
        print(f"error: source not found: {s}", file=sys.stderr)
        sys.exit(1)
for tgt in targets:
    gen = random if tgt in ("wad", "xml") else random.Random(f"591-{tgt}")
    build_target(tgt, gen)
