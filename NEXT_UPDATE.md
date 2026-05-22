# Drops — Nächstes Update Roadmap

Drei priorisierte Features für das nächste Update. Stand: nach Cleanup-Sprint am 14.–15.05.2026 (Brand-Migration, Aurora-Tokens, Demo-Daten-Cycle für Screenshots, ID-Verify-Cleanup, Boost-Drop-Entfernung).

---

## 1. First-Drop-Walkthrough im Onboarding

**Problem:** Erstnutzer öffnet die App → sieht WelcomeSheet (info-heavy) → schließt → ist auf leerer Map → versteht nicht was zu tun ist → deinstalliert. Aktivierungsrate leidet.

**Ziel:** Nach 1–2 minimalen Welcome-Slides direkt einen Probe-Drop erstellen lassen mit Coach-Marks. Erster Drop = sofortiger „Aha-Moment".

### Konkrete Implementation

**Touchpoints im Code:**
- `MainTabView.swift` — `WelcomeSheet` aufgerufen über `hasSeenWelcome`-UserDefault
- `MainTabView.swift:251+` — `FirstDropCelebration` bereits implementiert (Confetti-Burst)
- `CreateDropView.swift` — Drop-Erstellungs-UI (Activity, Location, Time, Submit)
- Eventueller neuer UserDefault: `hasCompletedFirstDropWalkthrough`

