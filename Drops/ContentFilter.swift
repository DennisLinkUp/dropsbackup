import Foundation

/// Wortbasierter Content-Filter für Nutzer-Eingaben (Drop-Name, Beschreibung).
///
/// Strategie: einfache Wort-Blocklist, Whole-Word-Match (Wortgrenze regex),
/// Case-insensitive, mit basaler Leetspeak-Normalisierung (`@→a`, `3→e`,
/// `1→i`, `0→o`, `$/5→s`, `7→t`). Substrings werden bewusst NICHT geblockt,
/// damit z.B. „Spaziergang" nicht an „spast" hängen bleibt.
///
/// Nicht hier: KI-Toxizität-Erkennung, Kontext-Analyse, Drohungs-Klassifier.
/// Für Launch reicht der harte Wort-Block — alles weitere kommt via
/// Report-Flow im Admin-Panel.
enum ContentFilter {

    // MARK: - Blocklist
    //
    // Bewusst kompakt gehalten — die häufigsten Beleidigungen, Slurs,
    // Sexual-Solicitation-Wörter. Alles Lowercase, ohne Leetspeak (das
    // normalisiert die `containsBlockedWord`-Funktion). Compound-Worte
    // werden via Wortgrenze gematcht.
    static let blocklist: Set<String> = [
        // ── DE: Beleidigungen ──────────────────────────────────────
        "arschloch", "arsch", "wichser", "wixer", "idiot", "vollidiot",
        "depp", "trottel", "hurensohn", "hurenkind", "hure", "schlampe",
        "nutte", "fotze", "miststueck", "miststück", "missgeburt",
        "spasti", "spast", "behindi", "mongo", "kackbratze", "spinner",
        "vollpfosten", "drecksau", "drecksack", "drecksvieh",
        "abschaum", "missratener",
        // ── DE: Slurs / Diskriminierung ────────────────────────────
        "kanake", "nigger", "neger", "schwuchtel", "schwul",
        "tunte", "schwuchti", "schwanzlutscher", "fag", "faggot",
        "zigeuner", "jud", "judensau",
        // ── DE: Sexuelle Anbahnung (Solicitation) ──────────────────
        "blowjob", "ficken", "fick", "ficker", "gangbang", "bumsen",
        "vögeln", "voegeln", "blasen", "schwanz",
        "titten", "muschi", "möse", "moese", "pussy", "wichsen",
        // ── DE: Gewalt / Drohungen ─────────────────────────────────
        "killen", "umbringen", "abstechen", "totschlagen", "vergewaltigen",
        // ── EN: Common ─────────────────────────────────────────────
        "asshole", "fuck", "fucker", "fucking", "shit", "bitch",
        "cunt", "dick", "slut", "whore", "retard", "retarded",
        "motherfucker", "bastard",
        "kill", "rape", "stab",
        // ── EN: Slurs ──────────────────────────────────────────────
        "nigga", "tranny", "kike", "chink", "spic",
    ]

    // MARK: - Public API

    struct Match {
        let word: String        // gefundenes Blocklist-Wort (lowercase)
        let inField: String     // ursprünglicher Feld-Inhalt
    }

    /// Prüft Drop-Name + Beschreibung. Gibt das erste gefundene Wort
    /// zurück, oder `nil` wenn sauber. Beide Felder werden gemeinsam
    /// gescannt damit der User in einem Schritt eine klare Antwort
    /// bekommt.
    static func firstMatch(activityName: String,
                           description: String?) -> Match? {
        if let m = scan(activityName) {
            return Match(word: m, inField: activityName)
        }
        if let desc = description, !desc.isEmpty,
           let m = scan(desc) {
            return Match(word: m, inField: desc)
        }
        return nil
    }

    // MARK: - Internals

    /// Liefert das erste Blocklist-Wort, das im Text als ganzes Wort vorkommt.
    private static func scan(_ raw: String) -> String? {
        let normalized = normalize(raw)
        // Word-Boundary-Regex auf normalisiertem Text — verhindert dass
        // legitime Wörter (z.B. „spazieren" → enthält nicht „spast")
        // ausversehen blocken. Wir bauen für jede Blocklist-Eintrag
        // ein eigenes Pattern, weil dynamische OR-Regexe mit 100+
        // Alternationen in NSRegularExpression spürbar slow werden.
        for word in blocklist {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: normalized,
                                range: NSRange(normalized.startIndex..., in: normalized)) != nil {
                return word
            }
        }
        return nil
    }

    /// Normalisiert User-Input für robusteren Match:
    ///   1. lowercase
    ///   2. Leetspeak rückwärts: `@/4 → a`, `3 → e`, `1/!/| → i`,
    ///      `0 → o`, `$/5 → s`, `7 → t`
    ///   3. NICHT-alphanumerische Zeichen zusammen, damit „f*ck" oder
    ///      „f.u.c.k" auch matcht (Punkte/Sterne raus).
    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        // Leetspeak
        let map: [Character: Character] = [
            "@": "a", "4": "a",
            "3": "e",
            "1": "i", "!": "i", "|": "i",
            "0": "o",
            "$": "s", "5": "s",
            "7": "t"
        ]
        s = String(s.map { map[$0] ?? $0 })
        // Zwischenraum-/Punktuations-Tricks: f.u.c.k → fuck
        let separators: Set<Character> = [".", "*", "_", "-", "·"]
        s = String(s.filter { !separators.contains($0) })
        return s
    }
}
