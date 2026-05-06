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
import { onValueCreated } from "firebase-functions/v2/database";
import { logger } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getDatabase } from "firebase-admin/database";
import { getMessaging } from "firebase-admin/messaging";
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

// ── Friend Request Push ────────────────────────────────────────────────────

/**
 * Wenn friendRequests/{recipientUID}/{senderUID} geschrieben wird → Push an
 * recipientUID mit "{senderName} möchte mit dir befreundet sein".
 *
 * Der Client hinterlegt beim Schreiben `fromName` und optional `fromImageURL`
 * als Payload — wir brauchen also keinen separaten users/-Lookup für den Namen.
 */
export const onFriendRequestCreated = onValueCreated(
    { ref: "/friendRequests/{recipientUID}/{senderUID}", region: "europe-west1" },
    async (event) => {
        const { recipientUID, senderUID } = event.params;
        if (recipientUID === senderUID) return;

        const db = getDatabase();
        const tokenSnap = await db.ref(`users/${recipientUID}/fcmToken`).once("value");
        const token = tokenSnap.val() as string | null;
        if (!token) {
            logger.info("onFriendRequestCreated: no FCM token for recipient", { recipientUID });
            return;
        }

        const val = event.data.val() ?? {};
        const senderName = (val.fromName as string | null) ?? "Jemand";

        try {
            await getMessaging().send({
                token,
                notification: {
                    title: "Neue Freundschaftsanfrage",
                    body: `${senderName} möchte mit dir befreundet sein.`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            category: "FRIEND_REQUEST",
                        },
                    },
                },
                data: {
                    type: "friend_request",
                    senderUID,
                    senderName,
                },
            });
            logger.info("onFriendRequestCreated sent", { recipientUID, senderUID });
        } catch (e: any) {
            logger.warn("FCM send failed", { recipientUID, error: e?.message });
        }
    }
);

// ── Friendship Push ────────────────────────────────────────────────────────

/**
 * Wenn friends/{recipientUID}/{adderUID} = true geschrieben wird → Push an
 * recipientUID mit "{adderName} hat dich als Freund hinzugefügt".
 *
 * Voraussetzung: Der Empfänger hat seinen FCM-Token in users/{uid}/fcmToken
 * hinterlegt (schreibt der iOS-Client beim Launch).
 *
 * Der iOS-Client schreibt die Freundschaft bidirektional — d.h. wenn A B als
 * Freund hinzufügt, werden BEIDE Pfade (friends/A/B und friends/B/A) geschrieben.
 * Wir schicken den Push nur an den Empfänger (der den Add nicht ausgelöst hat),
 * damit der Adder keinen Push für seinen eigenen Add kriegt.
 */
export const onFriendshipAdded = onValueCreated(
    { ref: "/friends/{recipientUID}/{adderUID}", region: "europe-west1" },
    async (event) => {
        const { recipientUID, adderUID } = event.params;
        if (recipientUID === adderUID) return;

        const db = getDatabase();

        // Metadaten parallel laden — Token des Empfängers + Name des Adders
        const [tokenSnap, adderSnap, markerSnap] = await Promise.all([
            db.ref(`users/${recipientUID}/fcmToken`).once("value"),
            db.ref(`users/${adderUID}/name`).once("value"),
            db.ref(`friendshipPushSent/${recipientUID}/${adderUID}`).once("value"),
        ]);

        // Der iOS-Client schreibt beide Pfade — wir würden sonst zweimal pushen.
        // Markerwert dedupliziert: der erste der beiden Trigger setzt den Marker,
        // der zweite findet ihn und bricht ab.
        if (markerSnap.exists()) {
            logger.debug("onFriendshipAdded: already sent", { recipientUID, adderUID });
            return;
        }
        await db.ref(`friendshipPushSent/${recipientUID}/${adderUID}`)
            .set({ at: Date.now() });

        const token = tokenSnap.val() as string | null;
        if (!token) {
            logger.info("onFriendshipAdded: no FCM token for recipient", { recipientUID });
            return;
        }
        const adderName = (adderSnap.val() as string | null) ?? "Jemand";

        try {
            await getMessaging().send({
                token,
                notification: {
                    title: "Neuer Freund",
                    body: `${adderName} hat dich als Freund hinzugefügt.`,
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            category: "FRIENDSHIP_ADDED",
                        },
                    },
                },
                data: {
                    type: "friendship_added",
                    adderUID,
                    adderName,
                },
            });
            logger.info("onFriendshipAdded sent", { recipientUID, adderUID });
        } catch (e: any) {
            logger.warn("FCM send failed", { recipientUID, error: e?.message });
        }
    }
);

