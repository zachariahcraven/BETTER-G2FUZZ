# card-15: Memory limit for LLM-written generator scripts (OOM kills in 21 of 70 continuous uncovered campaigns)

## Note nom-nom 2026-11-15 21:13
Files: g2fuzz/py_utils/func.py, g2fuzz/tests/test_gen_limits.py, docs/ALFRED.md

## Note nom-nom 2026-11-15 21:13
**Cause (2026-11-15):** with `uncovered`, the LLM writes generators that make very large files to reach size checks in the target (`huge_file.bin`, `large_file_4_1024M.txt`, `tga_big_size.tga`, ...). 64 files over 50 MB in A03's uncovered-cont arm; the arm's folder is 128 GB (control: 6.7 GB). The jobs have 8 GB, so the kernel killed the generator process; the campaign went on.

**Fix:** `run_cmd` in `py_utils/func.py` sets two limits on the generator process: address space `G2F_GEN_MEM_MB` (default 6144) and file size `G2F_GEN_FILE_MB` (default 64). 0 = off. The worker already drops files over 1 MiB, so no usable seed is lost.

**Tested** in the image on Tempest: `g2fuzz/tests/test_gen_limits.py` 4 of 4 pass (small file passes, 4 MB file fails at a 1 MB limit, 1 GB allocation fails at 512 MB, limits off). `test_uncovered.py` 7 pass, `test_mutators.py` 18 pass. numpy and PIL import and run under the 6144 MB limit.

**Not done:** the 128 GB already on Tempest in `experiments/A03-uncovered-6h/campaigns/uncovered-cont/*/*_output/default/tmp` is left as it is. Deleting it is the human's call. Not in an image yet: needs approve, push, then an image build.

## Note nom-nom 2026-11-15 21:13
Brief: now: generators get a 6 GB memory and 64 MB file limit; tests pass in the image
next: image build after push, then the check round uses it
you: approve, then git push origin alfred

## Note nom-nom 2026-11-15 21:13
Review:
##### To check
- Open `g2fuzz/py_utils/func.py`: `_generator_limits` sets RLIMIT_AS and RLIMIT_FSIZE, and `run_cmd` passes it as `preexec_fn`.
- Open `docs/ALFRED.md`, "Generator limits": the two switches and their defaults (6144, 64) are named.
##### Changed
Generator scripts now run with a memory limit (6 GB) and a file-size limit (64 MB); both can be changed or turned off by environment variable.
Why: in A03 the `uncovered` generators wrote files of up to 1 GB, which caused OOM kills in 21 of 70 campaigns and 128 GB of leftovers.
I ran the new tests (4) and the mutator tests (25) in the image on Tempest: all pass.

## Note human 2026-11-15 21:19
Approved and committed (d492cca).
