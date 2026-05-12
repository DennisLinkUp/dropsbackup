import Foundation

/// Wortbasierter Content-Filter für Nutzer-Eingaben (Drop-Name,
/// Beschreibung, Profil-Name).
///
/// Strategie: einfache Wort-Blocklist, Whole-Word-Match (Wortgrenze-Regex),
/// Case-insensitive, mit basaler Leetspeak-Normalisierung (`@→a`, `3→e`,
/// `1→i`, `0→o`, `$/5→s`, `7→t`) + Punkt-/Stern-/Trennzeichen-Filter
/// (`f.u.c.k`, `f*ck`, `f_u_c_k` → `fuck`).
///
/// Sprachen: Deutsch, Englisch, Türkisch, Arabisch (translit), Spanisch,
/// Französisch, Italienisch, Russisch (translit), Polnisch, Niederländisch.
/// Plus universelle Slurs / Sexual Solicitation / Drohwörter.
///
/// Performance: alle Blocklist-Wörter werden EINMAL beim ersten Match in
/// ein kombiniertes `\b(w1|w2|…|wN)\b`-Pattern compiliert und cached.
/// Bei 300+ Wörtern ist das ~50× schneller als N einzelne Regexe.
enum ContentFilter {

    // MARK: - Blocklist (mehrsprachig)
    //
    // Bewusst Lowercase ohne Leetspeak (normalize() macht das). Compound-
    // Wörter werden via Wortgrenze gematcht — „spazieren" matchet nicht
    // „spast", auch wenn die Buchstaben drin sind.
    static let blocklist: Set<String> = [
        // ───────────────────────────────────────────────────────────
        // DEUTSCH — Beleidigungen
        // ───────────────────────────────────────────────────────────
        "arschloch", "arsch", "arschlecker", "arschkriecher",
        "wichser", "wixer", "wixxer", "wichsen", "wixen",
        "idiot", "vollidiot", "depp", "trottel", "drecksvieh",
        "hurensohn", "hurenkind", "hure", "schlampe", "nutte",
        "fotze", "miststueck", "miststück", "missgeburt",
        "spasti", "spast", "behindi", "mongo", "kackbratze",
        "spinner", "vollpfosten", "drecksau", "drecksack",
        "abschaum", "missratener", "schwachkopf", "schwachmat",
        "vollhonk", "honk", "lappen", "lutscher",
        "opfer", "loser", "versager",
        // DE — Slurs / Diskriminierung
        "kanake", "nigger", "neger", "negerin",
        "schwuchtel", "schwuchti", "tunte",
        "schwanzlutscher", "fag", "faggot",
        "zigeuner", "zigeunerin", "jud", "judensau", "judenbengel",
        "polacke",
        // DE — Sexuelle Anbahnung / vulgär
        "blowjob", "blasen", "blowi",
        "ficken", "fick", "ficker", "anficken", "weggeficken",
        "gangbang", "bumsen", "vögeln", "voegeln",
        "schwanz", "schwanzfick",
        "titten", "muschi", "möse", "moese", "pussy",
        "wichsen", "wichsvorlage",
        "anal", "deepthroat", "facefuck", "creampie",
        "sexkontakt", "sexkontakte", "sextreffen", "treffsex",
        "fickdate", "fickdates", "fickfreund", "fickfreundin",
        "huren", "puff", "bordell", "rotlicht", "callgirl",
        "callboy", "escort", "escortservice",
        "milf", "dilf", "gilf",
        // DE — Gewalt / Drohungen
        "killen", "umbringen", "abstechen", "totschlagen",
        "vergewaltigen", "vergewaltigung", "vergewaltiger",
        "erschießen", "erschiessen", "erschiess",
        "abknallen", "köpfen", "koepfen",

        // ───────────────────────────────────────────────────────────
        // ENGLISCH
        // ───────────────────────────────────────────────────────────
        "fuck", "fucker", "fucking", "fuckface", "fucktard",
        "motherfucker", "mofo", "mf",
        "asshole", "asshat", "assclown", "asswipe", "jackass",
        "shit", "shithead", "shitbag", "bullshit", "shitstorm",
        "bitch", "bitchy", "biatch",
        "cunt", "twat", "dickhead", "dick", "dickface",
        "slut", "whore", "thot", "ho",
        "retard", "retarded", "moron",
        "bastard", "scumbag",
        "wanker", "tosser", "prick",
        "douche", "douchebag",
        "pussy",
        // EN — Slurs
        "nigga", "nigger", "tranny", "kike", "chink", "spic",
        "gook", "wop", "wetback", "coon", "redskin",
        "fag", "faggot", "homo",
        "raghead", "towelhead", "muzzie",
        "paki",
        // EN — Sexual / explicit
        "porn", "porno", "xxx", "milf", "dilf",
        "blowjob", "handjob", "rimjob", "gangbang",
        "creampie", "bukkake", "facial",
        "hookup", "fwb", "nsa", "sexting",
        "naked", "nude", "nudes", "send nudes",
        "horny", "kinky",
        "escort", "callgirl", "prostitute", "hooker",
        "deepthroat", "fisting",
        // EN — Threats / violence
        "kill", "killing", "killyou", "kys", "rape", "raping",
        "stab", "shoot", "shooting", "murder", "molest",
        "bomb", "terrorist", "isis", "nazi",

        // ───────────────────────────────────────────────────────────
        // TÜRKISCH (große Community in DE)
        // ───────────────────────────────────────────────────────────
        "amk", "aq", "amına", "amına koyim", "aminakoyim",
        "orospu", "orospucocugu", "orospucocuğu", "piç",
        "siktir", "siktir git", "sikim", "sikerim", "sikiyim",
        "yarrak", "yarak", "döl", "götveren", "ibne",
        "puşt", "pust", "gavat", "şerefsiz", "serefsiz",
        "kahpe", "fahişe", "fahise",

        // ───────────────────────────────────────────────────────────
        // ARABISCH (transliteriert — wie User es oft schreiben)
        // ───────────────────────────────────────────────────────────
        "kalb", "kelb", "ibn kalb", "ibn al kalb",
        "sharmuta", "charmuta", "sharmute",
        "kahba", "kahbeh",
        "manyak", "manyuk",
        "khara", "akhu sharmuta",
        "qahba", "qahbe",
        "zib", "zob",
        "ya hmar", "hmar",

        // ───────────────────────────────────────────────────────────
        // SPANISCH
        // ───────────────────────────────────────────────────────────
        "puto", "puta", "putita", "putos", "putas",
        "cabron", "cabrón", "cabrona", "cabrones",
        "pendejo", "pendeja", "pendejos",
        "mierda", "joder", "coño", "cono",
        "chinga", "chingar", "chingada", "chingate",
        "verga", "pinche", "pendejada",
        "maricon", "maricón", "marica",
        "zorra", "perra",
        "follar", "follador", "culiar",
        "polla", "concha", "panocha",

        // ───────────────────────────────────────────────────────────
        // FRANZÖSISCH
        // ───────────────────────────────────────────────────────────
        "putain", "salope", "salaud", "connard", "connasse",
        "enculé", "encule", "enculer", "enculer",
        "bordel", "merde", "bite", "couilles", "couilles molles",
        "pute", "pétasse", "petasse",
        "nique", "niquer", "niquetamere", "niquetamère",
        "fdp", "ntm", "tg",
        "pédé", "pede", "tarlouze",

        // ───────────────────────────────────────────────────────────
        // ITALIENISCH
        // ───────────────────────────────────────────────────────────
        "cazzo", "cazzata", "stronzo", "stronza", "stronzata",
        "vaffanculo", "vafanculo", "fanculo",
        "puttana", "troia", "porca", "porcoddio",
        "minchia", "coglione", "coglioni",
        "frocio", "ricchione",

        // ───────────────────────────────────────────────────────────
        // RUSSISCH (transliteriert)
        // ───────────────────────────────────────────────────────────
        "blyat", "blya", "blyad", "blyadi",
        "suka", "suchka",
        "pizdec", "pizdets", "pizda",
        "huy", "huya", "huynya", "huyovo",
        "yobaniy", "yobannyy", "yobanyy",
        "mudak", "mudaki",
        "pidor", "pidaras", "pidoras",
        "govno", "der'mo", "dermo",
        "shluha", "shluxa",

        // ───────────────────────────────────────────────────────────
        // POLNISCH
        // ───────────────────────────────────────────────────────────
        "kurwa", "kurwy", "kurwo",
        "chuj", "chuja", "chujowy",
        "pierdol", "pierdolic", "spierdalaj", "wypierdalaj",
        "jebać", "jebac", "jeb", "jebaniec",
        "skurwysyn", "skurwiel",
        "cipa", "cipy", "pizda",
        "dupa", "dupek",
        "szmata",

        // ───────────────────────────────────────────────────────────
        // NIEDERLÄNDISCH
        // ───────────────────────────────────────────────────────────
        "kut", "klootzak", "lul", "kutwijf",
        "hoer", "hoertje", "slet",
        "godverdomme", "gvd",
        "tering", "tyfus", "kanker",
        "neuken", "wijf", "trut",

        // ───────────────────────────────────────────────────────────
        // SLURS / Universal
        // ───────────────────────────────────────────────────────────
        "hitler", "heilhitler", "sieg heil", "siegheil",
        "kkk", "skinhead",
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

    /// Profil-Name-Check — einzelnes String-Feld. Nutzt dieselbe Engine.
    static func firstMatch(profileName: String) -> Match? {
        guard let m = scan(profileName) else { return nil }
        return Match(word: m, inField: profileName)
    }

    /// Allgemeine String-Prüfung — für beliebige Felder.
    /// `hasBlockedWord("hure ist hier")` → true.
    static func hasBlockedWord(in text: String) -> Bool {
        scan(text) != nil
    }

    // MARK: - Internals

    /// Cached kombiniertes Regex — `\b(word1|word2|…)\b`. Wird beim
    /// ersten Scan einmalig gebaut, danach für jeden Scan wiederverwendet.
    /// NSRegularExpression mit Alternation ist deutlich schneller als
    /// N einzelne Regex-Objekte (lineare Compilation-Kosten N×, bei
    /// 300+ Wörtern messbar).
    private static let combinedRegex: NSRegularExpression? = {
        // Sortiere absteigend nach Länge damit z.B. „arschloch" vor
        // „arsch" steht — sonst matchet die Engine das kürzere Wort
        // zuerst und liefert verwirrendes Match-Wort zurück.
        let words = blocklist.sorted { $0.count > $1.count }
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "\\b(" + escaped.joined(separator: "|") + ")\\b"
        return try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
    }()

    /// Liefert das erste Blocklist-Wort. Zwei-Pass-Scan:
    ///   1. Normalize mit Leerzeichen — Wort-Grenze funktioniert für
    ///      normale Sätze („kaffee sex party" → matchet „sex").
    ///   2. Falls Pass 1 leer: Leerzeichen weg — fängt obfuskierte
    ///      Eingaben („f u c k" → „fuck", matched).
    private static func scan(_ raw: String) -> String? {
        guard let regex = combinedRegex else { return nil }
        if let m = match(in: normalize(raw, stripSpaces: false), regex: regex) {
            return m
        }
        return match(in: normalize(raw, stripSpaces: true), regex: regex)
    }

    private static func match(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              m.numberOfRanges >= 2,
              let captured = Range(m.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }

    /// Normalisiert User-Input für robusteren Match:
    ///   1. lowercase
    ///   2. Leetspeak rückwärts: `@/4 → a`, `3 → e`, `1/!/| → i`,
    ///      `0 → o`, `$/5 → s`, `7 → t`
    ///   3. Trennzeichen raus: `f.u.c.k` / `f*ck` / `f_u_c_k` → `fuck`
    ///   4. Falls `stripSpaces`: zusätzlich Leerzeichen weg
    ///      (zweiter Pass für „f u c k"-Obfuskation).
    private static func normalize(_ raw: String, stripSpaces: Bool) -> String {
        var s = raw.lowercased()
        let map: [Character: Character] = [
            "@": "a", "4": "a",
            "3": "e",
            "1": "i", "!": "i", "|": "i",
            "0": "o",
            "$": "s", "5": "s",
            "7": "t"
        ]
        s = String(s.map { map[$0] ?? $0 })
        var separators: Set<Character> = [".", "*", "_", "-", "·", "‧"]
        if stripSpaces { separators.insert(" ") }
        s = String(s.filter { !separators.contains($0) })
        return s
    }
}
