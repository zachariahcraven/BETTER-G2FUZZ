"""ALFRED: the web stall mutator's memory, one file per campaign: <afl-out>/web_ledger.json.

For each format it keeps:
- features: each feature the web steps found, the documents that describe it (url and the sentence quoted from
  it) and what became of it: candidate (found, no generator yet), targeted (with its generator) or failed (its
  generator didn't run; tried again up to MAX_ATTEMPTS times). Features the checks turned down are under rejected,
  with the reason (ungrounded: the quote isn't in the document; duplicate-of:<feature>; off-format: <why>, not a
  part of the format's own files, by the relevance rule).
- docs: each document fetched (url, title, source, the query that found it, the step, the features it gave, and
  the file in web_docs/ holding the excerpt the LLM read). A document is fetched once: later steps skip it, so each
  stall reads new documents.
- frontier: links found in fetched documents and not fetched yet, the reading list for later steps.
- queries: each query sent, with its source, step, results and new documents.
- angles: how often each search angle was used (the next step takes the least used).
Plus per-source cooldowns (a rate-limited source is skipped until then) and the step count.

Campaigns never share a ledger, so repetitions stay independent (scripts/fuzz reuse doesn't copy it).
"""
import json
import os
import re
import time
import urllib.parse

MAX_ATTEMPTS = 2          # a failed feature is tried this many times in all
MAX_FRONTIER = 300        # links kept per format (oldest dropped first)
VERSION = 1

# words that don't tell features apart
_STOP = {"the", "a", "an", "of", "and", "or", "for", "in", "on", "to", "with", "by", "support", "supported",
         "feature", "features", "field", "fields", "data", "file", "files", "format", "type", "types", "option",
         "options", "use", "using", "based"}


def norm_url(url):
    """One spelling per document: https, lower-case host without www., no fragment, no trailing slash."""
    p = urllib.parse.urlsplit(url.strip())
    host = p.netloc.lower()
    if host.startswith("www."):
        host = host[4:]
    scheme = "https" if p.scheme.lower() in ("http", "https", "") else p.scheme.lower()
    return urllib.parse.urlunsplit((scheme, host, p.path.rstrip("/") or "/", p.query, ""))


def _stem(w):
    return w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") else w


def name_tokens(name, fmt_words=()):
    """The words of a feature name that tell it apart: lower case, no stop words or format names, plurals cut."""
    drop = set(_STOP)
    for w in fmt_words:
        drop.update(re.findall(r"[a-z0-9]+", w.lower()))
    words = [_stem(w) for w in re.findall(r"[a-z0-9]+", name.lower())]
    kept = [w for w in words if w not in drop]
    return kept or words


def similar(a, b, fmt_words=()):
    """The cheap duplicate check: same words, or at least 60% of their words shared (Jaccard)."""
    A, B = set(name_tokens(a, fmt_words)), set(name_tokens(b, fmt_words))
    if not A or not B:
        return False
    return A == B or len(A & B) / len(A | B) >= 0.6