// ── New-Drop Nearby Push ──────────────────────────────────────────────────
//
// Wenn jemand einen Drop erstellt → benachrichtige alle User mit lastLat/lastLng
// im Umkreis von NEARBY_RADIUS_METERS (1500m für Launch-Phase, später runter
// auf 600m). Der Host selbst wird ausgeschlossen.
//
// users/{uid}/lastLat, lastLng werden vom iOS-Client throttled geschrieben
// (1× pro 10 Min, gerundet auf ~110m für Privacy).

const NEARBY_RADIUS_METERS = 1500;

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const R = 6371000;
    const toRad = (d: number) => (d * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(a));
}

export const onDropCreatedNearbyPush = onValueCreated(
    { ref: "/drops/{dropID}", region: "europe-west1" },
    async (event) => {
        const drop = event.data.val() ?? {};
        const dropLat = drop.latitude as number | undefined;
        const dropLng = drop.longitude as number | undefined;
        const hostUID = drop.userID as string | undefined;
        const emoji = (drop.emoji as string) || "📍";
        const activity = (drop.activityName as string) || "Drop";

        if (typeof dropLat !== "number" || typeof dropLng !== "number") {
            logger.info("onDropCreatedNearbyPush: drop has no coords, skipping");
            return;
        }

        const db = getDatabase();
        const usersSnap = await db.ref("users").once("value");
        const users = (usersSnap.val() ?? {}) as Record<string, any>;

        const recipients: { uid: string; token: string; distM: number }[] = [];
        for (const [uid, u] of Object.entries(users)) {
            if (uid === hostUID) continue;                  // Host nicht selber benachrichtigen
            if (u?.isBanned === true) continue;
            const token = u?.fcmToken as string | undefined;
            const lat = u?.lastLat as number | undefined;
            const lng = u?.lastLng as number | undefined;
            if (!token || typeof lat !== "number" || typeof lng !== "number") continue;
            const d = haversineMeters(dropLat, dropLng, lat, lng);
            if (d <= NEARBY_RADIUS_METERS) {
                recipients.push({ uid, token, distM: d });
            }
        }

        if (recipients.length === 0) {
            logger.info("onDropCreatedNearbyPush: no nearby users", { hostUID });
            return;
        }

        // Distanz-String pro Empfänger personalisieren ("400 m" / "1.2 km")
        const sends = recipients.map(async (r) => {
            const distStr =
                r.distM < 1000 ? `${Math.round(r.distM)} m` : `${(r.distM / 1000).toFixed(1)} km`;
            try {
                await getMessaging().send({
                    token: r.token,
                    notification: {
                        title: `${emoji} ${activity} in der Nähe`,
                        body: `Nur ${distStr} entfernt — schau auf die Karte.`,
                    },
                    apns: {
                        payload: { aps: { sound: "default", category: "NEARBY_DROP" } },
                    },
                    data: {
                        type: "nearby_drop",
                        dropID: event.params.dropID,
                        hostUID: hostUID ?? "",
                    },
                });
            } catch (e: any) {
                logger.warn("nearby push send failed", { uid: r.uid, error: e?.message });
            }
        });
        await Promise.allSettled(sends);
        logger.info("onDropCreatedNearbyPush done", {
            dropID: event.params.dropID,
            recipients: recipients.length,
        });
    }
);

