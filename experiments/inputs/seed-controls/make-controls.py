#!/usr/bin/env python3
"""Rebuilds the seed-control sets next to this file from two finished campaigns (run from the project
root): <tgt>-llmseeds = that campaign's initial_seeds as they are; <tgt>-junk = the same stock files,
plus random bytes for each generated file, the same size and keeping its first 4 bytes (seed 591)."""
import os, random, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
random.seed(591)
for tgt, src, stock in (("wad", "lineup-1h/wad-codernext-r1", "freedoom2-"), ("xml", "lineup-1h/xml-codernext-r1", "small_document")):
    s = os.path.join("results/campaigns", src, "initial_seeds")
    a, j = os.path.join(HERE, tgt + "-llmseeds"), os.path.join(HERE, tgt + "-junk")
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
            open(os.path.join(j, "junk-" + f), "wb").write(b[:4] + bytes(random.getrandbits(8) for _ in range(max(0, len(b) - 4))))
    print(tgt, len(os.listdir(a)), len(os.listdir(j)))
