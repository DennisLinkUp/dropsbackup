# Drops Cloud Functions

Scheduled server-side housekeeping. The iOS client does a best-effort cleanup
on start, but this function is the reliable fallback — it runs even when no
user has opened the app in weeks.

## What it does

Runs daily at **03:00 Europe/Berlin** (`dailyCleanup`):

1. **Expired Drops** — removes entries in `drops/` where `expiresAt` is in the
   past (or 12 h after `timestamp` for legacy entries). Also cascades deletion
   of associated `dropins/{dropID}` and `joinRequests/{dropID}`.
2. **Old Encounters** — removes `encounters/*` older than 90 days.
3. **Orphaned Discovery Indexes** — removes `phoneIndex/*` and `emailIndex/*`
   entries whose `uid` no longer exists in `users/`.
4. **Expired Tombstones** — for entries in `deletedAccounts/` older than
   30 days, deletes the corresponding Firebase Auth account, then removes the
   tombstone. This is the second half of the soft-delete flow: the iOS client
   deletes user data immediately, the Cloud Function later truly deletes the
   Auth account server-side (no client reauth needed).

## Deployment (one-time setup)

Requires the Firebase **Blaze plan** (pay-as-you-go). This function runs
1×/day and stays well within the free tier (2 M invocations/month).

```bash
# 1. Install CLI if not already
npm install -g firebase-tools
firebase login

# 2. From repo root — initialize functions for the existing project
firebase use drops-858d1        # or: firebase init functions

# 3. Install dependencies
cd functions
npm install

# 4. Deploy
npm run deploy
```

After the first deploy, re-deploying only the function:

```bash
cd functions
npm run deploy
```

## Monitoring

```bash
# Tail logs
firebase functions:log --only dailyCleanup

# One-time manual run (for testing)
firebase functions:shell
# then in the shell:
# > dailyCleanup()
```

Or in the Firebase Console → Functions → `dailyCleanup` → Logs.

## Cost estimate

- 1 invocation per day = 30 / month
- Each run reads a few hundred RTDB entries, does batched updates
- Expected cost: **~0 € / month** (well below Blaze free tier)

## If you want to test locally

```bash
cd functions
npm run serve     # starts emulator
```

Point the iOS app at the emulator RTDB URL to see changes.

## Adjusting the schedule

Edit the `schedule` string in `src/index.ts` (standard cron syntax) and
redeploy. For example:

- `"0 */6 * * *"` — every 6 hours
- `"0 3 * * *"` — daily at 03:00 (current)
- `"0 3 * * 0"` — weekly on Sunday at 03:00