// ── City Inactivity Push ──────────────────────────────────────────────────
//
// Täglich 18:00 Europe/Berlin: pro Service-Stadt zählen wir aktive Drops der
// letzten 3 Tage. Wenn 0 → einmal pro Stadt einen "Sei der Erste"-Push an
// alle User in dieser Stadt. User-Stadt wird aus letzter bekannter Position
// (lastLat/lastLng) abgeleitet.
//
// Service-Cities (in sync mit iOS Drops/CityGateView.swift)
const SERVICE_CITIES: { name: string; lat: number; lng: number; radiusKm: number }[] = [
    { name: "München",   lat: 48.1371, lng: 11.5754, radiusKm: 25 },
    { name: "Berlin",    lat: 52.5200, lng: 13.4050, radiusKm: 30 },
    { name: "Hamburg",   lat: 53.5511, lng: 9.9937,  radiusKm: 25 },
    { name: "Köln",      lat: 50.9375, lng: 6.9603,  radiusKm: 22 },
    { name: "Frankfurt", lat: 50.1109, lng: 8.6821,  radiusKm: 22 },
];

function cityForCoord(lat: number, lng: number): string | null {
    for (const c of SERVICE_CITIES) {
        const d = haversineMeters(lat, lng, c.lat, c.lng);
        if (d <= c.radiusKm * 1000) return c.name;
    }
    return null;
}

export const cityInactivityPush = onSchedule(
    { schedule: "0 18 * * *", timeZone: TZ, region: "europe-west1" },
    async () => {
        const db = getDatabase();
        const dropsSnap = await db.ref("drops").once("value");
        const usersSnap = await db.ref("users").once("value");
        const now = Date.now();
        const threeDaysAgo = now - 3 * 24 * 60 * 60 * 1000;

        // 1) Pro Stadt: aktive Drops der letzten 3 Tage zählen
        const activityByCity: Record<string, number> = {};
        SERVICE_CITIES.forEach((c) => (activityByCity[c.name] = 0));
        const drops = (dropsSnap.val() ?? {}) as Record<string, any>;
        for (const d of Object.values(drops)) {
            const lat = d?.latitude as number | undefined;
            const lng = d?.longitude as number | undefined;
            const created = d?.createdAt as number | undefined;
            if (typeof lat !== "number" || typeof lng !== "number") continue;
            if (typeof created !== "number" || created < threeDaysAgo) continue;
            const city = cityForCoord(lat, lng);
            if (city) activityByCity[city]++;
        }

        // 2) Pro inaktiver Stadt: Push an alle User dort
        const inactiveCities = SERVICE_CITIES.filter((c) => activityByCity[c.name] === 0);
        if (inactiveCities.length === 0) {
            logger.info("cityInactivityPush: alle Städte aktiv ✓");
            return;
        }

        const users = (usersSnap.val() ?? {}) as Record<string, any>;
        for (const city of inactiveCities) {
            const tokens: string[] = [];
            for (const u of Object.values(users)) {
                if (u?.isBanned === true) continue;
                const token = u?.fcmToken as string | undefined;
                const lat = u?.lastLat as number | undefined;
                const lng = u?.lastLng as number | undefined;
                if (!token || typeof lat !== "number" || typeof lng !== "number") continue;
                if (cityForCoord(lat, lng) === city.name) tokens.push(token);
            }
            if (tokens.length === 0) continue;

            // Batch via sendEachForMulticast (max 500 per call)
            try {
                await getMessaging().sendEachForMulticast({
                    tokens,
                    notification: {
                        title: `${city.name} braucht dich`,
                        body: "Niemand droppt gerade — sei heute Abend der Erste.",
                    },
                    apns: {
                        payload: { aps: { sound: "default", category: "CITY_INACTIVE" } },
                    },
                    data: { type: "city_inactive", city: city.name },
                });
                logger.info("cityInactivityPush sent", {
                    city: city.name,
                    recipients: tokens.length,
                });
            } catch (e: any) {
                logger.warn("cityInactivityPush failed", { city: city.name, error: e?.message });
            }
        }
    }
);

