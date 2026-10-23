# By hand (the upstream steps)

The raw commands `scripts/fuzz run` runs, for debugging or changing the pipeline. `scripts/fuzz shell <campaign>`,
then from `/eval`:

```bash
python /AFLplusplus/g2fuzz/program_gen.py --output ./jhead_output --program jhead     # Step II; skip if initial_seeds/ exists
mkdir -p initial_seeds && cp /AFLplusplus/testcases/images/jpeg/* jhead_output/default/gen_seeds/* initial_seeds/
afl-fuzz -i initial_seeds -o /tmp/jhead_output -c /targets/jhead.cmp -m 1024 -V 3600 -k /AFLplusplus/g2fuzz/ -- /targets/jhead.afl @@
```

- `-k /AFLplusplus/g2fuzz/` is required: it's where G2Fuzz's Python is.
- `-o /tmp/...` is 5–8x faster than `/eval`; copy it to `/eval` at the end (`run` does this for you).

**Note:** To ensure experimental fairness in the paper, all fuzzers — including G2FUZZ — are initialized with the
same set of initial seeds you prepared. Moreover, the fuzzing process in G2FUZZ is suspended during its seed
generation phase.
