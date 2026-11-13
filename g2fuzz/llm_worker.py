#!/usr/bin/env python3
"""llm_worker.py: Alfred's LLM side of G2FUZZ, run next to afl-fuzz instead of inside it.

Upstream G2FUZZ patches afl-fuzz to stop fuzzing for each LLM step (system("python generator_mutation.py ..."))
and to put every generated seed straight into its queue, without AFL++'s size checks (KNOWN_BUGS G2F-1). Alfred's
afl-fuzz is stock AFL++ 5.03c. This worker runs the same generator_mutation.py in its own process and hands the
seeds over the way any other fuzzer instance does (SymCC works the same way): it writes them to
<sync-dir>/queue/id:NNNNNN,orig:<seed> and AFL++ imports them at its next sync. AFL++ runs each one and keeps it
only if it reaches new coverage (save_if_interesting, so with the size checks), as id:...,sync:llm,src:NNNNNN.
The sync dir is a sibling of AFL++'s own output folder and holds an is_main_node file, so afl-fuzz (no -M/-S:
it configures itself as a secondary) syncs from it and fuzzes exactly as the --afl baseline does.

When a step runs (G2F_LLM_MODE):
  stall       (default) upstream's trigger: G2F_PLATEAU_SEC (300) without a new queue entry and since the last
              step ended, plus G2F_BACKOFF_SEC (60) for each step already taken
  continuous  a step as soon as the previous one ends, G2F_LLM_GAP_SEC (0) apart

Run from the campaign folder (generator_mutation.py reads ./model_setting.json), before exec'ing afl-fuzz:
  python /AFLplusplus/g2fuzz/llm_worker.py --afl-out out/default --sync-dir out/llm > llm-worker.log 2>&1 &
  exec afl-fuzz -i seeds -o out ...
It exits when afl-fuzz does (it watches its parent and fuzzer_stats' fuzzer_pid), stopping a running step.
Each step appends a JSON line to <sync-dir>/steps.jsonl, and the log prints "==== Gen-M start ====" and
"==== Gen-M end ====" around it (scripts/fuzz watch and scripts/study results count these).
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time

MAX_FILE = 1024 * 1024          # AFL++'s MAX_FILE: larger files are never imported
QUEUE_ID_RE = re.compile(r"^id:([0-9]+)")
HERE = os.path.dirname(os.path.abspath(__file__))


def log(msg):
    print(time.strftime("%Y-%m-%d %H:%M:%S ") + msg, flush=True)


def env_int(name, default):
    value = os.environ.get(name, "")
    if value == "":
        return default
    try:
        number = int(value)
    except ValueError:
        sys.exit(f"llm_worker: {name} must be a whole number of seconds (got {value!r})")
    if number < 0:
        sys.exit(f"llm_worker: {name} must not be negative (got {number})")
    return number


def read_stats(path):
    stats = {}
    try:
        with open(path) as f:
            for line in f:
                key, sep, value = line.partition(":")
                if sep:
                    stats[key.strip()] = value.strip()
    except OSError:
        pass
    return stats


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def max_queue_id(queue_dir):
    highest = -1
    try:
        with os.scandir(queue_dir) as entries:
            for entry in entries:
                match = QUEUE_ID_RE.match(entry.name)
                if match:
                    highest = max(highest, int(match.group(1)))
    except OSError:
        pass
    return highest


MOVED_RE = re.compile(r"---- Moved \S+ to \S*/gen_seeds/(.+-\d+)_\d+")


def step_info(mutate_log, offset):
    """The mutator a step picked and the generator it made (None if none), from its part of mutate_log
    (generator_mutation.py prints "cur_mutator: <m>", and mv_files "---- Moved ... gen_seeds/<generator>_<n>.<ext>").
    The rare and web mutators also print "---- step: {json}" (feature, and the web search's numbers): merged in."""
    info = {"mutator": None, "generator": None}
    try:
        with open(mutate_log, "rb") as f:
            f.seek(offset)
            text = f.read().decode("utf-8", "replace")
    except OSError:
        return info
    for line in text.splitlines():
        if line.startswith("cur_mutator:"):
            info["mutator"] = line.split(":", 1)[1].strip()
        elif line.startswith("---- step: "):   # rare/web: the feature targeted and, for web, its search numbers
            try:
                extra = json.loads(line[len("---- step: "):])
            except ValueError:
                continue
            if isinstance(extra, dict):
                info.update({k: v for k, v in extra.items() if k not in ("mutator", "generator")})
        elif info["generator"] is None:
            m = MOVED_RE.search(line)
            if m:
                info["generator"] = m.group(1)
    return info


class Worker:
    def __init__(self, args):
        self.afl_out = os.path.abspath(args.afl_out)
        self.sync_dir = os.path.abspath(args.sync_dir)
        self.queue = os.path.join(self.sync_dir, "queue")
        self.staging = os.path.join(self.sync_dir, ".staging")
        self.gen_seeds = os.path.join(self.afl_out, "gen_seeds")
        self.mode = os.environ.get("G2F_LLM_MODE", "stall") or "stall"
        if self.mode not in ("stall", "continuous"):
            sys.exit(f"llm_worker: G2F_LLM_MODE must be stall or continuous (got {self.mode!r})")
        self.plateau = env_int("G2F_PLATEAU_SEC", 300)
        self.backoff = env_int("G2F_BACKOFF_SEC", 60)
        self.gap = env_int("G2F_LLM_GAP_SEC", 0)
        self.poll = args.poll
        self.script = os.path.abspath(args.mutation_script)
        self.parent = os.getppid()
        self.afl_pid = None
        self.child = None
        self.stopping = False
        self.steps = 0
        self.llm_ms = 0
        os.makedirs(self.queue, exist_ok=True)
        os.makedirs(self.staging, exist_ok=True)
        # AFL++ secondaries (a lone afl-fuzz is one) import only from an instance marked main
        open(os.path.join(self.sync_dir, "is_main_node"), "a").close()
        self.next_id = max_queue_id(self.queue) + 1      # resume-safe: ids only ever grow
        self.last_mtime = 0
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, self.on_signal)

    def on_signal(self, signum, _frame):
        self.stopping = True
        log(f"signal {signum}: stopping")
        self.kill_child()

    def kill_child(self):
        if self.child and self.child.poll() is None:
            try:
                os.killpg(self.child.pid, signal.SIGTERM)
                self.child.wait(timeout=10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(self.child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def afl_gone(self):
        if os.getppid() != self.parent:          # the exec'd afl-fuzz (our parent) has exited
            return True
        return self.afl_pid is not None and not alive(self.afl_pid)

    def sleep(self, secs):
        end = time.time() + secs
        while not self.stopping and time.time() < end:
            if self.afl_gone():
                self.stopping = True
                log("afl-fuzz has exited: stopping")
                return
            time.sleep(min(1.0, max(0.0, end - time.time())))

    def wait_for_afl(self):
        stats_path = os.path.join(self.afl_out, "fuzzer_stats")
        while not self.stopping:
            stats = read_stats(stats_path)
            if stats.get("fuzzer_pid", "").isdigit() and stats.get("start_time", "").isdigit():
                self.afl_pid = int(stats["fuzzer_pid"])
                return int(stats["start_time"])
            self.sleep(self.poll)
        return None

    def run_step(self):
        self.steps += 1
        start = time.time()
        log(f"==== Gen-M start ==== step {self.steps}")
        cmd = [sys.executable, self.script, "--output", self.afl_out]
        mutate_log = os.path.join(self.afl_out, "mutate_log")
        offset = os.path.getsize(mutate_log) if os.path.exists(mutate_log) else 0
        with open(mutate_log, "a") as out:
            self.child = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
            while self.child.poll() is None:
                if self.stopping or self.afl_gone():
                    self.stopping = True
                    log("afl-fuzz has exited during the step: stopping it")
                    self.kill_child()
                    break
                time.sleep(1)
        rc = self.child.returncode
        self.child = None
        secs = time.time() - start
        self.llm_ms += int(secs * 1000)
        record = {"step": self.steps, "mode": self.mode, "start": round(start, 3), "secs": round(secs, 3),
                  "exit": rc, "stopped": self.stopping}
        record.update(step_info(mutate_log, offset))
        record.update(self.publish() if not self.stopping else {"seeds": 0, "published": 0})
        with open(os.path.join(self.sync_dir, "steps.jsonl"), "a") as f:
            f.write(json.dumps(record) + "\n")
        # the line upstream's afl-fuzz wrote after each step (README: seeds added and time spent in the LLM)
        with open(os.path.join(self.afl_out, "gen_seeds_energy_log"), "a") as f:
            f.write(f"\n\ncnt:{record['published']}\ncost_time:{self.llm_ms}\n")
        log(f"==== Gen-M end ==== step {self.steps}: exit {rc}, {secs:.0f}s, "
            f"{record['seeds']} seeds, {record['published']} handed to AFL++")
        if record["published"] and self.afl_pid and alive(self.afl_pid):
            os.kill(self.afl_pid, signal.SIGUSR2)   # AFL++ 5.03c: sync now instead of at the next sync time
        return time.time()

    def publish(self):
        """Move gen_seeds/'s files into the sync queue. Like upstream, only regular files are seeds and gen_seeds/
        is emptied of them afterwards. Empty and over-1-MiB files are dropped here (AFL++ would skip them)."""
        counts = {"seeds": 0, "published": 0, "empty": 0, "too_big": 0}
        try:
            names = sorted(os.listdir(self.gen_seeds))
        except OSError:
            return counts
        for name in names:
            path = os.path.join(self.gen_seeds, name)
            if not os.path.isfile(path) or os.path.islink(path):
                continue
            counts["seeds"] += 1
            size = os.path.getsize(path)
            if size == 0 or size > MAX_FILE:
                counts["empty" if size == 0 else "too_big"] += 1
                os.remove(path)
                continue
            # write fully elsewhere, then rename: AFL++ never sees a partial file, and ids appear in order
            # (it remembers the highest id it has synced and skips lower ones)
            final = os.path.join(self.queue, "id:%06u,orig:%s" % (self.next_id, name.replace(",", "_")))
            tmp = os.path.join(self.staging, "%06u" % self.next_id)
            shutil.move(path, tmp)
            os.rename(tmp, final)
            self.next_id += 1
            counts["published"] += 1
        return counts

    def run(self):
        log(f"mode {self.mode}; AFL++ output {self.afl_out}; seeds go to {self.queue}")
        if self.mode == "stall":
            # same wording as upstream's patched afl-fuzz printed (scripts/fuzz watch reads it)
            log(f"G2F: LLM step after {self.plateau}s without finds (+{self.backoff}s per step)")
        else:
            log(f"G2F: continuous LLM steps, {self.gap}s apart")
        t0 = self.wait_for_afl()
        if t0 is None:
            return 0
        log(f"afl-fuzz pid {self.afl_pid} started at {t0}")
        queue_dir = os.path.join(self.afl_out, "queue")
        stats_path = os.path.join(self.afl_out, "fuzzer_stats")
        seen_id = max_queue_id(queue_dir)
        last_find = 0          # upstream: last_find_time is 0 until the first new queue entry
        last_step_end = t0     # upstream: gen_last_update starts when the fuzzing loop does
        while not self.stopping:
            now = time.time()
            if self.mode == "continuous":
                if now - last_step_end >= self.gap or self.steps == 0:
                    last_step_end = self.run_step()
                    continue
            else:
                highest = max_queue_id(queue_dir)
                if highest > seen_id:
                    seen_id, last_find = highest, now
                stat_find = read_stats(stats_path).get("last_find", "0")
                if stat_find.isdigit():
                    last_find = max(last_find, int(stat_find))
                wait = self.plateau + self.steps * self.backoff
                if now - last_find > wait and now - last_step_end > wait:
                    last_step_end = self.run_step()
                    seen_id = max(seen_id, max_queue_id(queue_dir))
                    continue
            self.sleep(self.poll)
        log(f"done: {self.steps} steps, {self.llm_ms / 1000:.0f}s in LLM steps, {self.next_id} seeds handed over")
        return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--afl-out", required=True, help="afl-fuzz's own output folder, e.g. out/default")
    parser.add_argument("--sync-dir", required=True, help="this worker's instance folder next to it, e.g. out/llm")
    parser.add_argument("--poll", type=float, default=5.0, help="seconds between checks of AFL++'s progress")
    parser.add_argument("--mutation-script", default=os.path.join(HERE, "generator_mutation.py"),
                        help="what each step runs with --output <afl-out> (tests replace it)")
    args = parser.parse_args()
    return Worker(args).run()


if __name__ == "__main__":
    sys.exit(main())
