# A01-stall-mutators-6h

**Question:** do stall steps that always target a new feature beat upstream's mix of stall mutators, and does it
matter whether the feature comes from the model's memory or from the web? Does dropping pattern mutation cost
anything?
**Owner:** n59m742. **Status:** planned (after A00). **Started:** –

## Design
- Round A01 of [docs/ALFRED-ROUNDS.md](../../docs/ALFRED-ROUNDS.md).
- **Arms:**
  - `control`: A00's winner, made the default in code (upstream's feature, structure and pattern mutators).
  - `rare`: `G2F_STALL_MUTATORS=rare`. Every stall step runs Rare-Feature Directed Mutation: the LLM names
    features of the parent's format that no generator has yet, and one of them extends the parent generator.
  - `web`: `G2F_STALL_MUTATORS=web`. As `rare`, but the feature comes from documents found on the web at that
    stall: free sources (Wikipedia, NVD's CVE descriptions, Stack Overflow, GitHub issues, and the pages those link
    to). The campaign's ledger remembers every feature and document, so each stall reads new documents.
  - `no-pattern`: `feature+structure` only.
- **One mutator per arm:**
  - A 6 h campaign takes a median of 3 stall steps (03, gpt-oss-20b; 90th percentile 9).
  - As one of four random picks, `rare` or `web` would run less than once per campaign. That's too rare to show
    an effect.
- **Why:**
  - In 04, stall-step seeds gave about 1% of queue descendants. "feature" gave 2.6 per generator, "structure" 2.9
    and "pattern" 0.7.
  - Rare-Feature mutation gave 31.5 per generator, but it ran only during seed generation (2026-11-08 lineage
    analysis, Tempest `~/.cache/alfred-analysis/`).
  - The web arm tests whether fresh documents bring features the model wouldn't think of, after the easy coverage is
    gone.
- **Runs:**
  - 15 targets, 5 reps of 6 h, gpt-oss-20b.
  - Seeds are shared, so the arms differ only in the switch: 300 campaigns plus 15 seed campaigns.
  - The shared seed campaign's feature lists are copied into each campaign (`scripts/fuzz reuse`), so `rare` and
    `web` know what seed generation covered.
- **Extra measures:**
  - kept seeds per mutator (`scripts/compare`'s mutator table), next to coverage;
  - for `web`, `scripts/compare`'s web table: queries, documents read, features found, rejected as ungrounded or
    duplicate, generators made, per source.
- **Results can't be repeated exactly** for `web`, since the web changes. Each campaign's ledger and `web_docs/`
  keep what it read.
- **Before launch:** run `scripts/web-check` on a priority-partition node (the Friday checklist in
  ALFRED-ROUNDS.md). Then launch it as A00 (same accounts and commands).

## Results
Filled in when the round ends.
