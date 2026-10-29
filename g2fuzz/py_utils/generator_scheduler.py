import json
import math
import os
import random
import re
import tempfile


_DEFAULT_EXPLORATION = 1.0
_SOURCE_RE = re.compile(r"(?:^|,)src:([0-9]+)(?:\+([0-9]+))?(?:,|$)")
_ORIGINAL_RE = re.compile(r"(?:^|,)orig:([^,]+)(?:,|$)")
_QUEUE_ID_RE = re.compile(r"^id:([0-9]+)")
_GENERATOR_SEED_RE = re.compile(r"^(.*-[0-9]+)_")


def select_parent_generator(
    generators,
    scheduler=None,
    generator_dir=None,
    queue_dir=None,
    state_path=None,
    exploration=None,
):
    """Select a parent generator and update its persistent UCB state at each stall."""
    scheduler = scheduler or os.environ.get("G2F_GENERATOR_SCHEDULER", "random")
    if not generators:
        raise ValueError("cannot select a parent from an empty generator pool")

    if scheduler == "random":
        return random.choice(generators)
    if scheduler != "ucb":
        raise ValueError(
            "G2F_GENERATOR_SCHEDULER must be 'random' or 'ucb' "
            f"(got '{scheduler}')"
        )
    if not all((generator_dir, queue_dir, state_path)):
        raise ValueError(
            "UCB selection requires generator_dir, queue_dir, and state_path"
        )

    if exploration is None:
        exploration = os.environ.get(
            "G2F_UCB_EXPLORATION", str(_DEFAULT_EXPLORATION)
        )
    try:
        exploration = float(exploration)
    except (TypeError, ValueError) as error:
        raise ValueError("G2F_UCB_EXPLORATION must be a positive number") from error
    if not math.isfinite(exploration) or exploration <= 0:
        raise ValueError("G2F_UCB_EXPLORATION must be a positive finite number")

    generators = sorted(set(generators))
    all_generators = generators
    state = _load_state(state_path)
    generator_states = state.setdefault("generators", {})
    invalid_generators = set(state.get("invalid_generators", []))
    for generator in all_generators:
        generator_states.setdefault(
            generator, {"delta_p": 0.0, "children": [], "failures": 0}
        )

    root_generators = _harvest_queue(queue_dir, generator_states, state)
    _resolve_pending(
        state,
        generator_states,
        all_generators,
        root_generators,
    )
    invalid_generators = set(state.get("invalid_generators", []))
    generators = [
        generator
        for generator in all_generators
        if generator not in invalid_generators
    ]
    if not generators:
        raise ValueError("UCB has no eligible generator with a valid seed history")

    utilities = _seed_utilities(generators, generator_states)
    scores = _ucb_scores(generators, generator_states, utilities, exploration)
    best_score = max(scores.values())
    tied = [
        generator
        for generator, score in scores.items()
        if math.isclose(score, best_score, rel_tol=1e-12, abs_tol=1e-12)
    ]
    selected = random.choice(tied)
    state["pending"] = {
        "parent": selected,
        "generator_snapshot": all_generators,
    }
    _save_state(state_path, state)
    return selected


def _load_state(state_path):
    if not os.path.exists(state_path):
        return {"generators": {}, "last_harvested_queue_id": -1, "pending": None}
    try:
        with open(state_path, "r", encoding="utf-8") as state_file:
            state = json.load(state_file)
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read UCB scheduler state {state_path}: {error}") from error
    if not isinstance(state, dict) or not isinstance(state.get("generators", {}), dict):
        raise ValueError(f"invalid UCB scheduler state in {state_path}")
    state.setdefault("generators", {})
    state.setdefault("last_harvested_queue_id", -1)
    state.setdefault("pending", None)
    return state


def _save_state(state_path, state):
    state_dir = os.path.dirname(state_path) or "."
    os.makedirs(state_dir, exist_ok=True)
    fd, temporary_path = tempfile.mkstemp(prefix=".generator-scheduler-", dir=state_dir)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as state_file:
            json.dump(state, state_file, sort_keys=True)
            state_file.write("\n")
        os.replace(temporary_path, state_path)
    except OSError:
        try:
            os.unlink(temporary_path)
        except OSError:
            pass
        raise


