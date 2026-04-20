/**
 * Drops Cleanup Cloud Functions
 *
 * Scheduled housekeeping that the iOS client shouldn't be responsible for:
 *   - Delete expired drops (expiresAt < now)
 *   - Delete DropIns / JoinRequests belonging to gone drops
 *   - Delete encounters older than 90 days
 *   - Delete phoneIndex / emailIndex entries pointing to gone users
 *   - Delete deletedAccounts tombstones older than 30 days
 *   - Delete Firebase Auth users that have had a tombstone for 90+ days
 *
 * Runs daily at 03:00 Europe/Berlin. Low cost, high reliability.
 *
 * Deploy:
 *   cd functions
 *   npm install
 *   firebase deploy --only functions
 *
 * Requires the Blaze (pay-as-you-go) plan. Free tier: 2M invocations/month —
 * this function runs once per day, well within the free allowance.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getAuth } from "firebase-admin/auth";

const DB_URL = "https://drops-858d1-default-rtdb.europe-west1.firebasedatabase.app";
const TZ = "Europe/Berlin";

initializeApp({ databaseURL: DB_URL });

// ── Main entry — scheduled once per day ──────────────────────────────────────

export const dailyCleanup = onSchedule(
    { schedule: "0 3 * * *", timeZone: TZ, region: "europe-west1", timeoutSeconds: 540 },
    async () => {
        const db = getDatabase();
        const auth = getAuth();
        const now = Date.now();

        const dropsRemoved = await cleanupExpiredDrops(db, now);
        const encountersRemoved = await cleanupOldEncounters(db, now);
        const indexRemoved = await cleanupOrphanedIndex(db);
        const tombstoneUids = await collectExpiredTombstones(db, now);
        const authDeleted = await deleteAuthAccountsForTombstones(auth, tombstoneUids);

        logger.info("dailyCleanup summary", {
            dropsRemoved, encountersRemoved, indexRemoved,
            tombstoneCollected: tombstoneUids.length, authDeleted,
        });
    }
);

// ── Drops older than expiresAt, plus their DropIns/JoinRequests ─────────────

async function cleanupExpiredDrops(db: FirebaseFirestore.Firestore | any, now: number): Promise<number> {
    const ref = db.ref("drops");
    const snap = await ref.once("value");
    if (!snap.exists()) return 0;

    const updates: Record<string, null> = {};
    let count = 0;

    snap.forEach((child: any) => {
        const dict = child.val() ?? {};
        const expiresAtSec = dict.expiresAt as number | undefined;
        const tsMs = dict.timestamp as number | undefined;

        let isExpired = false;
        if (typeof expiresAtSec === "number") {
            isExpired = now > expiresAtSec * 1000;
        } else if (typeof tsMs === "number") {
            // Altes Feld: 12h-Fallback
            isExpired = now - tsMs > 12 * 60 * 60 * 1000;
        } else {
            isExpired = true; // kein Zeitstempel → löschen
        }

        if (isExpired) {
            updates[`drops/${child.key}`] = null;
            updates[`dropins/${child.key}`] = null;
            updates[`joinRequests/${child.key}`] = null;
            count++;
        }
        return false;
    });

    if (count > 0) await db.ref().update(updates);
    return count;
}

// ── Encounters older than 90 days ────────────────────────────────────────────

async function cleanupOldEncounters(db: any, now: number): Promise<number> {
    const cutoff = now - 90 * 24 * 60 * 60 * 1000;
    const snap = await db.ref("encounters").once("value");
    if (!snap.exists()) return 0;

    const updates: Record<string, null> = {};
    let count = 0;
    snap.forEach((child: any) => {
        const ts = child.val()?.timestamp as number | undefined;
        const tsMs = typeof ts === "number" ? (ts > 1e12 ? ts : ts * 1000) : 0;
        if (tsMs > 0 && tsMs < cutoff) {
            updates[`encounters/${child.key}`] = null;
            count++;
        }
        return false;
    });
    if (count > 0) await db.ref().update(updates);
    return count;
}

// ── phoneIndex / emailIndex entries whose uid no longer exists ───────────────

async function cleanupOrphanedIndex(db: any): Promise<number> {
    const [phoneSnap, emailSnap, usersSnap] = await Promise.all([
        db.ref("phoneIndex").once("value"),
        db.ref("emailIndex").once("value"),
        db.ref("users").once("value"),
    ]);

    const existingUids = new Set<string>();
    usersSnap.forEach((c: any) => { existingUids.add(c.key); return false; });

    const updates: Record<string, null> = {};
    let count = 0;

    phoneSnap.forEach((c: any) => {
        const uid = c.val()?.uid as string | undefined;
        if (uid && !existingUids.has(uid)) {
            updates[`phoneIndex/${c.key}`] = null;
            count++;
        }
        return false;
    });
    emailSnap.forEach((c: any) => {
        const uid = c.val()?.uid as string | undefined;
        if (uid && !existingUids.has(uid)) {
            updates[`emailIndex/${c.key}`] = null;
            count++;
        }
        return false;
    });

    if (count > 0) await db.ref().update(updates);
    return count;
}

// ── Tombstones older than 30 days → collect uids (for auth deletion) ────────

async function collectExpiredTombstones(db: any, now: number): Promise<string[]> {
    const cutoff = now - 30 * 24 * 60 * 60 * 1000;
    const snap = await db.ref("deletedAccounts").once("value");
    if (!snap.exists()) return [];
    const uids: string[] = [];
    snap.forEach((child: any) => {
        const deletedAt = child.val()?.deletedAt as number | undefined;
        const tsMs = typeof deletedAt === "number" ? (deletedAt > 1e12 ? deletedAt : deletedAt * 1000) : 0;
        if (tsMs > 0 && tsMs < cutoff) uids.push(child.key);
        return false;
    });
    return uids;
}

// ── Delete Firebase Auth accounts for collected tombstones, then drop the
//    tombstone itself (it's fulfilled its purpose).
async function deleteAuthAccountsForTombstones(auth: any, uids: string[]): Promise<number> {
    if (uids.length === 0) return 0;
    const db = getDatabase();
    const updates: Record<string, null> = {};
    let deleted = 0;
    for (const uid of uids) {
        try {
            await auth.deleteUser(uid);
            deleted++;
        } catch (e: any) {
            // user/not-found ist ok — Auth wurde schon gelöscht; tombstone bleibt
            if (e?.code === "auth/user-not-found") {
                deleted++;
            } else {
                logger.warn(`auth.deleteUser failed for ${uid}`, { error: e?.message });
                continue;
            }
        }
        updates[`deletedAccounts/${uid}`] = null;
    }
    if (Object.keys(updates).length > 0) await db.ref().update(updates);
    return deleted;
}
