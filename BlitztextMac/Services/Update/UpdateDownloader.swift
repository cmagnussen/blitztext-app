import Foundation

enum UpdateDownloadError: LocalizedError {
    case serverAntwortet(Int)
    case signaturFehlt
    case abgebrochen
    case bereitsGestartet

    var errorDescription: String? {
        switch self {
        case .serverAntwortet(let code):
            return "Der Download endete mit Status \(code)."
        case .signaturFehlt:
            return "Zum Archiv gibt es keine lesbare Signatur."
        case .abgebrochen:
            return "Der Download wurde abgebrochen."
        case .bereitsGestartet:
            return "Dieser Downloader hat bereits einen Download gestartet."
        }
    }
}

/// Laedt Signatur und Archiv eines Release in einen Zielordner.
///
/// Der Fortschritt kommt ueber den Delegate der klassischen Download-API.
/// Die async-Variante von URLSession meldet keinen Fortschritt, und ein
/// byteweises AsyncSequence waere bei einem Archiv dieser Groesse zu langsam.
///
/// Eine Instanz ist nur fuer einen einzigen Aufruf von `download(...)` gedacht:
/// am Ende des Aufrufs wird die interne URLSession invalidiert, danach ist die
/// Instanz verbraucht. Fuer jeden Installationsversuch gehoert eine frische
/// `UpdateDownloader()`-Instanz angelegt.
final class UpdateDownloader: NSObject, @unchecked Sendable {
    struct Ergebnis {
        let archivURL: URL
        let signatur: Data
    }

    private var session: URLSession!

    // `fortschritt`, `weiter` und `zielURL` werden aus dem Aufrufer-Kontext
    // geschrieben und aus der Delegate-Queue der URLSession (nebenlaeufig zum
    // Aufrufer) gelesen und geschrieben. `sperre` schuetzt alle drei Zugriffe.
    // Damit ist `@unchecked Sendable` eine ehrliche Zusage und keine
    // unterdrueckte Warnung.
    private let sperre = NSLock()
    private var fortschritt: ((Double) -> Void)?
    private var weiter: CheckedContinuation<URL, Error>?
    private var zielURL: URL?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    /// Laedt Signatur und Archiv des Release nach `ordner`.
    ///
    /// `fortschritt` wird auf einem Hintergrund-Thread aufgerufen (der
    /// Delegate-Queue der URLSession), niemals auf dem Main-Thread. Wer damit
    /// UI-Zustand aktualisiert, muss selbst auf den Main-Thread wechseln.
    ///
    /// Diese Instanz ist nur fuer einen Aufruf gedacht: am Ende wird die
    /// interne URLSession invalidiert. Ein zweiter Aufruf auf derselben
    /// Instanz, ob gleichzeitig oder danach, scheitert mit
    /// `UpdateDownloadError.bereitsGestartet`.
    func download(
        _ release: UpdateRelease,
        into ordner: URL,
        fortschritt: @escaping (Double) -> Void
    ) async throws -> Ergebnis {
        sperre.lock()
        guard self.fortschritt == nil else {
            sperre.unlock()
            throw UpdateDownloadError.bereitsGestartet
        }
        self.fortschritt = fortschritt
        sperre.unlock()

        defer { session.finishTasksAndInvalidate() }

        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        // Erst die Signatur, sie ist klein. Fehlt sie, sparen wir das Archiv.
        let signaturDaten = try await ladeKleineDatei(release.signatureURL)
        guard let signatur = UpdateSignatureVerifier.signature(fromFileContents: signaturDaten) else {
            throw UpdateDownloadError.signaturFehlt
        }

        let ziel = ordner.appendingPathComponent(UpdateFeedClient.archiveAssetName)
        try? FileManager.default.removeItem(at: ziel)

        sperre.lock()
        self.zielURL = ziel
        sperre.unlock()

        let archiv: URL = try await withCheckedThrowingContinuation { weiter in
            sperre.lock()
            self.weiter = weiter
            sperre.unlock()
            session.downloadTask(with: release.archiveURL).resume()
        }
        return Ergebnis(archivURL: archiv, signatur: signatur)
    }

    private func ladeKleineDatei(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (daten, antwort) = try await URLSession.shared.data(for: request)
        guard let http = antwort as? HTTPURLResponse else {
            throw UpdateDownloadError.abgebrochen
        }
        guard http.statusCode == 200 else {
            throw UpdateDownloadError.serverAntwortet(http.statusCode)
        }
        return daten
    }
}

extension UpdateDownloader: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let anteil = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1)

        sperre.lock()
        let aufruf = fortschritt
        sperre.unlock()

        aufruf?(anteil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Die Datei an location verschwindet, sobald diese Methode zurueckkehrt.
        sperre.lock()
        let ziel = zielURL
        sperre.unlock()

        guard let ziel else {
            beende(mit: .failure(UpdateDownloadError.abgebrochen))
            return
        }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateDownloadError.serverAntwortet(http.statusCode)
            }
            try FileManager.default.moveItem(at: location, to: ziel)
            beende(mit: .success(ziel))
        } catch {
            beende(mit: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        beende(mit: .failure(error))
    }

    private func beende(mit ergebnis: Result<URL, Error>) {
        sperre.lock()
        guard let weiter else {
            sperre.unlock()
            return
        }
        self.weiter = nil
        sperre.unlock()

        switch ergebnis {
        case .success(let url): weiter.resume(returning: url)
        case .failure(let fehler): weiter.resume(throwing: fehler)
        }
    }
}
