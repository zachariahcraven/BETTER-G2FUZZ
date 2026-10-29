# Group Permissions

May be need if you have made files on tempest in the 591 folder. Scripted to keep it simple.

Give the team full access to everything **you** own in the shared folder:

```bash
/home/group/csci-591-automated-vulnerability-discovery/students/WORKING-BETTERG2FUZZ/scripts/group-perms
```

Run it on Tempest whenever teammates can't open or change your files (e.g. after a run). Optional argument: a narrower folder, e.g. `scripts/group-perms eval/<campaign>`.

**What it does:**
`find <folder> -user $USER \( -type f ! -perm -g=rw -o -type d ! -perm -g=rwx \) -print0 | xargs -0 -r chmod g+rwX` group read + write on your files, execute only where you have it, folders enterable.

**Why it's needed:** AFL++ writes its output (`fuzzer_stats`, `plot_data`, `queue/`, …) as `0600`/`0700`, so only
the owner can read it, and only the owner can `chmod` a file. Tempest's NFS has no ACLs to set defaults.
`scripts/fuzz` already does this for its campaign output when a run ends.

**Safe:** only your files, only adds group bits, never touches "other". Millions of files take a few minutes.

