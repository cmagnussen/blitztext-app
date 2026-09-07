import Foundation

enum UpdateDownloadError: LocalizedError {
    case serverAntwortet(Int)
    case signaturFehlt
    case abgebrochen

    var errorDescription: String? {
        switch self {
        case .serverAntwortet(let code):
            return "Der Download endete mit Status \(code)."
        case .signaturFehlt:
            return "Zum Archiv gibt es keine lesbare Signatur."
        case .abgebrochen:
            return "Der Download wurde abgebrochen."
        }
    }
}

/// Laedt Signatur und Archiv eines Release in einen Zielordner.
///
/// Der Fortschritt kommt ueber den Delegate der klassischen Download-API.
/// Die async-Variante von URLSession meldet keinen Fortschritt, und ein
/// byteweises AsyncSequence waere bei einem Archiv dieser Groesse zu langsam.
final class UpdateDownloader: NSObject, @unchecked Sendable {
    struct Ergebnis {
        let archivURL: URL
        let signatur: Data
    }

    private var session: URLSession!
    private var fortschritt: ((Double) -> Void)?
    private var weiter: CheckedContinuation<URL, Error>?
    private var zielURL: URL?

    override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func download(
        _ release: UpdateRelease,
        into ordner: URL,
        fortschritt: @escaping (Double) -> Void
    ) async throws -> Ergebnis {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)

        // Erst die Signatur, sie ist klein. Fehlt sie, sparen wir das Archiv.
        let signaturDaten = try await ladeKleineDatei(release.signatureURL)
        guard let signatur = UpdateSignatureVerifier.signature(fromFileContents: signaturDaten) else {
            throw UpdateDownloadError.signaturFehlt
        }

        let ziel = ordner.appendingPathComponent(UpdateFeedClient.archiveAssetName)
        try? FileManager.default.removeItem(at: ziel)

        self.fortschritt = fortschritt
        self.zielURL = ziel

        let archiv: URL = try await withCheckedThrowingContinuation { weiter in
            self.weiter = weiter
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
        fortschritt?(anteil)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Die Datei an location verschwindet, sobald diese Methode zurueckkehrt.
        guard let ziel = zielURL else {
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
        guard let weiter else { return }
        self.weiter = nil
        switch ergebnis {
        case .success(let url): weiter.resume(returning: url)
        case .failure(let fehler): weiter.resume(throwing: fehler)
        }
    }
}
