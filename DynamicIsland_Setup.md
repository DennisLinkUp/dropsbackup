# Dynamic Island — Xcode Setup

Die folgenden Schritte müssen einmalig manuell in Xcode durchgeführt werden.  
Code ist bereits geschrieben — du musst nur noch die Xcode-Projektstruktur anlegen.

---

## 1. Widget Extension Target hinzufügen

1. In Xcode: **File → New → Target…**
2. Unter **iOS** → **Widget Extension** wählen → **Next**
3. Einstellungen:
   - Product Name: `DropLiveActivity`
   - Team: dein Dev-Team
   - Organization Identifier: gleicher Prefix wie Haupt-App
   - Bundle Identifier wird automatisch: `<deine.bundle.id>.DropLiveActivity`
   - **Include Live Activity**: ☑️ aktivieren (wichtig!)
   - **Include Configuration App Intent**: ☐ deaktivieren
4. **Finish** → Xcode fragt „Activate scheme?" → **Activate**

---

## 2. Attribute-Datei zu beiden Targets hinzufügen

Die Datei `Drops/DropLiveActivityAttributes.swift` muss in **beiden** Targets kompiliert werden:

1. Datei `DropLiveActivityAttributes.swift` im Project Navigator auswählen
2. Rechts im **File Inspector** unter **Target Membership**:
   - ☑️ `Drops` (Haupt-App) — sollte schon aktiv sein
   - ☑️ `DropLiveActivity` (Widget Extension) — hier aktivieren

---

## 3. Widget-Datei dem Extension-Target zuweisen

1. Die generierte `DropLiveActivityWidget.swift` aus dem Ordner `DropLiveActivity/` im Navigator öffnen  
   *(Xcode hat beim Target-Erstellen eine eigene erzeugt — diese durch unsere Version ersetzen)*
2. Den Inhalt der Xcode-generierten Datei durch den Inhalt von  
   `/DropLiveActivity/DropLiveActivityWidget.swift` ersetzen
3. Sicherstellen: Target Membership → ☑️ `DropLiveActivity`

---

## 4. Live Activities Capability aktivieren

1. Haupt-App Target **Drops** auswählen → Tab **Signing & Capabilities**
2. **+ Capability** → **Push Notifications** hinzufügen *(falls nicht vorhanden)*
3. Nochmal **+ Capability** → nach „Live" suchen → **Live Activities** hinzufügen

---

## 5. Deployment Target prüfen

- Haupt-App & Widget Extension: **iOS 16.1+** (ActivityKit Mindestanforderung)
- In den Target-Settings unter **Minimum Deployments** prüfen

---

## 6. Build & Test

```
Cmd+B → Build Both Targets
```

- Dynamic Island im **Simulator** testen: iPhone 14 Pro / 15 Pro / 16 Pro
- Previews in `DropLiveActivityWidget.swift` funktionieren direkt in Xcode

---

## Übersicht der neuen Dateien

| Datei | Target | Zweck |
|---|---|---|
| `Drops/DropLiveActivityAttributes.swift` | Drops **+** DropLiveActivity | Shared Datenmodell |
| `DropLiveActivity/DropLiveActivityWidget.swift` | DropLiveActivity | Dynamic Island UI |

---

## Live Activity manuell auslösen (zum Testen)

In `AppStore` gibt es jetzt folgende Methoden die du direkt aufrufen kannst:

```swift
// Drop erstellt / gestartet (automatisch in createDrop())
store.startDropLiveActivity(drop: drop, isHost: true)

// Jemand tritt bei → Update mit neuem Teilnehmer-Count
store.updateDropLiveActivity(
    participantCount: 4,
    maxParticipants: 5,
    expiresAt: drop.expiresAt
)

// Jemand ist unterwegs → Option 2 anzeigen
store.updateDropLiveActivity(
    participantCount: 4,
    maxParticipants: 5,
    expiresAt: drop.expiresAt,
    onTheWayName: "Jonas",
    onTheWayEmoji: "🧑‍💻",
    onTheWayETAMinutes: 8,
    onTheWayCount: 1
)

// Drop beendet / verlassen (automatisch in cancelDrop() & leaveDropJoin())
store.endDropLiveActivity()
```
