# A01-mutators-warm-2h

**Question:** once AFL++ has stalled, which LLM mutator finds coverage it can't reach on its own? Upstream's mix
(feature, structure, pattern), features named by the model (`rare`), features found in web documents (`web`), or the
mix without pattern mutation? And how much does AFL++ alone still find from the same point?
**Owner:** n59m742. **Status:** planned (after A00; on the image and targets with the ALF-1 guard). **Started:** –

## Design (changed 2026-11-13: a warm-start screen instead of a 6 h round)
- Round A01 of [docs/ALFRED-ROUNDS.md](../../docs/ALFRED-ROUNDS.md).
- **Why not 6 h from fresh seeds (A00's evidence, 280 finished campaigns):**
  - Every arm, plain AFL++ too, has about 93% of its 6 h coverage after 1 h: the first hour is AFL++'s own easy
    progress, and the LLM's share is in the tail.
  - In stall mode the first LLM step comes at a median of 74 min, and a 6 h campaign takes a median of 6 steps; 55 of
    70 control campaigns kept no LLM seed at all.
  - AFL++ keeps about 0.07-0.10 LLM seeds per step in every mode. A 6 h stall-mode round would give each arm about
    450 steps and about 35 kept seeds: too few to tell mutators apart.
- **Warm start** (`seeds = warm:...`, `scripts/fuzz reuse --queue`): each campaign starts from A00's
  `control/<target>-r<rep>` after its 6 h: its whole queue (AFL++'s finds and the LLM seeds it kept) as the seeds,
  plus its generators and feature lists. AFL++ has stalled there, so new coverage is rare and an LLM seed that adds
  some stands out. Every arm's rep r starts from the same campaign: a paired comparison.
- **Continuous LLM steps** (`G2F_LLM_MODE=continuous`) in every LLM arm: about 25 steps per campaign per hour, so
  15 targets x 5 reps x 2 h is about 1,900 steps per arm.
- **Arms:**
  - `control`: upstream's mutators (feature, structure, pattern).
  - `rare`: every step runs Rare-Feature Directed Mutation: the LLM names features of the parent's format that no
    generator has yet, and one of them extends the parent generator.
  - `web`: as `rare`, but the feature comes from documents found on the web at that step (free sources: Wikipedia,
    NVD, Stack Overflow, GitHub issues, and the pages those link to), checked for relevance (part of the file),
    grounding and novelty. Each campaign's ledger remembers features and documents.
  - `no-pattern`: feature and structure only.
  - `afl-only`: the same warm start with no LLM step (`G2F_PLATEAU_SEC=1000000`): what AFL++ alone still finds.
- **Runs:** 15 targets x 5 reps x 5 arms = 375 campaigns of 2 h (about 750 campaign-hours, under half of a 6 h
  round), gpt-oss-20b on one qc-h100 server, quantumcore first with the class priority account as overflow.
- **Measures:**
  - edges at the end (`scripts/compare`; all arms of a rep start from the same queue, so the difference is the gain);
  - LLM seeds kept per step and per mutator (`scripts/compare`'s LLM table), and their descendants
    (`scripts/lineage`);
  - for `web`: `scripts/compare`'s web table.
- **Decision:** a screen. A mutator that beats `control` here (by the acceptance rule's coverage test, or clearly on
  kept seeds per step) is confirmed in a normal 6 h round before it becomes the default.
- **Caveats:**
  - Continuous mode isn't harmless everywhere: in A00 it ended lcms at 438 edges against control's 1,179 (to be
    explained in A00's analysis). Here every LLM arm runs continuous, so the comparison between them is fair, and
    `afl-only` shows whether continuous steps hurt a target.
  - The web arm's 75 campaigns share one address, so they take turns through one limiter for all of Tempest
    (`py_utils/web_limit.py`): GitHub and NVD a request per 7 s, Stack Exchange per 300 s, Wikipedia per 1 s, other
    sites per 2 s, in total. That keeps Tempest within each API's limits (and other users unthrottled), at the cost
    of fewer documents per step: the web arm is tested under polite limits.
  - The targets are rebuilt before A01 (ALF-1's guard; CmpLog now works in gdk-pixbuf-pixdata and mp42aac), while the
    warm-start queues were found on A00's builds. The same for every arm.
  - A warm start measures what a mutator adds after AFL++ stalls, not how it shapes the queue early on.
- **Before launch:** A00 done (its control campaigns are the sources; the study waits for each), the new image and
  targets deployed, `scripts/study show A01-mutators-warm-2h` lists 375 campaigns.

## Results
Filled in when the round ends.
