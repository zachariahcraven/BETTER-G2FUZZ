"""Scheduler for generator and mutator selection."""
import json
import os
import random
import re
import time
from collections import defaultdict, deque

_SEED_RE = re.compile(r'^([A-Za-z0-9]+)-(\d+)_(\d+)(\.[^.]*)?$')


def generator_of(name):
    """Map a queue-entry or seed file name to its generator name, or None."""
    if not name:
        return None
    if name.startswith('id:'):
        orig = None
        for p in name.split(',')[1:]:
            if p.startswith('orig:'):
                orig = p.split(':', 1)[1]
                break
        if orig is None:
            return None
        name = orig
    m = _SEED_RE.match(name)
    if m:
        return '%s-%s.py' % (m.group(1), m.group(2))
    return None


def _load_json(path, default=None):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except (OSError, ValueError, TypeError):
        return default


def _save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        json.dump(data, f)


def credit(out):
    """Return {generator: {'seeds': N, 'productive': M, 'finds': K}} for the queue in *out*."""
    queue_dir = os.path.join(out, 'queue')
    if not os.path.isdir(queue_dir):
        return {}

    info = {}
    for fname in os.listdir(queue_dir):
        fpath = os.path.join(queue_dir, fname)
        if not os.path.isfile(fpath) or not fname.startswith('id:'):
            continue
        parts = fname.split(',')
        file_id = parts[0].split(':', 1)[1]
        if not file_id.isdigit():
            continue
        is_seed = False
        parents = []
        gen = None
        for p in parts[1:]:
            if p.startswith('orig:'):
                is_seed = True
                gen = generator_of(fname)
            elif p.startswith('src:'):
                src = p.split(':', 1)[1]
                parents = src.split('+') if '+' in src else [src]
        info[file_id] = {'is_seed': is_seed, 'generator': gen, 'parents': parents}

    if not info:
        return {}

    children = defaultdict(list)
    for fid, e in info.items():
        for p in e['parents']:
            if p in info:
                children[p].append(fid)

    gen_seeds = defaultdict(list)
    for fid, e in info.items():
        if e['is_seed'] and e['generator']:
            gen_seeds[e['generator']].append(fid)

    result = {}
    for gen, seeds in gen_seeds.items():
        all_desc = set()
        productive = 0
        for seed in seeds:
            visited = set()
            dq = deque([seed])
            has_child = False
            while dq:
                curr = dq.popleft()
                for child in children.get(curr, []):
                    if child not in visited:
                        visited.add(child)
                        has_child = True
                        dq.append(child)
            if has_child:
                productive += 1
            all_desc |= visited
        finds = sum(1 for fid in all_desc if not info[fid]['is_seed'])
        result[gen] = {'seeds': len(seeds), 'productive': productive, 'finds': finds}
    return result


def family(generator, relationship):
    """Return the transitive closure of *generator* under *relationship* (cycle-safe)."""
    seen = set()
    stack = [generator]
    while stack:
        curr = stack.pop()
        if curr in seen:
            continue
        seen.add(curr)
        for child in relationship.get(curr, []):
            stack.append(child)
    return seen


def _mode():
    return os.environ.get('G2F_SCHEDULER', 'random')


def _log(out, entry):
    path = os.path.join(out, 'mutation_log', 'scheduler.jsonl')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'a') as f:
        f.write(json.dumps(entry) + '\n')


def _rng_choice(rng, seq):
    if rng is None:
        return random.choice(seq)
    return rng.choice(seq)


def _rng_beta(rng, a, b):
    if rng is None:
        return random.betavariate(a, b)
    return rng.betavariate(a, b)


def _generator_arm(gen, cred, rel):
    fam = family(gen, rel)
    total_seeds = 0
    total_prod = 0
    for g in fam:
        c = cred.get(g, {})
        total_seeds += c.get('seeds', 0)
        total_prod += c.get('productive', 0)
    return total_prod + 1, (total_seeds - total_prod) + 1


