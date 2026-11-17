---

kanban-plugin: board

---

## Todo

- [ ] Check round (3 models, 6 h) and 24 h final study on 28 targets (ends ~2026-12-02) ^card-7
- [ ] Verdict: do LLM stall mutators add coverage over AFL++ alone? (from A01 + A03; stop rule inside) [[threads/card-14|thread]] ^card-14

## Doing

## Needs Human

## Review

- [ ] #nom-nom A03 final row (15 targets) and A04: prior run for the uncovered lists of the other 13 targets [[threads/card-16|thread]] ^card-16

## Done

- [x] #nom-nom Memory limit for LLM-written generator scripts (OOM kills in 21 of 70 continuous uncovered campaigns) [[threads/card-15|thread]] ^card-15
- [x] #nom-nom Launch A01-mutators-warm-2h, then A03 scouts; rounds stop 2026-11-27 [[threads/card-6|thread]] ^card-6
- [x] #nom-nom Relaunch A02, then A00 freetype2 reruns, on Tempest (owned by session alfred-tweak-rounds-study) [[threads/card-2|thread]] ^card-2
- [x] #nom-nom New stall mutator "uncovered": show the LLM source of target functions the queue has not reached (A03 arm) [[threads/card-13|thread]] ^card-13
- [x] #nom-nom Deploy window after A02: new image, builders, rebuild all 25 targets (ALF-1 guard + CmpLog fix) [[threads/card-5|thread]] ^card-5
- [x] #nom-nom A00 analysis: pick the winner that feeds A01's control [[threads/card-3|thread]] ^card-3
- [x] #nom-nom Ask RCI to fix DNS on Tempest compute nodes (blocks the relaunch) [[threads/card-1|thread]] ^card-1
- [x] #nom-nom scripts/compare: "coverage jumps after LLM steps" measure for A01 [[threads/card-11|thread]] ^card-11
- [x] #nom-nom OURS-7: LLM worker dies on a gen_seeds file it cannot delete (3 A00 continuous campaigns) [[threads/card-12|thread]] ^card-12
- [x] #nom-nom Submit future Slurm jobs with --no-requeue (requeue caused duplicate campaigns) [[threads/card-8|thread]] ^card-8
- [x] #nom-nom Fonts hint switch for freetype2 seed generation (gpt-oss invents fontTools APIs) [[threads/card-9|thread]] ^card-9
- [x] #nom-nom OURS-5: retry open() on ERESTARTSYS in afl-fuzz [[threads/card-10|thread]] ^card-10
- [x] #nom-nom Commit and push the Mac clone (A01 redesign, web limiter, docs) [[threads/card-4|thread]] ^card-4