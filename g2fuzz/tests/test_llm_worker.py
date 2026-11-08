#!/usr/bin/env python3
"""Tests for g2fuzz/llm_worker.py and g2fuzz/py_utils/lineage.py, without AFL++, a GPU or an LLM.

A fake afl-fuzz (this file with --fake-afl) writes fuzzer_stats, counts SIGUSR2 and starts the worker as its child,
the way run.sh's exec makes afl-fuzz the worker's parent. A fake LLM step (--fake-step) writes seeds into gen_seeds/.
Run: python3 g2fuzz/tests/test_llm_worker.py   (Python 3.8+, stdlib only)
"""
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
G2F = os.path.dirname(HERE)
WORKER = os.path.join(G2F, "llm_worker.py")
sys.path.insert(0, os.path.join(G2F, "py_utils"))
import lineage  # noqa: E402


def running(pid):
    """Whether pid is still running. An exited process whose parent is gone waits as a zombie for whoever
    adopted it: in a container that is PID 1, which may be this test, so reap it here and count zombies as gone."""
    try:
        os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        pass
    try:
        with open(f"/proc/{pid}/stat") as f:
            if f.read().rsplit(")", 1)[1].split()[0] == "Z":
                return False
    except OSError:
        pass
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def read(path):
    with open(path) as f:
        return f.read()


def fake_step(out):
    """One LLM step: a normal seed, an empty one, one over 1 MiB, a folder, and a name with a comma."""
    seeds = os.path.join(out, "gen_seeds")
    os.makedirs(seeds, exist_ok=True)
    n = len(read(os.path.join(out, "mutate_log")).splitlines()) if os.path.exists(os.path.join(out, "mutate_log")) else 0
    with open(os.path.join(seeds, f"jpg-{n + 3}_1.jpg"), "wb") as f:
        f.write(b"\xff\xd8" + bytes([n]) * 100)
    open(os.path.join(seeds, f"jpg-{n + 3}_2.jpg"), "wb").close()
    with open(os.path.join(seeds, f"jpg-{n + 3}_3.jpg"), "wb") as f:
        f.write(b"x" * (1024 * 1024 + 1))
    with open(os.path.join(seeds, f"jpg-{n + 3}_4,x.jpg"), "wb") as f:
        f.write(b"comma")
    os.makedirs(os.path.join(seeds, "subdir"), exist_ok=True)
    print("fake step done", flush=True)
    time.sleep(float(os.environ.get("FAKE_STEP_SECS", "0")))


def fake_afl(out, sync, run_secs, worker_env):
    os.makedirs(os.path.join(out, "queue"), exist_ok=True)
    got = {"usr2": 0}

    def on_usr2(_s, _f):
        got["usr2"] += 1

    signal.signal(signal.SIGUSR2, on_usr2)
    log = open(os.path.join(os.path.dirname(out), "llm-worker.log"), "w")  # noqa: SIM115 (the worker keeps it)
    env = dict(os.environ, **json.loads(worker_env))
    worker = subprocess.Popen([sys.executable, WORKER, "--afl-out", out, "--sync-dir", sync, "--poll", "0.2",
                               "--mutation-script", os.path.abspath(__file__)],
                              stdout=log, stderr=subprocess.STDOUT, env=env)
    start = int(time.time())
    end = time.time() + run_secs
    while time.time() < end:
        with open(os.path.join(out, "fuzzer_stats"), "w") as f:
            f.write(f"start_time        : {start}\nfuzzer_pid        : {os.getpid()}\nlast_find         : 0\n")
        time.sleep(0.2)
    with open(os.path.join(out, "usr2"), "w") as f:
        f.write(str(got["usr2"]))
    # exit without waiting: the worker must notice on its own (its parent is gone)
    with open(os.path.join(out, "worker_pid"), "w") as f:
        f.write(str(worker.pid))
    os._exit(0)


