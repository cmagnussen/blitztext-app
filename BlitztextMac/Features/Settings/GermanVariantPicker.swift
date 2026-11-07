import SwiftUI

/// "Schreibweise": German as in Germany and Austria, or as in Switzerland and Liechtenstein.
/// "Automatisch" shows which of the two applies on this Mac and updates when the region
/// changes in macOS.
struct GermanVariantPicker: View {
    @Binding var selection: GermanVariant
    @State private var systemIsSwiss = GermanVariant.systemIsSwiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Schreibweise")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)

                Picker("", selection: $selection) {
                    ForEach(GermanVariant.allCases) { variant in
                        Text(variant.label(systemIsSwiss: systemIsSwiss)).tag(variant)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            Text("Deutsch (Schweiz) schreibt ss statt \u{00DF}, gliedert grosse Zahlen mit Apostroph (12\u{2019}500), Betr\u{00E4}ge mit Punkt (CHF 23.50) und Anf\u{00FC}hrungszeichen als \u{00AB}\u{2026}\u{00BB}, auch in den KI-Modi und Meeting-Zusammenfassungen. Schweizer W\u{00F6}rter wie Velo bleiben stehen. Automatisch folgt Region und Sprache von macOS: In der Schweiz und in Liechtenstein gilt Deutsch (Schweiz), sonst Deutsch.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            systemIsSwiss = GermanVariant.systemIsSwiss
        }
    }
}
