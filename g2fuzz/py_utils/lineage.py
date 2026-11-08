"""Queue names with Alfred's synced LLM seeds mapped back to the generator that made them (ALFRED).

Upstream G2FUZZ's afl-fuzz put each generated seed in its queue as id:N,...,orig:<seed>, and the lineage code
(generator_mutation.build_tree, generator_scheduler._harvest_queue) reads orig: for a generator's own seeds and
src: for their descendants. In Alfred the seeds come in through AFL++'s sync from the LLM worker
(g2fuzz/llm_worker.py), named id:N,sync:llm,src:M,... where M is the id in the worker's own queue
(<afl output>/../llm/queue/id:M,orig:<seed>). src: there is not a local queue id, so read as one it would credit
the wrong parent. queue_names() rewrites those entries to id:N,orig:<seed>, and drops src: from entries synced
from any other instance, so both readers work unchanged.
"""
import os
import re

LLM_INSTANCE = "llm"
_SYNC_RE = re.compile(r"^(id:[0-9]+),sync:([^,]+),src:([0-9]+)")
_ID_RE = re.compile(r"^id:([0-9]+),orig:(.+)$")


def _llm_seeds(queue_dir):
    sync_queue = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(queue_dir))), LLM_INSTANCE, "queue")
    seeds = {}
    try:
        names = os.listdir(sync_queue)
    except OSError:
        return seeds
    for name in names:
        match = _ID_RE.match(name)
        if match:
            seeds[int(match.group(1))] = match.group(2)
    return seeds


def rewrite(names, llm_seeds):
    out = []
    for name in names:
        match = _SYNC_RE.match(name)
        if not match:
            out.append(name)
            continue
        entry, party, src = match.group(1), match.group(2), int(match.group(3))
        if party == LLM_INSTANCE and src in llm_seeds:
            out.append(f"{entry},orig:{llm_seeds[src]}")
        else:
            out.append(f"{entry},sync:{party}")
    return out


def queue_names(queue_dir):
    """The file names in an AFL++ queue folder, with synced entries rewritten as described above."""
    names = [f for f in os.listdir(queue_dir) if os.path.isfile(os.path.join(queue_dir, f))]
    if not any(",sync:" in name for name in names):
        return names
    return rewrite(names, _llm_seeds(queue_dir))