class WorkerTest(unittest.TestCase):
    def run_campaign(self, run_secs, **env):
        tmp = tempfile.mkdtemp(prefix="llm-worker-test.")
        out, sync = os.path.join(tmp, "out", "default"), os.path.join(tmp, "out", "llm")
        subprocess.run([sys.executable, __file__, "--fake-afl", out, sync, str(run_secs), json.dumps(env)],
                       check=True, timeout=run_secs + 30)
        pid = int(read(os.path.join(out, "worker_pid")))
        for _ in range(100):                      # the worker must exit within ~2 s of afl-fuzz
            if not running(pid):
                break
            time.sleep(0.1)
        else:
            os.kill(pid, signal.SIGKILL)
            self.fail("worker kept running after afl-fuzz exited")
        steps_file = os.path.join(sync, "steps.jsonl")
        steps = [json.loads(line) for line in read(steps_file).splitlines()] if os.path.exists(steps_file) else []
        return tmp, out, sync, steps

    def test_stall_trigger_publish_and_exit(self):
        tmp, out, sync, steps = self.run_campaign(5, G2F_PLATEAU_SEC="1", G2F_BACKOFF_SEC="0", G2F_LLM_MODE="stall")
        self.assertGreaterEqual(len(steps), 2, steps)
        first = steps[0]
        self.assertEqual((first["seeds"], first["published"], first["empty"], first["too_big"]), (4, 2, 1, 1))
        queue = sorted(os.listdir(os.path.join(sync, "queue")))
        self.assertTrue(queue[0].startswith("id:000000,orig:jpg-"), queue)
        self.assertFalse(any(",x" in q.split("orig:")[1] for q in queue), "comma kept in a seed name")
        ids = [int(q[3:9]) for q in queue]
        self.assertEqual(ids, list(range(len(ids))), "ids must be 0, 1, 2, ... in order")
        self.assertTrue(os.path.exists(os.path.join(sync, "is_main_node")))
        self.assertEqual([f for f in os.listdir(os.path.join(out, "gen_seeds")) if os.path.isfile(os.path.join(out, "gen_seeds", f))], [])
        self.assertGreaterEqual(int(read(os.path.join(out, "usr2"))), 1, "AFL++ was never asked to sync")
        log = read(os.path.join(tmp, "out", "llm-worker.log"))
        self.assertIn("G2F: LLM step after 1s without finds (+0s per step)", log)
        self.assertEqual(log.count("==== Gen-M start ===="), len(steps))
        self.assertIn("cnt:2", read(os.path.join(out, "gen_seeds_energy_log")))

    def test_no_step_before_plateau(self):
        _, _, _, steps = self.run_campaign(2, G2F_PLATEAU_SEC="60", G2F_LLM_MODE="stall")
        self.assertEqual(steps, [])

    def test_backoff_spaces_steps(self):
        _, _, _, steps = self.run_campaign(7, G2F_PLATEAU_SEC="1", G2F_BACKOFF_SEC="2", G2F_LLM_MODE="stall")
        # waits 1, 3, 5 s: two steps in 7 s, never three
        self.assertEqual(len(steps), 2, steps)

    def test_continuous(self):
        _, _, _, steps = self.run_campaign(3, G2F_LLM_MODE="continuous", G2F_PLATEAU_SEC="999")
        self.assertGreaterEqual(len(steps), 3, steps)

    def test_running_step_is_stopped(self):
        _, _, _, steps = self.run_campaign(3, G2F_PLATEAU_SEC="0", G2F_LLM_MODE="stall", FAKE_STEP_SECS="60")
        self.assertEqual(len(steps), 1, steps)
        self.assertTrue(steps[0]["stopped"])

    def test_bad_mode_refused(self):
        r = subprocess.run([sys.executable, WORKER, "--afl-out", "/nonexistent/a", "--sync-dir", tempfile.mkdtemp()],
                           env=dict(os.environ, G2F_LLM_MODE="sometimes"), capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("G2F_LLM_MODE must be stall or continuous", r.stderr)


class LineageTest(unittest.TestCase):
    def test_rewrite(self):
        names = ["id:000000,time:0,execs:0,orig:not_kitty.jpg",
                 "id:000001,time:0,execs:0,orig:jpg-1_1.jpg",
                 "id:000002,src:000001,time:5,execs:9,op:havoc,rep:2,+cov",
                 "id:000003,sync:llm,src:000007,time:9,execs:20,+cov",
                 "id:000004,src:000003,time:12,execs:40,op:havoc,rep:4,+cov",
                 "id:000005,sync:other,src:000001,time:13,execs:41",
                 "id:000006,sync:llm,src:000099,time:14,execs:42"]
        got = lineage.rewrite(names, {7: "jpg-16_2.jpg"})
        self.assertEqual(got[:3], names[:3])
        self.assertEqual(got[3], "id:000003,orig:jpg-16_2.jpg")
        self.assertEqual(got[4], names[4])
        self.assertEqual(got[5], "id:000005,sync:other")      # src: would point at a wrong local entry
        self.assertEqual(got[6], "id:000006,sync:llm")        # unknown worker id: no lineage

    def test_queue_names_reads_worker_queue(self):
        tmp = tempfile.mkdtemp()
        q, wq = os.path.join(tmp, "out", "default", "queue"), os.path.join(tmp, "out", "llm", "queue")
        os.makedirs(q); os.makedirs(wq); os.makedirs(os.path.join(q, ".state"))
        open(os.path.join(wq, "id:000004,orig:xmp-2_1.xmp"), "w").close()
        open(os.path.join(q, "id:000010,sync:llm,src:000004,time:1,execs:2,+cov"), "w").close()
        self.assertEqual(lineage.queue_names(q), ["id:000010,orig:xmp-2_1.xmp"])

    def test_scheduler_credits_synced_seed(self):
        sys.path.insert(0, G2F)
        from py_utils import generator_scheduler as gs
        tmp = tempfile.mkdtemp()
        q, wq, gens = (os.path.join(tmp, "out", "default", "queue"), os.path.join(tmp, "out", "llm", "queue"),
                       os.path.join(tmp, "gens"))
        for d in (q, wq, gens):
            os.makedirs(d)
        for g in ("jpg-1.py", "jpg-2.py"):
            open(os.path.join(gens, g), "w").close()
        open(os.path.join(q, "id:000000,time:0,execs:0,orig:jpg-1_1.jpg"), "w").close()
        open(os.path.join(wq, "id:000000,orig:jpg-2_1.jpg"), "w").close()
        open(os.path.join(q, "id:000001,sync:llm,src:000000,time:1,execs:2,+cov"), "w").close()
        open(os.path.join(q, "id:000002,src:000001,time:2,execs:3,op:havoc,+cov"), "w").close()
        state = {"generators": {g: {"delta_p": 0.0, "children": [], "failures": 0} for g in ("jpg-1.py", "jpg-2.py")},
                 "last_harvested_queue_id": -1, "pending": None}
        roots = gs._harvest_queue(q, state["generators"], state)
        self.assertEqual(roots, {"jpg-1.py", "jpg-2.py"})
        self.assertEqual(state["generators"]["jpg-2.py"]["delta_p"], 1.0)   # id 2 descends from jpg-2's seed
        self.assertEqual(state["generators"]["jpg-1.py"]["delta_p"], 0.0)   # not from local id 0 (old misreading)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--fake-afl":
        fake_afl(sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5])
    elif len(sys.argv) > 2 and sys.argv[1] == "--output":
        fake_step(sys.argv[2])
        with open(os.path.join(sys.argv[2], "mutate_log"), "a") as f:
            f.write("step\n")
    else:
        unittest.main(verbosity=2)
