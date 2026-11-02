import Foundation

// Own modes, shared by the Mac and the iOS app: the model and the templates. Each app stores
// them its own way (iOS in the App Group, the Mac in its settings file). Foundation only, so
// the Mac tests compile it.

/// A user-defined mode: the transcript goes through a language model with this instruction.
struct CustomMode: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var prompt: String
    /// One of the Blackboat accent families (`CustomModeColor`), nil for the default. Only the
    /// Mac lets the user choose it; a nil value is left out of the JSON, so modes stored by
    /// earlier builds keep their shape.
    var color: String?

    static func new(
        name: String = "",
        icon: String = "wand.and.stars",
        prompt: String = "",
        color: String? = nil
    ) -> CustomMode {
        CustomMode(id: "custom-\(UUID().uuidString)", name: name, icon: icon, prompt: prompt, color: color)
    }

    /// Without an instruction the mode keeps the text word for word and needs no language model.
    var hasInstruction: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The colour to show; missing or unknown values fall back to evening, like the writing modes.
    var colorChoice: CustomModeColor {
        get { color.flatMap(CustomModeColor.init(rawValue:)) ?? .evening }
        set { color = newValue.rawValue }
    }

    /// Symbols to choose from in the editors.
    static let symbols = [
        "wand.and.stars", "envelope.fill", "number", "list.bullet", "globe",
        "text.append", "briefcase.fill", "person.2.fill", "checklist", "quote.bubble.fill",
        "doc.text.fill", "lightbulb.fill",
    ]
}

/// The three accent families of the Blackboat tokens (`BlackboatColor.Source`), by name.
enum CustomModeColor: String, CaseIterable, Identifiable {
    case day
    case evening
    case night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: return "Blau"
        case .evening: return "Violett"
        case .night: return "Lila"
        }
    }
}

/// Ready-made instructions the user can add with one tap.
struct CustomModeTemplate: Identifiable {
    let id: String
    let name: String
    let icon: String
    let prompt: String

    func makeMode() -> CustomMode {
        .new(name: name, icon: icon, prompt: prompt)
    }

    static let email = CustomModeTemplate(
        id: "email",
        name: "Als E-Mail",
        icon: "envelope.fill",
        prompt: """
        Du schreibst aus einem gesprochenen Transkript eine E-Mail auf Deutsch. Behalte die Perspektive wie gesprochen („ich“ bleibt „ich“, „wir“ bleibt „wir“).
        Regeln:
        - Beginne direkt mit der Anrede. Wird ein Name genannt, nutze ihn („Hallo Jana,“), sonst „Hallo,“.
        - Danach die Anliegen in ein bis drei kurzen Absätzen, zusammengehörige Sätze in einem Absatz.
        - Jede Bitte, jede Frist und jeder Termin aus dem Transkript bleibt erhalten. Erfinde nichts dazu.
        - Ende mit einem kurzen Gruß wie „Viele Grüße“.
        - Schreibe keine Betreffzeile und keine Erklärungen.
        """
    )

    static let reply = CustomModeTemplate(
        id: "reply",
        name: "Antworten",
        icon: "arrowshape.turn.up.left.fill",
        prompt: """
        Du formulierst aus einem gesprochenen Transkript eine Antwort auf Deutsch. Das Transkript sagt, was geantwortet werden soll.
        Regeln:
        - Steht im Kontext eine Nachricht, antworte passend darauf: gleiche Anrede (du oder Sie), gleicher Ton, Bezug auf die Punkte, die das Transkript anspricht.
        - Übernimm Zusagen, Absagen, Termine und Bedingungen genau so, wie sie gesprochen wurden. Erfinde nichts dazu.
        - Kurz und klar, ohne Betreffzeile und ohne Erklärungen. Gib nur den Antworttext zurück.
        """
    )

    static let bullets = CustomModeTemplate(
        id: "bullets",
        name: "Stichpunkte",
        icon: "list.bullet",
        prompt: """
        Fasse das gesprochene Transkript als Stichpunkte auf Deutsch zusammen.
        Regeln:
        - Ein Gedanke pro Zeile, jede Zeile beginnt mit „- “.
        - Behalte Namen, Fristen und Zahlen. Erfinde nichts dazu.
        - Aufgaben kennzeichnest du am Zeilenanfang mit „To-do:“.
        - Keine Einleitung, keine Überschrift.
        """
    )

    static let english = CustomModeTemplate(
        id: "english",
        name: "Auf Englisch",
        icon: "globe",
        prompt: """
        Übersetze das gesprochene Transkript in natürliches, klares Englisch.
        Behalte Ton, Perspektive und Bedeutung, glätte gesprochene Wiederholungen. Erfinde nichts dazu.
        Gib nur die Übersetzung zurück.
        """
    )

    static let summary = CustomModeTemplate(
        id: "summary",
        name: "Kurzfassung",
        icon: "text.append",
        prompt: """
        Fasse das gesprochene Transkript in zwei bis drei klaren Sätzen auf Deutsch zusammen.
        Das Wichtigste zuerst, Namen und Fristen bleiben erhalten. Erfinde nichts dazu.
        Gib nur die Zusammenfassung zurück.
        """
    )

    static let all: [CustomModeTemplate] = [email, bullets, reply, english, summary]
    static let defaultSeeds: [CustomModeTemplate] = [email, bullets]
}
