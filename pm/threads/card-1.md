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
