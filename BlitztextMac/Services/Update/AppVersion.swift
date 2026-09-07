import Foundation

/// Vergleichbare Programmversion. Toleriert ein fuehrendes "v" und
/// unterschiedlich viele Komponenten: 1.5 und 1.5.0 sind dieselbe Version.
/// Nicht parsbare Eingaben ergeben nil und fuehren nie zu einem Update-Angebot.
struct AppVersion: Equatable, Comparable, CustomStringConvertible {
    let components: [Int]

    init?(string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        guard !text.isEmpty else { return nil }

        var parsed: [Int] = []
        for teil in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard let wert = Int(teil), wert >= 0 else { return nil }
            parsed.append(wert)
        }
        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    /// Die Version der laufenden App aus dem Bundle.
    static var current: AppVersion? {
        guard let roh = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return nil
        }
        return AppVersion(string: roh)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let anzahl = max(lhs.components.count, rhs.components.count)
        for index in 0..<anzahl {
            let links = index < lhs.components.count ? lhs.components[index] : 0
            let rechts = index < rhs.components.count ? rhs.components[index] : 0
            if links != rechts { return links < rechts }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
