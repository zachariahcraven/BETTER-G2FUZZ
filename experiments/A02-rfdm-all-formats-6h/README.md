# A02-rfdm-all-formats-6h

**Question:** does running Rare-Feature Directed Mutation during seed generation for multi-format targets too
(`G2F_RFDM_ALL_FORMATS=1`) help them?
**Owner:** n59m742. **Status:** planned (beside A01). **Started:** –

## Design
- **Background:**
  - Upstream's `program_gen.py` runs 3 seed-generation rounds for a single-format target (synthesis, then 2 of
    Rare-Feature mutation), but only 1 for a target with several formats.
  - On single-format targets in 04, Rare-Feature mutation gave 16.2% of queue descendants, as much as synthesis.
  - The paper's Table 13 shows almost no mutation contribution on exactly its multi-format targets.
- **Arms:** `control` vs `rfdm-all`.
- **Targets:** the 4 multi-format ones: jhead, gdk-pixbuf-pixdata, imginfo and sndfile_fuzzer.
- **Runs:** 5 reps of 6 h, gpt-oss-20b, `seeds = fresh` (it is a setup switch): 40 campaigns, each with its own seed
  generation.
- **Cost:** it roughly doubles seed generation. Median setup times in 04 were 380–1,707 s on these targets.
- **Measures:**
  - Seed-generation time (`llm_calls.jsonl`), generators and seeds made, and t=0 coverage of `initial_seeds`.
  - Lineage: the `setup-rfdm` share, from `scripts/lineage`.
- **Launch:** start it once A01's 15 seed campaigns are done, so the two rounds don't both run 4 seed generations at
  once on the one gpt-oss-20b server.

## Results
Filled in when the round ends.