class Ledger:
    def __init__(self, path):
        self.path = path
        self.data = {"version": VERSION, "steps": 0, "cooldown": {}, "formats": {}}
        if os.path.exists(path):
            try:
                with open(path) as f:
                    data = json.load(f)
                if isinstance(data, dict) and data.get("version") == VERSION:
                    self.data = data
            except (OSError, ValueError):
                os.replace(path, path + ".bad")   # keep it for a look; start a new one

    # --- file ---
    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.data, f, indent=1, sort_keys=True)
        os.replace(tmp, self.path)

    def new_step(self):
        self.data["steps"] = self.data.get("steps", 0) + 1
        return self.data["steps"]

    def fmt(self, fmt):
        f = self.data["formats"].setdefault(fmt, {})
        for k, v in (("features", {}), ("rejected", {}), ("docs", {}), ("frontier", {}), ("queries", []),
                     ("angles", {})):
            f.setdefault(k, v)
        return f

    # --- documents ---
    def seen(self, fmt, url):
        return norm_url(url) in self.fmt(fmt)["docs"]

    def add_doc(self, fmt, url, title, source, query, step, chars, excerpt_file=None):
        u = norm_url(url)
        f = self.fmt(fmt)
        f["frontier"].pop(u, None)
        f["docs"].setdefault(u, {"title": title, "source": source, "query": query, "step": step,
                                 "time": int(time.time()), "chars": chars, "features": [], "file": excerpt_file})
        return u

    def add_frontier(self, fmt, url, title, found_in, score):
        u = norm_url(url)
        f = self.fmt(fmt)
        if u in f["docs"] or u in f["frontier"]:
            return False
        f["frontier"][u] = {"title": title[:200], "from": found_in, "score": score, "time": int(time.time())}
        if len(f["frontier"]) > MAX_FRONTIER:
            oldest = sorted(f["frontier"], key=lambda k: (f["frontier"][k]["score"], f["frontier"][k]["time"]))
            for k in oldest[:len(f["frontier"]) - MAX_FRONTIER]:
                del f["frontier"][k]
        return True

    def take_frontier(self, fmt, n):
        """Up to n unfetched links, best scored and oldest first; they leave the frontier (fetched or not)."""
        f = self.fmt(fmt)
        best = sorted(f["frontier"], key=lambda k: (-f["frontier"][k]["score"], f["frontier"][k]["time"]))[:n]
        return [(u, f["frontier"].pop(u)) for u in best]

    # --- queries and angles ---
    def used_queries(self, fmt):
        return [q["q"] for q in self.fmt(fmt)["queries"]]

    def query_used(self, fmt, q):
        key = " ".join(sorted(set(re.findall(r"[a-z0-9]+", q.lower()))))
        return any(" ".join(sorted(set(re.findall(r"[a-z0-9]+", u.lower())))) == key for u in self.used_queries(fmt))

    def add_query(self, fmt, source, q, step, results, new_docs, error=None):
        rec = {"q": q, "source": source, "step": step, "results": results, "new_docs": new_docs,
               "time": int(time.time())}
        if error:
            rec["error"] = error
        self.fmt(fmt)["queries"].append(rec)

    def source_uses(self, fmt, source):
        return sum(1 for q in self.fmt(fmt)["queries"] if q["source"] == source)

    def next_angle(self, fmt, angles, rng):
        used = self.fmt(fmt)["angles"]
        low = min(used.get(a, 0) for a in angles)
        angle = rng.choice([a for a in angles if used.get(a, 0) == low])
        used[angle] = used.get(angle, 0) + 1
        return angle

    # --- features ---
    def names(self, fmt, statuses=None):
        feats = self.fmt(fmt)["features"]
        return [n for n, v in feats.items() if statuses is None or v["status"] in statuses]

    def add_feature(self, fmt, name, description, url, quote, step, part=""):
        f = self.fmt(fmt)
        feat = f["features"].setdefault(name, {"description": description, "part": part, "docs": [],
                                               "status": "candidate", "attempts": 0, "generator": None,
                                               "step": step})
        self.link(fmt, name, url, quote)
        return feat

    def link(self, fmt, name, url, quote, create=False):
        """Record that document url describes feature name (its quote): feature -> docs and doc -> features.
        create: a feature the ledger doesn't have yet (one covered before any web step, e.g. by seed generation)
        gets an entry with status covered, so its documents are remembered too."""
        f = self.fmt(fmt)
        u = norm_url(url)
        if create and name not in f["features"]:
            f["features"][name] = {"description": "", "docs": [], "status": "covered", "attempts": 0,
                                   "generator": None, "step": None}
        feat = f["features"].get(name)
        if feat is not None and all(d["url"] != u for d in feat["docs"]):
            feat["docs"].append({"url": u, "quote": quote[:500]})
        doc = f["docs"].get(u)
        if doc is not None and name not in doc["features"]:
            doc["features"].append(name)

    def reject(self, fmt, name, reason, url, quote):
        self.fmt(fmt)["rejected"].setdefault(name, {"reason": reason, "url": norm_url(url), "quote": quote[:300]})

    def off_format(self, fmt):
        """Names the relevance rule turned down (not parts of the format's own files), oldest first."""
        return [n for n, v in self.fmt(fmt)["rejected"].items() if v["reason"].startswith("off-format")]

    def candidates(self, fmt):
        """Features found but without a generator yet: never tried, or failed fewer than MAX_ATTEMPTS times."""
        feats = self.fmt(fmt)["features"]
        return [n for n, v in feats.items()
                if v["status"] == "candidate" or (v["status"] == "failed" and v["attempts"] < MAX_ATTEMPTS)]

    def tried(self, fmt, name, generator=None):
        feat = self.fmt(fmt)["features"][name]
        feat["attempts"] += 1
        feat["status"] = "targeted" if generator else "failed"
        feat["generator"] = generator

    # --- rate limits ---
    def cooling(self, source, now=None):
        return (now or time.time()) < self.data["cooldown"].get(source, 0)

    def cool(self, source, secs):
        self.data["cooldown"][source] = int(time.time() + secs)

    def summary(self):
        return summarize(self.data)


def summarize(data):
    """A ledger's numbers (scripts/compare reads the JSON and calls this; it never rewrites a campaign's ledger)."""
    s = {"steps": data.get("steps", 0), "queries": 0, "query_errors": 0, "docs": 0, "frontier": 0,
         "features": 0, "targeted": 0, "failed": 0, "candidates": 0, "covered": 0, "ungrounded": 0,
         "duplicates": 0, "off_format": 0, "by_source": {}}
    for f in data.get("formats", {}).values():
        for q in f.get("queries", []):
            s["queries"] += 1
            s["query_errors"] += 1 if q.get("error") else 0
            b = s["by_source"].setdefault(q.get("source", "?"), [0, 0])
            b[0] += 1
            b[1] += q.get("new_docs", 0)
        s["docs"] += len(f.get("docs", {}))
        links = [d for d in f.get("docs", {}).values() if d.get("source") == "links"]
        if links:
            b = s["by_source"].setdefault("links", [0, 0])
            b[0] += len(links)
            b[1] += sum(1 for d in links if d.get("chars"))
        s["frontier"] += len(f.get("frontier", {}))
        for v in f.get("features", {}).values():
            if v.get("status") == "covered":   # found by seed generation; web documents describe it
                s["covered"] += 1
                continue
            s["features"] += 1
            s[{"targeted": "targeted", "failed": "failed"}.get(v.get("status"), "candidates")] += 1
        for v in f.get("rejected", {}).values():
            r = v.get("reason", "")
            s["ungrounded" if r == "ungrounded" else "off_format" if r.startswith("off-format") else "duplicates"] += 1
    return s
