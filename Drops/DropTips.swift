import TipKit

// MARK: - First-Drop Coach-Marks (TipKit)
//
// Drei sequentielle Hinweise für Erstnutzer beim ersten Drop-Erstellen.
// TipKit speichert den gesehen/nicht-gesehen Status automatisch in seinem
// eigenen Datastore → jeder Tip erscheint exakt einmal, danach nie wieder.
// Konfiguriert in LinkUpApp.init() via Tips.configure().

/// Schritt 1: Aktivität auswählen — erscheint auf dem Aktivitäts-Textfeld.
struct ActivityTip: Tip {
    var title: Text {
        Text(tr("tips.what_are_you_doing"))
    }
    var message: Text? {
        Text(tr("tips.name_template"))
    }
    var image: Image? {
        Image(systemName: "hand.tap.fill")
    }
    var options: [TipOption] {
        [Tips.MaxDisplayCount(1)]
    }
}

/// Schritt 2: Zeitpunkt wählen — erscheint auf dem Wann-Bereich.
struct TimeTip: Tip {
    var title: Text {
        Text(tr("tips.now_or_later"))
    }
    var message: Text? {
        Text(tr("tips.now_message"))
    }
    var image: Image? {
        Image(systemName: "clock.fill")
    }
    var options: [TipOption] {
        [Tips.MaxDisplayCount(1)]
    }
}

/// Schritt 3: Drop veröffentlichen — erscheint auf dem Publish-Button.
struct StartDropTip: Tip {
    var title: Text {
        Text(tr("tips.drop_goes_live"))
    }
    var message: Text? {
        Text(tr("tips.appears_on_map"))
    }
    var image: Image? {
        Image(systemName: "location.fill")
    }
    var options: [TipOption] {
        [Tips.MaxDisplayCount(1)]
    }
}
