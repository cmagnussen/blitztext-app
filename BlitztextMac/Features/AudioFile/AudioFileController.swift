import AppKit
import Foundation
import Observation

/// Transcribes an audio file on this Mac: Voice Memos from the iPhone (m4a), WhatsApp
/// voice messages (Opus in Ogg) and anything else macOS can decode. The result lands on
/// the clipboard and in the history; the AI modes can rewrite it afterwards.
@Observable
@MainActor
final class AudioFileController {
    enum Phase: Equatable {
        case idle
        case working(String)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var fileName = ""
    private(set) var duration: TimeInterval = 0
    private(set) var transcript = ""
    private(set) var text = ""
    private(set) var mode: WorkflowType = .tapTalk
    private(set) var copied = false

    private var task: Task<Void, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func transcribe(_ url: URL, appState: AppState) {
        task?.cancel()
        fileName = url.lastPathComponent
        duration = 0
        transcript = ""
        text = ""
        mode = .tapTalk
        copied = false

        guard appState.selectedLocalModelIsInstalled else {
            phase = .failed("Zuerst in den Einstellungen ein lokales Sprachmodell laden.")
            return
        }

        phase = .working("Wird umgewandelt ...")
        let language = appState.transcriptionSettings.language
        let modelName = appState.selectedLocalModelName
        let postProcessor = appState.postProcessor
        let paragraphs = appState.appSettings.automaticParagraphs

        task = Task {
            do {
                let wav = try await Task.detached(priority: .userInitiated) {
                    try AudioFileConverter.convertToWAV(url)
                }.value
                defer { try? FileManager.default.removeItem(at: wav.url) }
                duration = wav.duration
                if Task.isCancelled { return }

                phase = .working("Wird transkribiert ...")
                let raw = try await LocalTranscriptionService.transcribe(
                    audioURL: wav.url,
                    language: language,
                    modelName: modelName
                ) { [weak self] in
                    self?.phase = .working(LocalTranscriptionService.slowPreparationMessage)
                }
                var processed = postProcessor.process(TranscriptionQualityService.cleanedTranscript(raw))
                if paragraphs {
                    processed = TranscriptParagraphService.format(processed, language: language)
                }
                guard !processed.isEmpty else {
                    phase = .failed("In der Datei wurde keine Sprache erkannt.")
                    return
                }
                if Task.isCancelled { return }

                transcript = processed
                finish(processed, mode: .tapTalk, appState: appState)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func rewrite(as newMode: WorkflowType, appState: AppState) {
        guard !transcript.isEmpty, let instruction = Self.instruction(for: newMode, appState: appState) else { return }
        task?.cancel()
        copied = false
        phase = .working("\(appState.displayName(for: newMode)) wird formuliert ...")
        let engine = appState.appSettings.rewriteEngine
        let source = transcript

        task = Task {
            do {
                let rewritten = try await TextRewriter.rewrite(source, instruction: instruction, engine: engine)
                let cleaned = TranscriptionQualityService.cleanedTranscript(rewritten)
                if Task.isCancelled { return }
                finish(cleaned, mode: newMode, appState: appState)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func showTranscript(appState: AppState) {
        guard !transcript.isEmpty else { return }
        text = transcript
        mode = .tapTalk
        copy(appState: appState)
    }

    func copy(appState: AppState) {
        appState.copyToClipboard(text)
        copied = true
    }

    func close() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    private func finish(_ result: String, mode: WorkflowType, appState: AppState) {
        text = result
        self.mode = mode
        appState.history.add(result, workflow: mode)
        copy(appState: appState)
        phase = .done
    }

    private static func instruction(for mode: WorkflowType, appState: AppState) -> String? {
        switch mode {
        case .textImprover: return ModePrompts.textImprovement(appState.textImprovementSettings)
        case .dampfAblassen: return ModePrompts.dampfAblassen(appState.dampfAblassenSettings)
        case .emojiText: return ModePrompts.emoji(appState.emojiTextSettings)
        case .tapTalk, .localTapTalk: return nil
        }
    }
}