def _bandit_pick(candidates, out, rng, kind, compute_arm):
    arms = {}
    best = None
    best_val = -1.0
    for c in candidates:
        a, b = compute_arm(c)
        sample = _rng_beta(rng, a, b)
        arms[c] = {'a': a, 'b': b, 'sample': sample}
        if sample > best_val:
            best_val = sample
            best = c
    entry = {'time': time.time(), 'kind': kind, 'choice': best, 'arms': arms}
    if kind == 'generator':
        queue_dir = os.path.join(out, 'queue')
        if os.path.isdir(queue_dir):
            entry['queue'] = len(
                [f for f in os.listdir(queue_dir)
                 if os.path.isfile(os.path.join(queue_dir, f))])
    _log(out, entry)
    return best


def pick_generator(candidates, out, rng=None):
    """Pick a generator from *candidates* using the configured scheduler mode."""
    mode = _mode()
    if mode == 'bandit':
        cred = credit(out)
        rel = _load_json(os.path.join(out, 'mutation_log', 'relationship.json'), {})
        if rel is None:
            rel = {}
        return _bandit_pick(candidates, out, rng, 'generator',
                            lambda c: _generator_arm(c, cred, rel))
    elif mode == 'oracle':
        ranking_path = os.environ.get('G2F_ORACLE_RANKING')
        if not ranking_path:
            raise RuntimeError("G2F_ORACLE_RANKING environment variable is unset")
        
        ranking = _load_json(ranking_path)
        if ranking is None:
            raise RuntimeError("Ranking file %s is missing or unreadable" % ranking_path)
        if not isinstance(ranking, list):
            raise RuntimeError("Ranking file %s does not contain a JSON list" % ranking_path)
        
        best_cand = None
        best_pos = len(ranking) + 1
        
        for c in candidates:
            try:
                pos = ranking.index(c)
                if pos < best_pos:
                    best_pos = pos
                    best_cand = c
            except ValueError:
                continue
        
        ranked = best_cand is not None
        choice = best_cand if ranked else _rng_choice(rng, candidates)
        
        _log(out, {
            'time': time.time(),
            'kind': 'generator',
            'mode': 'oracle',
            'choice': choice,
            'ranked': ranked
        })
        return choice

    return _rng_choice(rng, candidates)


def mutator_stats(out, now=None):
    """Return {mutator: [a, b]} Beta parameters from recorded mutations."""
    if now is None:
        now = time.time()
    pending_sec = float(os.environ.get('G2F_BANDIT_PENDING_SEC', '300'))

    path = os.path.join(out, 'mutation_log', 'scheduler.json')
    state = _load_json(path, None)
    if not isinstance(state, dict):
        state = {'mutations': []}

    cred = credit(out)
    counts = defaultdict(lambda: [0, 0])
    seen_mutators = set()

    for m in state.get('mutations', []):
        mutator = m.get('mutator')
        child = m.get('child')
        t = m.get('time', 0)
        seen_mutators.add(mutator)
        if child is None:                                        # failed mutation
            counts[mutator][1] += 1
        elif cred.get(child, {}).get('productive', 0) > 0:      # its seeds found something
            counts[mutator][0] += 1
        elif now - t >= pending_sec:                             # nothing after the wait
            counts[mutator][1] += 1                              # (else still pending)

    result = {}
    for mutator in seen_mutators:
        s, f = counts.get(mutator, [0, 0])
        result[mutator] = [s + 1, f + 1]
    return result


def pick_mutator(mutators, out, rng=None):
    """Pick a mutator from *mutators* using the configured scheduler mode."""
    if _mode() == 'bandit':
        stats = mutator_stats(out)
        return _bandit_pick(mutators, out, rng, 'mutator',
                            lambda c: tuple(stats.get(c, [1, 1])))
    return _rng_choice(rng, mutators)


def record_mutation(out, mutator, child, now=None):
    """Append a mutation record to the scheduler state file."""
    if now is None:
        now = time.time()
    path = os.path.join(out, 'mutation_log', 'scheduler.json')
    state = _load_json(path, None)
    if not isinstance(state, dict) or 'mutations' not in state:
        state = {'mutations': []}
    state['mutations'].append({'mutator': mutator, 'child': child, 'time': now})
    _save_json(path, state)