def _generator_from_seed_name(seed_name):
    seed_name = os.path.basename(seed_name)
    match = _GENERATOR_SEED_RE.match(seed_name)
    return f"{match.group(1)}.py" if match else None


def _queue_entries(queue_dir):
    entries = []
    try:
        names = os.listdir(queue_dir)
    except OSError as error:
        raise RuntimeError(f"cannot list AFL queue {queue_dir}: {error}") from error
    for name in names:
        match = _QUEUE_ID_RE.match(name)
        if match:
            entries.append((int(match.group(1)), name))
    return sorted(entries)


def _harvest_queue(queue_dir, generator_states, state):
    owners_by_queue_id = {}
    generated_seed_roots = set()
    last_harvested_queue_id = int(state["last_harvested_queue_id"])
    new_credits = {}

    entries = _queue_entries(queue_dir)
    for queue_id, name in entries:
        original_match = _ORIGINAL_RE.search(name)
        if original_match:
            generator = _generator_from_seed_name(original_match.group(1))
            if generator in generator_states:
                owners_by_queue_id[queue_id] = {generator}
                generated_seed_roots.add(generator)
                continue

        source_match = _SOURCE_RE.search(name)
        if not source_match:
            continue
        source_ids = [int(source_id) for source_id in source_match.groups() if source_id]
        source_owners = set()
        for source_id in source_ids:
            source_owners.update(owners_by_queue_id.get(source_id, set()))
        if not source_owners:
            continue

        owners_by_queue_id[queue_id] = source_owners
        if queue_id <= last_harvested_queue_id:
            continue
        credit = 1.0 / len(source_owners)
        for generator in source_owners:
            new_credits[generator] = new_credits.get(generator, 0.0) + credit

    for generator, credit in new_credits.items():
        generator_states[generator]["delta_p"] += credit
    if entries:
        state["last_harvested_queue_id"] = max(
            last_harvested_queue_id, entries[-1][0]
        )
    return generated_seed_roots


def _resolve_pending(state, generator_states, generators, generated_seed_roots):
    pending = state.get("pending")
    if not pending:
        return

    parent = pending.get("parent")
    prior_generators = set(pending.get("generator_snapshot", []))
    current_generators = set(generators)
    new_generators = current_generators - prior_generators
    valid_children = sorted(new_generators & generated_seed_roots)

    if parent not in generator_states:
        raise ValueError(f"pending UCB parent is missing from scheduler state: {parent}")
    parent_state = generator_states[parent]
    if valid_children:
        for child in valid_children:
            generator_states.setdefault(
                child, {"delta_p": 0.0, "children": [], "failures": 0}
            )
            if child not in parent_state["children"]:
                parent_state["children"].append(child)
    else:
        parent_state["failures"] += 1
        invalid_generators = set(state.get("invalid_generators", []))
        invalid_generators.update(new_generators)
        state["invalid_generators"] = sorted(invalid_generators)

    state["pending"] = None


def _seed_utilities(generators, generator_states):
    max_paths = max(
        (float(generator_states[name]["delta_p"]) for name in generators),
        default=0.0,
    )
    if max_paths <= 0:
        return {name: 0.0 for name in generators}
    denominator = math.log1p(max_paths)
    return {
        name: (
            math.log1p(float(generator_states[name]["delta_p"])) / denominator
            if float(generator_states[name]["delta_p"]) > 0
            else 0.0
        )
        for name in generators
    }


def _ucb_scores(generators, generator_states, utilities, exploration):
    pulls = {}
    means = {}
    for generator in generators:
        generator_state = generator_states[generator]
        children = [
            child
            for child in generator_state["children"]
            if child in utilities
        ]
        failures = int(generator_state["failures"])
        pulls[generator] = 1 + len(children) + failures
        total_utility = utilities[generator] + sum(
            utilities[child] for child in children
        )
        means[generator] = total_utility / pulls[generator]

    total_pulls = sum(pulls.values())
    log_total = math.log(total_pulls)
    return {
        generator: means[generator]
        + exploration * math.sqrt(log_total / pulls[generator])
        for generator in generators
    }