// ── 30-Min-Reminder vor Drop-Start ────────────────────────────────────────
//
// Läuft alle 5 Minuten: findet Drops mit `startAt` in [now+25min, now+35min]
// und `reminderSent != true`. Sendet Push an Host + alle Joiner (aus dropins/),
// markiert dann `reminderSent: true` damit nicht doppelt gefeuert wird.
//
// startAt wird vom iOS-Client beim Publish geschrieben (parseDropStartAt in
// RealtimeDBManager.swift). Drops mit scheduledTime "Jetzt" haben startAt ≈
// createdAt → fallen NICHT ins 25–35min-Fenster, kein Reminder.

export const dropStartReminder = onSchedule(
    { schedule: "every 5 minutes", timeZone: TZ, region: "europe-west1" },
    async () => {
        const db = getDatabase();
        const now = Date.now();
        const windowStart = now + 25 * 60 * 1000;
        const windowEnd   = now + 35 * 60 * 1000;

        const [dropsSnap, usersSnap] = await Promise.all([
            db.ref("drops").once("value"),
            db.ref("users").once("value"),
        ]);
        const drops = (dropsSnap.val() ?? {}) as Record<string, any>;
        const users = (usersSnap.val() ?? {}) as Record<string, any>;

        let triggeredDrops = 0;
        let totalSends = 0;

        for (const [dropID, drop] of Object.entries(drops)) {
            if (!drop || drop.active === false) continue;
            if (drop.reminderSent === true) continue;
            const startAtSec = drop.startAt as number | undefined;
            if (typeof startAtSec !== "number") continue;
            const startAtMs = startAtSec * 1000;
            if (startAtMs < windowStart || startAtMs > windowEnd) continue;

            const hostUID  = (drop.userID as string | undefined) ?? "";
            const emoji    = (drop.emoji as string) || "📍";
            const activity = (drop.activityName as string) || "Drop";

            // Empfänger sammeln: Host + alle Joiner aus dropins/{dropID}
            const recipientUIDs = new Set<string>();
            if (hostUID) recipientUIDs.add(hostUID);
            const dropinsSnap = await db.ref(`dropins/${dropID}`).once("value");
            dropinsSnap.forEach((c) => {
                if (c.key) recipientUIDs.add(c.key);
                return false;
            });

            const tokenSends: Promise<any>[] = [];
            for (const uid of recipientUIDs) {
                const u = users[uid];
                const token = u?.fcmToken as string | undefined;
                if (!token || u?.isBanned === true) continue;
                const isHost = uid === hostUID;
                tokenSends.push(
                    getMessaging().send({
                        token,
                        notification: {
                            title: isHost
                                ? `Dein Drop startet in 30 Min`
                                : `${emoji} ${activity} startet in 30 Min`,
                            body: isHost
                                ? "Mach dich bereit — die anderen kommen gleich."
                                : "Zeit, sich auf den Weg zu machen.",
                        },
                        apns: {
                            payload: { aps: { sound: "default", category: "DROP_REMINDER" } },
                        },
                        data: {
                            type: "drop_reminder",
                            dropID,
                            hostUID,
                        },
                    }).catch((e: any) => {
                        logger.warn("dropStartReminder send failed", {
                            uid, dropID, error: e?.message,
                        });
                    })
                );
            }

            await Promise.allSettled(tokenSends);
            // Markieren — auch wenn keine Tokens da waren, sonst feuert es endlos
            await db.ref(`drops/${dropID}/reminderSent`).set(true);
            triggeredDrops++;
            totalSends += tokenSends.length;
        }

        if (triggeredDrops > 0) {
            logger.info("dropStartReminder done", { triggeredDrops, totalSends });
        }
    }
);