**Walkthrough-Flow:**
1. **Welcome-Slide reduzieren** auf 1–2 Slides (statt aktuell 4 Features)
   - Slide 1: Manifest-Statement („Hingehen statt schreiben")
   - Slide 2 (optional): Live-Activity-Mock (Dynamic Island Demo)
   - CTA: „Mach deinen ersten Drop"

2. **Coach-Mark-Overlay über `CreateDropView`** (Standard-Schritte mit Spotlight)
   - Coach 1: Aktivität auswählen — „Was machst du?" mit Pfeil zum Activity-Picker
   - Coach 2: Standort bestätigen — „Wo bist du?" mit Pfeil zum Map-Pin
   - Coach 3: Zeit — „Jetzt oder später?" mit Pfeil zum Time-Chip
   - Coach 4: Drop starten — Big-CTA-Highlight

3. **Optionaler Demo-Modus für ersten Drop**
   - Wenn User in einer Test-Stadt ist und keine echten Drops in der Nähe: Ghost-Drop als „Demo-Joiner" simulieren der nach 30 Sek anklopft
   - Markiert als „Beispiel-Begegnung — so läuft's bei einem echten Drop"
   - NICHT in `pastDrops`/`encounters` persistieren

4. **First-Drop-Celebration bleibt unverändert** — wird nach erstem echten Drop getriggert

5. **Skip-Button** an jedem Coach-Mark („Später durchblicken" → User landet auf Map ohne Probe-Drop)

### Aufwand
~1–2 Tage. Hauptarbeit: Coach-Mark-Overlay-System bauen (gibt's nicht in der App, müsste eigene SwiftUI-View sein mit `.overlay` + spotlight-Cutout).

### Bibliothek-Tipps
- Eigene Coach-Marks via SwiftUI `Path` + `.eoFill`-Mask für Spotlight
- Alternativ: [TipKit](https://developer.apple.com/documentation/tipkit) (iOS 17+) für native Coach-Marks

### Erfolgsmessung
Track per Firebase Analytics:
- `onboarding_started`
- `onboarding_walkthrough_completed`
- `onboarding_walkthrough_skipped`
- `first_drop_created`
- Conversion-Rate: started → first-drop-created

---

## 2. Reliability-Tier-System vereinfachen

**Problem:** Das Score-System hat 8 Bonus-Mechaniken + 5 Tiers. Im Profil-Hero ist das viel auf einmal — neue User verstehen den Wert nicht sofort.

**Ziel:** Profil-Hero zeigt nur essenzielle Info (Tier + Progress). Detail-Aufschlüsselung hinter „ⓘ".

### Konkrete Implementation

**Touchpoints im Code:**
- `DesignSystem.swift:601+` — `ReliabilityBadgeView` (kompakte Variante)
- `DesignSystem.swift:725+` — `ReliabilityInfoSheet` (großes Detail-Sheet)
- `ProfileAndAlertsView.swift` — Profil-Hero-Card (zeigt aktuell Score-Number + Tier + Drops + Freunde)

**Was im Profil-Hero bleibt:**
- Avatar + Name + Alter
- Tier-Icon + Tier-Name („Stammgast") — visuell groß
- Score-Number — sekundär kleiner
- **Progress-Bar** zur nächsten Stufe (zeigt motivation: „noch 76 Pkt bis Drop-Legende")
- Stat-Counter: „X Drops · Y Freunde" (klein)

**Was raus aus Hero:**
- Detail-Score-Aufschlüsselung
- 5-Tier-Übersicht
- Bonus-Kategorien

**Was im Detail-Sheet bleibt (hinter ⓘ-Tap):**
- Alle existierenden Sektionen (Hero-Card, Progress, Events, Bonus, Tier-Übersicht, Stats)
- Plus: „Wie kann ich aufsteigen?"-Erklärung in einfacher Sprache

### Konkrete Profile-Hero-Komposition

```
┌──────────────────────────────────────────┐
│  [Avatar]    Lara, 27                ⓘ  │
│              ⭐ Stammgast                 │
│              ████████░░░░░░  324 / 500   │
│              176 Pkt bis Drop-Legende    │
│              ─────────────────────────   │
│              8 Drops · 7 Freunde         │
└──────────────────────────────────────────┘
```

### Aufwand
~½ Tag. Existierende Komponenten sind alle da, nur Hero-Card-Layout umarrangieren.

### Sub-Idee: Score-Animation bei Punkt-Gewinn
Wenn User Punkte sammelt (`pointsToast` triggered) → Progress-Bar im Hero animiert mit. Closure-the-loop-Feeling.

---

## 3. Share-Drop-Link (Strava-Pattern)

**Problem:** Geteilte Drop-Links bringen aktuell nur Brand-Awareness, nicht direkten Drop-Join. Eingeladene Person sieht keinen Wert vor Install.

**Ziel:** Web-Page zeigt Live-Drop-Info → CTA zu Install + Deeplink.

### Konkrete Implementation

**Touchpoints im Code:**
- `SharedComponents.swift:527+` — `DropShareButton` (sendet Link)
- `apple-app-site-association.json` (Project-Root) — Universal-Links-Setup
- `drops-website/drop.html` (existiert schon!) — Landing-Page für geteilte Drops
- `firebase.json` / `functions/` — backend für Drop-Daten-Render

**Web-Flow für geteilten Link `drops.app.de/d/{dropID}`:**

```
┌──────────────────────────────────────┐
│  [Drops-Logo] · München              │
├──────────────────────────────────────┤
│                                      │
│      ☕️                              │
│   Kaffee bei Mahlefitz               │
│   Schwabing · läuft seit 12 Min     │
│                                      │
│   Sophie hostet                      │
│   2 / 4 schon da                     │
│                                      │
│   ⚡ Live · 24 Min Restzeit          │
│                                      │
│   ┌────────────────────────────┐    │
│   │  Im App Store öffnen   →   │    │
│   └────────────────────────────┘    │
│                                      │
│   App schon installiert?             │
│   → Direkt zum Drop                  │
│                                      │
└──────────────────────────────────────┘
```

**Server-Side-Rendering:**
- Cloud Function `getDropForShare(dropID)` → liest aus RTDB
- Returns: minimaler Subset (activity, location, host-name, host-emoji, currentParticipants, maxParticipants, expiresAt, isLive)
- Webseite rendert HTML mit dynamischen Daten

**Deeplink-Flow:**
1. User klickt geteilten Link auf iPhone
2. Universal Link triggered: iOS prüft `apple-app-site-association.json`
3. App installiert → direkt in der App geöffnet, Drop wird auf der Map zentriert + Join-Sheet geöffnet
4. App nicht installiert → fallback zu Web-Page mit App-Store-Button

**App-seitige Anpassung:**
- `AppDelegate.swift` — Deeplink-Handler erweitern für `/d/{dropID}` Pfad
- Logic: `pendingDropID` setzen, MapView fokussieren auf Coord, Join-Sheet auto-öffnen

### Aufwand
~2–3 Tage:
- ½ Tag: Cloud Function für Drop-Snapshot-API
- 1 Tag: drop.html als modernes Layout mit dynamischen Daten + App-Store-Badge
- ½ Tag: Universal Link Testing
- ½ Tag: App-Side Deeplink-Handling

### Viralitäts-Bonus
- Bei jedem erfolgreichen Join über Share-Link: **+25 Pkt App-Invite-Bonus** an den Host (gibt's schon in `appInvitesPoints`)
- Plus: in der App-Hero: „Drop teilen ↗"-Button prominenter

---

## Priorität für nächstes Update

**Wenn alle 3 zu viel:** mein Vorschlag in dieser Reihenfolge

1. **#2 Reliability vereinfachen** (½ Tag, niedriges Risiko, sofortiger UX-Gewinn)
2. **#3 Share-Drop-Link** (2–3 Tage, hoher Viralitäts-Impact)
3. **#1 First-Drop-Walkthrough** (1–2 Tage, höchster Activation-Impact, aber abhängig von #3 wenn Demo-Drops genutzt werden)

**Vor dem nächsten Update außerdem:**
- App-Store-Submission mit aktuellen Screenshots → echtes Nutzer-Feedback abwarten
- Falls Feedback klare Probleme zeigt: die hier priorisieren statt diese 3

---

## Aus dem Backlog (noch nicht priorisiert)

- App-Icon-Update auf D-Icon-Variante (Orange→Grün glossy, mit verstärkten Radar-Wellen)
- Live Activity im WelcomeSheet als echtes Dynamic-Island-Mock statt SF-Symbol
- Name-Edit-UI in Settings (sonst hängt User an Apple-Sign-In-Name)
- Drops+ Premium-Code aufräumen wenn permanent dormant
- Lokalisierung von `FeedStatus` (TODO in `FeedView.swift:444`)
- Map+Feed-Merge (anderes UX-Pattern als Bottom-Sheet — z.B. Toggle Map↔Liste)
