"""ALFRED: runs LLM-written generator code with no network and its own empty /tmp and /dev/shm.

unshare (util-linux, in the image) puts the generator in new user, network and mount namespaces: only a loopback
interface, and fresh tmpfs mounts over /tmp and /dev/shm, so it can't reach the internet or the node's shared
/tmp and /dev/shm, where other jobs keep files (see PREFIX for when /tmp stays). It still sees its own campaign folder (its current folder, where it
writes seeds) and the read-only image. The user namespace maps the user to root inside it, which also keeps it from
signalling the worker or afl-fuzz. Apptainer 1.5 on Tempest allows this inside a container (checked 2026-11-11).

Used for every generator the web stall mutator makes, and for all generators with G2F_SANDBOX_ALL=1
(py_utils/func.py: validate_status_process). available() checks once per process that it works; callers refuse to
run web-informed code without it.
"""
import subprocess

# /tmp is replaced only when the generator's own folder isn't in it (a campaign's is in /eval; Python turns a
# relative script path into an absolute one, which a fresh /tmp would hide). Campaign jobs already give the
# container a /tmp of its own (scripts/fuzz write_job_sbatch), so the node's shared /tmp is out of reach either way.
PREFIX = ["unshare", "--user", "--map-root-user", "--net", "--mount", "sh", "-c",
          'case "$(pwd)" in /tmp|/tmp/*) ;; *) mount -t tmpfs tmpfs /tmp || exit 97 ;; esac; '
          'mount -t tmpfs tmpfs /dev/shm || exit 97; exec "$@"', "alfred-sandbox"]

_ok = None
why = ""


def available():
    """True if the sandbox works here (cached). why says what failed."""
    global _ok, why
    if _ok is None:
        try:
            r = subprocess.run(PREFIX + ["true"],
                               capture_output=True, timeout=20)
            _ok = r.returncode == 0
            why = "" if _ok else (r.stderr.decode("utf-8", "replace").strip() or "exit %d" % r.returncode)
        except (OSError, subprocess.TimeoutExpired) as e:
            _ok, why = False, str(e)
    return _ok


def wrap(argv):
    return PREFIX + list(argv)
