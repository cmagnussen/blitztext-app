import Foundation

/// Whether a downloaded speech model is complete. FluidAudio only checks that the model
/// folders exist; a download that iOS or a quit interrupted leaves folders without their
/// weights, which then fail at every dictation.
enum CompiledModelCheck {
    /// Every compiled model in `directory` has its description, program and weights, and no
    /// file is still half downloaded.
    static func isComplete(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        let models = items.filter { $0.pathExtension == "mlmodelc" }
        guard !models.isEmpty else { return false }
        for model in models {
            for part in ["coremldata.bin", "model.mil", "weights/weight.bin"]
            where !fileManager.fileExists(atPath: model.appendingPathComponent(part).path) {
                return false
            }
        }
        let files = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            if file.pathExtension == "partial" { return false }
        }
        return true
    }
}
