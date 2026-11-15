# card-1: Ask RCI to fix DNS on Tempest compute nodes (blocks the relaunch)

## Note nom-nom 2026-11-13 17:15
Source: briefing from session alfred-tweak-rounds-study, 2026-11-13 15:30 MST (not re-verified by nom-nom).

After RCI's outage fix (resolv.conf rewritten 12:31), `/etc/resolv.conf` on most compute nodes holds only `nameserver 10.226.104.21`: no `search rci.montana.edu`, no second server `.23`. Short hostnames (gpu056, tempest-slurm02) fail; FQDNs and squeue work.

Effects:
- `sacctmgr` fails on compute nodes. This killed A02's new driver 1275504 on epyc019 with a bogus "you're not in the Slurm account ...".
- Campaigns reach the LLM server as `http://gpu056:<port>` (short name from `scripts/fuzz` llm_url), so their reachability check would fail.

Good nodes: epyc021, 022, 028, 034, gpu006, gpu027-036, 039, 042, 055-057, 060, 061. Every other epyc/gpu node is bad.

The user has a paste-ready message for the admin; not known whether it has been sent.

Check once fixed, on a few compute nodes: `getent hosts gpu056` and `sacctmgr -nP show assoc user=n59m742` both succeed.

## Note nom-nom 2026-11-13 17:15
Blocked: Send your paste-ready DNS message to the RCI admins (if not sent yet): compute-node /etc/resolv.conf is missing `search rci.montana.edu` and the second nameserver, so short hostnames fail.

## Note human 2026-11-13 17:18
Sent back: No on the msg RCI is working on this no msgs from me are needed.

## Note nom-nom 2026-11-13 17:18
Human, 2026-11-13: RCI is already working on this; no message from the user is needed. The card now just tracks waiting for RCI's fix.

Checked read-only by nom-nom the same evening (ssh to compute nodes): **still broken**.
- epyc019, epyc004, epyc010: resolv.conf has only `nameserver 10.226.104.21`; `getent hosts gpu056` fails; `sacctmgr` fails with "slurm_get_port: Address family '0' not supported".
- gpu056, epyc021: resolv.conf has `search rci.montana.edu` and both nameservers (.21, .23); short names resolve; `sacctmgr` lists the accounts (group-csci-591-..., group-quantumcore, priority-csci-591-...).

Re-check with the same two commands on epyc019/epyc004/epyc010 before the relaunch (card-2).

## Note nom-nom 2026-11-13 17:18
Brief: now: RCI is working on it; DNS still broken on epyc019/004/010 (checked 2026-11-13 evening)
next: re-check getent + sacctmgr on those nodes, then card-2 relaunch can go
you: nothing

## Note nom-nom 2026-11-13 18:09
**2026-11-13 18:08 MST: still broken** (epyc019, epyc004, epyc010, gpu010, epyc036: resolv.conf has one nameserver and no `search` line). epyc021 is good.

**Workaround, no code change, no node restriction.** In the shell that starts the studies (and the watcher), before `scripts/study start ...`:

```
export LOCALDOMAIN=rci.montana.edu APPTAINERENV_LOCALDOMAIN=rci.montana.edu
```

`LOCALDOMAIN` is the resolver's own override for resolv.conf's `search` line; the `APPTAINERENV_` copy carries it into the campaign container, which runs with `--cleanenv`. sbatch passes the submitting shell's environment to the job by default, so the driver, the campaigns it submits and the LLM server all inherit both.

**Verified** in a 1-second test job on a bad node (epyc036, job 1279437, the only job submitted; queue empty afterwards), with both variables exported on the login node:
- both variables arrive in the job;
- `getent hosts gpu056` resolves to gpu056.rci.montana.edu;
- `sacctmgr -nP show assoc user=n59m742` lists the four accounts (this is the check that killed driver 1275504);
- `sbatch --test-only` from the node is accepted;
- inside `build/g2fuzz.sif` with `--cleanenv`, Python resolves `gpu056` (without the variable: "Name or service not known", checked on epyc019).

**Not verified:** a whole campaign end to end, and the LLM server's own container. The variables are harmless once RCI restores the `search` line.

## Note nom-nom 2026-11-13 18:09
Brief: now: DNS still broken at 18:08; workaround verified on a bad node (two env variables, in the notes)
next: relaunch session can start with the workaround (card-2) or wait for RCI
you: say whether the relaunch should go ahead with the workaround

## Note nom-nom 2026-11-13 18:40
18:40 MST: the relaunch went ahead with the workaround and campaigns on bad-DNS nodes reach the LLM server (card-2). RCI's fix is no longer blocking. Closing this card; if RCI restores the `search` line the variables simply stop mattering. Any new shell that starts or restarts a study before then needs the two exports again.
