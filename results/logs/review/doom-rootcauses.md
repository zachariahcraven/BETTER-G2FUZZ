# Review record: doom-rootcauses

- Files: experiments/inputs/doom-rootcause-rules.csv (Claude, from the source line of every top frame), experiments/analysis/doom-rootcauses (Claude)
- Spec: tasks/rootcause.md (+ checklists/9-rootcause.md)
- Author: claude
- Status (computed from the passes below): ESCALATE (driver rule: clean streak 5 since the last fix, families gemma, non-author yes)
- Manager's note: ESCALATED (pass cap reached because the 127-rule review was split into 4 chunks x 2 models) and resolved by Claude: the 3 valid qwen38 findings were fixed in the rules; after the fix, qwen38 reviewed the tool (2 clean passes) and gemma re-reviewed the 3 corrected rule chunks (3 clean passes). By the strict driver rule the last 3 passes are one family (gemma); a qwen38 re-review of the corrected chunks was not possible (its server was requeued). Gemma was clean on all 127 rules before the fix as well.

## Events (in order)

- Pass 1: gemma, checklist 1-spec -> **clean** (2026-10-16 09:38:18)
- Pass 2: gemma, checklist 9-rootcause rules 1-32 -> **clean** (2026-10-16 09:56:15)
- Pass 3: qwen38, checklist 9-rootcause rules 1-32 -> **findings** (2026-10-16 09:59:23)
  - F1 [medium] experiments/inputs/doom-rootcause-rules.csv:22: Rule for P_SetThingPosition p_maputl.c:407 is classified 'map-index' but the basis describes a BSP traversal failure (subsector pointer made invalid by R_PointInSubsector following unchecked NODES children), which matches the 'bsp' class definition ('NODES children not validated … out of range') rather than map-index.
- Pass 4: gemma, checklist 9-rootcause rules 33-64 -> **clean** (2026-10-16 09:56:23)
- Pass 5: qwen38, checklist 9-rootcause rules 33-64 -> **findings** (2026-10-16 10:00:51)
  - F1 [medium] experiments/inputs/doom-rootcause-rules.csv:16: Rule for T_MovePlane p_floor.c:162 has confidence 'ambiguous' but the basis names only one mechanism ("sector->ceilingheight via a door thinker's sector pointer"). The door thinker's sector pointer is set once at door-creation time from the linedef's sector index; the only plausible cause is an unchecked map-lump index (map-index). There is no second class named or reasonably implied by the basis. Per the spec, 'ambiguous' requires 'two classes possible; basis names both.'
- Pass 6: gemma, checklist 9-rootcause rules 65-96 -> **clean** (2026-10-16 09:56:28)
- Pass 7: qwen38, checklist 9-rootcause rules 65-96 -> **clean** (2026-10-16 09:59:59)
- Pass 8: gemma, checklist 9-rootcause rules 97-127 -> **clean** (2026-10-16 09:56:00)
- Pass 9: qwen38, checklist 9-rootcause rules 97-127 -> **findings** (2026-10-16 10:03:56)
  - F1 [low] experiments/inputs/doom-rootcause-rules.csv:22: Basis for Z_Malloc z_zone.c:241 says 'rover->next: zone block list corrupt' but the source line is `rover = base->next;` — the dereferenced pointer is `base`, not `rover`. The basis misidentifies which variable is being accessed.
- Judgement (pass 3, F1): **valid**: P_SetThingPosition:407: ss comes from R_PointInSubsector -> an out-of-range ss means a NODES child index -> class bsp (was map-index).
- Judgement (pass 5, F1): **valid**: T_MovePlane:162 'ambiguous' but basis named one mechanism -> basis now names map-index and secondary.
- Judgement (pass 9, F1): **valid**: Z_Malloc:241: dereferenced pointer is base (rover = base->next) -> basis corrected.
- Fix round 1: rules corrected by Claude
- Pass 10: qwen38, checklist 5-errors (tool) -> **clean** (2026-10-16 10:07:06)
- Pass 11: qwen38, checklist 6-stats (tool) -> **clean** (2026-10-16 10:06:48)
- Pass 12: gemma, checklist 9-rootcause rules 1-32 (post-fix) -> **clean** (2026-10-16 13:08:24)
- Pass 13: gemma, checklist 9-rootcause rules 33-64 (post-fix) -> **clean** (2026-10-16 13:10:50)
- Pass 14: gemma, checklist 9-rootcause rules 97-127 (post-fix) -> **clean** (2026-10-16 13:13:04)
