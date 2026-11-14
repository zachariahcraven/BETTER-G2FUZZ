"""ALFRED: a web request limiter shared by every campaign on Tempest (2026-11-13).

All of Tempest reaches the internet through one address, and the free APIs count requests per address. 75 campaigns
that each keep to a limit on their own would together send 75 times too many, and would throttle every other
Tempest user of those APIs. So with G2F_WEB_LIMIT_DIR set (scripts/fuzz binds a group folder there in every
campaign), each web request first takes a turn from that folder:
- Each key (a source, or "host:<name>" for any other site) has a state file with the earliest time of its next
  request. Taking a turn moves it on by the key's interval, so across all campaigns two requests to one key are at
  least that far apart.
- A rate-limit answer (cool()) moves it on by the cooldown, so every campaign backs off, not only the one told.
- If the turn is more than MAX_WAIT seconds away, take() returns None and the caller skips the request (a Cooling),
  instead of waiting.
The state changes under a lock folder: mkdir is atomic on NFS, and unlike a lock call it can't hang when the file
server stalls. A lock older than STALE seconds (a process that died holding it) is taken over. If the lock can't be
had within LOCK_WAIT seconds, or the folder can't be used, the request is skipped: polite rather than fast.
Without G2F_WEB_LIMIT_DIR (tests, a hand run) nothing is shared and take() returns at once.
G2F_WEB_LIMIT_SCALE multiplies every interval (tests use a small one).
"""
import json
import os
import random
import re
import time
import urllib.parse

# seconds between two requests to one key, across all of Tempest: the APIs' published limits, with a margin
INTERVALS = {
    "github": 7.0,            # search API without a token: 10 a minute per address
    "nvd": 7.0,               # CVE API without a key: 5 in 30 s per address
    "stackexchange": 300.0,   # without a key: 300 a day per address
    "wikipedia": 1.0,         # no hard limit; asks clients to send one request at a time
}
HOST_INTERVAL = 2.0           # any other site: linked pages and their robots.txt
MAX_WAIT = 30.0               # a turn further away than this is skipped, not waited for
LOCK_WAIT = 5.0
STALE = 30.0
HOSTS = {"api.github.com": "github", "github.com": "github", "services.nvd.nist.gov": "nvd",
         "nvd.nist.gov": "nvd", "api.stackexchange.com": "stackexchange"}


def key_for(url):
    """The limiter key of a URL: a source's name, or host:<name> for any other site."""
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    if host in HOSTS:
        return HOSTS[host]
    if host == "wikipedia.org" or host.endswith(".wikipedia.org"):
        return "wikipedia"
    return "host:" + host


def source_of(key):
    """The web source a key belongs to (links for any other site): what a Cooling names."""
    return "links" if key.startswith("host:") else key


def folder():
    return os.environ.get("G2F_WEB_LIMIT_DIR") or None


def interval(key):
    try:
        scale = float(os.environ.get("G2F_WEB_LIMIT_SCALE", "1"))
    except ValueError:
        scale = 1.0
    return INTERVALS.get(key, HOST_INTERVAL) * max(scale, 0.0)


def _name(key):
    return re.sub(r"[^A-Za-z0-9_.-]", "_", key)[:120]


class _Lock:
    """mkdir-based lock on <folder>/<key>.lock; ok is False if it couldn't be had."""

    def __init__(self, base, key):
        self.path = os.path.join(base, _name(key) + ".lock")
        self.ok = False

    def __enter__(self):
        end = time.time() + LOCK_WAIT
        while True:
            try:
                os.mkdir(self.path)
                self.ok = True
                return self
            except FileExistsError:
                try:
                    if time.time() - os.stat(self.path).st_mtime > STALE:   # its owner died: take it over
                        os.rmdir(self.path)
                        continue
                except OSError:
                    continue   # gone meanwhile: try again
            except OSError:
                return self    # the folder can't be used
            if time.time() > end:
                return self
            time.sleep(random.uniform(0.02, 0.15))

    def __exit__(self, *_):
        if self.ok:
            try:
                os.rmdir(self.path)
            except OSError:
                pass


def _read(path):
    try:
        with open(path) as f:
            return float(json.load(f).get("next", 0))
    except (OSError, ValueError, AttributeError):
        return 0.0


def _write(path, nxt):
    tmp = "%s.%d.%d" % (path, os.getpid(), random.randrange(1 << 30))
    with open(tmp, "w") as f:
        json.dump({"next": nxt, "by": os.uname().nodename, "pid": os.getpid()}, f)
    os.replace(tmp, path)


def take(key, max_wait=MAX_WAIT):
    """Takes key's next turn and sleeps until it: returns the seconds waited, or None if the turn is more than
    max_wait away or the shared folder can't be used (skip the request). Without G2F_WEB_LIMIT_DIR: returns 0."""
    base = folder()
    if not base:
        return 0.0
    state = os.path.join(base, _name(key) + ".json")
    with _Lock(base, key) as lock:
        if not lock.ok:
            return None
        now = time.time()
        slot = max(now, _read(state))
        if slot - now > max_wait:
            return None
        try:
            _write(state, slot + interval(key))
        except OSError:
            return None
    wait = slot - time.time()
    if wait > 0:
        time.sleep(wait)
    return max(wait, 0.0)


def cool(key, secs):
    """A rate-limit answer for key: no campaign takes a turn for secs seconds."""
    base = folder()
    if not base:
        return
    state = os.path.join(base, _name(key) + ".json")
    with _Lock(base, key) as lock:
        if not lock.ok:
            return
        until = time.time() + secs
        if until > _read(state):
            try:
                _write(state, until)
            except OSError:
                pass


def wait_left(key):
    """Seconds until key's next turn (0 if free or not shared): for skipping a source without taking a turn."""
    base = folder()
    if not base:
        return 0.0
    return max(0.0, _read(os.path.join(base, _name(key) + ".json")) - time.time())
