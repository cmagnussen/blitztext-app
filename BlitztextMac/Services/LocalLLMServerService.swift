import Foundation
import OSLog

private let llmServerLogger = Logger(subsystem: "app.blitztext.mac", category: "LocalLLMServer")

/// Startet und stoppt bei Bedarf einen lokalen `llama-server` für die KI-Rewrite-Features,
/// damit der Nutzer ihn nicht manuell starten muss. Der Server läuft als Kindprozess von
/// Blitztext und wird beim Beenden der App wieder gestoppt.
///
/// Läuft bereits ein Server auf dem konfigurierten Port (z. B. manuell per Skript gestartet),
/// wird kein zweiter gestartet – Blitztext nutzt dann den vorhandenen.
@MainActor
final class LocalLLMServerService {
    private var process: Process?

    /// Startet den Server, falls das lokale KI-Modell aktiv ist, Autostart eingeschaltet ist
    /// und noch kein erreichbarer Server läuft.
    func startIfNeeded(settings: AppSettings) {
        guard settings.localLLMEnabled, settings.localLLMAutostart else { return }
        guard process == nil else { return }

        let port = Self.port(from: settings.localLLMBaseURL)
        let binary = settings.localLLMServerPath
        let model = settings.localLLMModelPath

        Task { [weak self] in
            // Läuft schon (z. B. manuell per start-local-llm.sh)? Dann nichts tun.
            if await Self.isReachable(port: port) {
                llmServerLogger.info("Lokaler LLM-Server läuft bereits auf Port \(port, privacy: .public).")
                return
            }
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                llmServerLogger.error("llama-server nicht gefunden unter \(binary, privacy: .public).")
                return
            }
            guard FileManager.default.fileExists(atPath: model) else {
                llmServerLogger.error("Modelldatei nicht gefunden unter \(model, privacy: .public).")
                return
            }
            self?.spawn(binary: binary, model: model, port: port)
        }
    }

    /// Beendet den von uns gestarteten Server (kein Effekt, wenn wir keinen gestartet haben).
    func stop() {
        guard let process else { return }
        process.terminate()
        self.process = nil
        llmServerLogger.info("Lokaler LLM-Server gestoppt.")
    }

    private func spawn(binary: String, model: String, port: Int) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)

        var arguments = [
            "-m", model,
            "--host", "127.0.0.1",
            "--port", String(port),
            "--jinja",
            "-ngl", "99",
            "-c", "8192",
            "--parallel", "1",
        ]
        // Qwen-3 nativ laufen lassen (stoppt zuverlässig); llama-server filtert den
        // Denk-Teil serverseitig, sodass die zurückgegebene Antwort sauber bleibt.
        let modelName = (model as NSString).lastPathComponent.lowercased()
        if modelName.contains("qwen3") || modelName.contains("qwen-3") || modelName.contains("qwen_3") {
            arguments += ["--reasoning", "on"]
        }
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
            llmServerLogger.info("Lokaler LLM-Server gestartet (Port \(port, privacy: .public)).")
        } catch {
            llmServerLogger.error("llama-server konnte nicht gestartet werden: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func port(from baseURL: String) -> Int {
        URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.port ?? 8080
    }

    private static func isReachable(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
