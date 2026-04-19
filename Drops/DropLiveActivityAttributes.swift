import ActivityKit
import Foundation

// MARK: - Live Activity Attributes
// Wird von beiden Targets benötigt: Drops (Haupt-App) + DropLiveActivity (Widget Extension).
// In Xcode: Datei in beiden Targets unter "Target Membership" aktivieren.

struct DropLiveActivityAttributes: ActivityAttributes {
    public typealias DropLiveActivityStatus = ContentState

    // MARK: Static (wird beim Start gesetzt, ändert sich nie)
    var activityName: String   // z.B. "Kaffee"
    var activityEmoji: String  // z.B. "☕️"
    var dropID: String         // UUID-String
    var isHost: Bool           // true = eigener Drop, false = beigetreten

    // MARK: Dynamic (wird per update() aktualisiert)
    public struct ContentState: Codable, Hashable {
        var participantCount: Int
        var maxParticipants: Int
        var expiresAt: Date
        /// Adresse des Drop-Standorts (z.B. "Odeonsplatz 1, München")
        var locationTitle: String
        /// Emojis der bereits vor Ort angekommenen Teilnehmer
        var arrivedEmojis: [String]
        /// Namen der vor Ort angekommenen Teilnehmer — Index-synchron zu arrivedEmojis
        var arrivedNames: [String]
        /// Dateinamen der gecachten Profilbilder in der App Group — Index-synchron zu arrivedEmojis
        /// Leer = kein Bild → Emoji-Fallback im Widget
        var arrivedImageFilenames: [String]
        /// Emojis + ETAs der Teilnehmer die gerade unterwegs sind (parallel)
        var onTheWayEmojis: [String]
        var onTheWayETAs: [Int]        // ETA in Minuten, Index-synchron zu onTheWayEmojis
        var onTheWayNames: [String]    // Namen, Index-synchron
    }
}
