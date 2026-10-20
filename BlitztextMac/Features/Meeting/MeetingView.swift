import SwiftUI

/// Popover page for meetings in the room: start with consent, record, evaluate, then read
/// the result with people, summary and transcript. Earlier meetings are listed on the start.
struct MeetingView: View {
    @Bindable var appState: AppState
    /// The popover height; snapshots render the whole page.
    var height: CGFloat = 560

    @State private var renaming: Int?
    @State private var newName = ""
    @State private var isResummarizing = false
    @State private var copied: CopyTarget?
    @State private var confirmDelete = false
    @AppStorage("BlitztextMeetingSystemAudio") private var includesSystemAudio = false
    @AppStorage("BlitztextMeetingLiveNotes") private var wantsLiveNotes = true
    @State private var copiedChatNote = false

    private enum CopyTarget { case summary, transcript, everything }

    private var meeting: MeetingController { appState.meeting }

    /// The Blackboat accents, one per person.
    private static let personColors: [Color] = [
        BlackboatColor.Source.day.primary, BlackboatColor.Source.night.primary, BlackboatColor.Source.evening.primary,
        BlackboatColor.dynamic(light: 0x0B0EC1, dark: 0xB7F1F9), BlackboatColor.dynamic(light: 0x5F287B, dark: 0xBB84DF),
        BlackboatColor.dynamic(light: 0x3C277C, dark: 0xA592DD),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Meeting", onBack: {
                meeting.close()
                appState.page = .main
            })

            Divider().opacity(0.16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let notice = meeting.notice, !isIdle {
                        NoticeRow(icon: "info.circle.fill", title: notice)
                    }

                    switch meeting.phase {
                    case .idle:
                        start
                    case .recording(let startedAt):
                        recording(since: startedAt)
                    case .processing(let step):
                        processing(step)
                    case .showing(let id):
                        if let record = meeting.store.meeting(id: id) {
                            result(record)
                        } else {
                            start
                        }
                    case .failed(let message, let id):
                        failure(message, meetingID: id)
                    }
                }
                .padding(16)
            }
        }
        .frame(height: height)
        .alert("Person umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Sichern") { saveName() }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        } message: {
            Text("Der Name ersetzt \u{201E}Person \(renaming ?? 0)\u{201C} im Transkript.")
        }
    }

    private var isIdle: Bool {
        if case .idle = meeting.phase { return true }
        return false
    }

    // MARK: - Start

    private var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Meeting aufnehmen", systemImage: "person.2.wave.2.fill")
                    .font(.ui(15, .semibold))
                    .foregroundStyle(BlitztextTheme.accent)
                Text("Blitztext nimmt das Gespr\u{00E4}ch im Raum \u{00FC}ber das Mikrofon auf, erkennt, wer spricht, und schreibt auf Wunsch eine Zusammenfassung mit To-dos. Alles l\u{00E4}uft auf diesem Mac, die Aufnahme wird nach der Auswertung gel\u{00F6}scht.")
                    .font(.ui(12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()

            NoticeRow(
                icon: "hand.raised.fill",
                title: "Bitte vorher alle Anwesenden informieren und um ihr Einverst\u{00E4}ndnis bitten.",
                tint: BlitztextTheme.danger
            )

            if MeetingController.canRecordSystemAudio {
                onlineMeeting
            }

            Toggle(isOn: $wantsLiveNotes) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Live-Notizen")
                            .font(.ui(12.5, .medium))
                        BetaBadge()
                    }
                    Text(LiveNotesController.isAvailable
                         ? "Alle zweieinhalb Minuten schreibt Blitztext mit, was besprochen und entschieden wurde. Bleibt auf diesem Mac."
                         : "Brauchen Apple Intelligence oder ein lokales Sprachmodell (Einstellungen, Modelle).")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.trailingSwitch)
            .disabled(!LiveNotesController.isAvailable)
            .padding(14)
            .glassPanel()

            Toggle(isOn: $appState.appSettings.summarizesMeetings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Danach zusammenfassen")
                        .font(.ui(12.5, .medium))
                    Text("Aus: nur das Transkript mit Personen, schneller. Die Zusammenfassung geht auch sp\u{00E4}ter.")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.trailingSwitch)
            .padding(14)
            .glassPanel()

            if let blocker = MeetingController.blocker {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    title: blocker,
                    tint: BlitztextTheme.danger,
                    actionTitle: ParakeetTranscriber.isSupported ? "Einstellungen" : nil,
                    action: ParakeetTranscriber.isSupported ? { appState.page = .settings } : nil
                )
            }

            Button {
                meeting.start(includingSystemAudio: recordsSystemAudio, liveNotes: wantsLiveNotes)
            } label: {
                Text("Alle sind einverstanden, starten")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.filledAction)
            .disabled(MeetingController.blocker != nil)

            Text(recordsSystemAudio
                 ? "Nimmt dein Mikrofon (Ich) und den Ton des Macs (die anderen) auf. Mit Kopfh\u{00F6}rern wird das Transkript am saubersten."
                 : "Nimmt nur das Mikrofon auf, gedacht f\u{00FC}r Meetings im Raum.")
                .font(.ui(11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !storedMeetings.isEmpty {
                earlierMeetings
            }
        }
    }

    private var recordingTitle: String {
        if meeting.pausedAt != nil { return "Pausiert, nichts wird aufgenommen" }
        return meeting.isRecordingSystemAudio ? "Aufnahme l\u{00E4}uft, mit Ton des Macs" : "Aufnahme l\u{00E4}uft"
    }

    private var recordsSystemAudio: Bool {
        includesSystemAudio && MeetingController.canRecordSystemAudio
    }

    /// Asked in the call's chat before starting, so everyone can agree in writing.
    static let chatNote = "Ich schreibe dieses Meeting lokal mit Blitztext mit. Der Ton verl\u{00E4}sst meinen Mac nicht und wird nach der Auswertung gel\u{00F6}scht. Ist das f\u{00FC}r alle in Ordnung?"

    private var onlineMeeting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $includesSystemAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Online-Meeting")
                            .font(.ui(12.5, .medium))
                        BetaBadge()
                    }
                    Text("Nimmt auch den Ton des Macs auf, zum Beispiel aus Teams, Zoom oder Meet. Beim ersten Mal fragt macOS nach der Freigabe f\u{00FC}r Systemaudio.")
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.trailingSwitch)

            if includesSystemAudio {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.chatNote, forType: .string)
                    copiedChatNote = true
                } label: {
                    Label(copiedChatNote ? "Kopiert, im Chat einf\u{00FC}gen" : "Frage f\u{00FC}r den Chat kopieren", systemImage: copiedChatNote ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.subtle)
            }
        }
        .padding(14)
        .glassPanel()
    }

    private var storedMeetings: [MeetingRecord] {
        meeting.store.meetings.filter { $0.id != meeting.recordingID }
    }

    private var earlierMeetings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Meetings (Rechtsklick zum L\u{00F6}schen)")
            VStack(spacing: 0) {
                ForEach(Array(storedMeetings.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        Divider().opacity(0.5).padding(.horizontal, 12)
                    }
                    Button {
                        if record.status == .done {
                            meeting.show(record.id)
                        } else {
                            meeting.process(record.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.title)
                                    .font(.ui(12.5, .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(record.status == .done ? summaryLine(record) : "Noch nicht ausgewertet, klicken zum Auswerten")
                                    .font(.ui(11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.ui(10, .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("L\u{00F6}schen", role: .destructive) { meeting.delete(record.id) }
                    }
                }
            }
            .padding(.vertical, 2)
            .glassPanel()
        }
    }

    // MARK: - Recording and processing

    private func recording(since startedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(meeting.pausedAt == nil ? BlitztextTheme.danger : Color.secondary)
                        .frame(width: 9, height: 9)
                    Text(recordingTitle)
                        .font(.ui(13, .semibold))
                    Spacer()
                    if let pausedAt = meeting.pausedAt {
                        Text(Self.clock(pausedAt.timeIntervalSince(startedAt)))
                            .font(.ui(13, .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text(Self.clock(context.date.timeIntervalSince(startedAt)))
                                .font(.ui(13, .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                WaveformView(audioLevel: meeting.audioLevel, isRecording: true, accentColor: BlitztextTheme.accent)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
            }
            .padding(14)
            .glassPanel()

            if let live = meeting.liveNotes {
                LiveNotesCard(live: live)
            }

            Text("Du kannst das Men\u{00FC} schlie\u{00DF}en, die Aufnahme l\u{00E4}uft weiter. Das Symbol in der Men\u{00FC}leiste zeigt sie an. Bitte den Mac nicht zuklappen.")
                .font(.ui(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                meeting.stop()
            } label: {
                Label("Beenden und auswerten", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.filledAction)

            Button {
                if meeting.pausedAt == nil { meeting.pause() } else { meeting.resume() }
            } label: {
                Label(meeting.pausedAt == nil ? "Pausieren" : "Fortsetzen", systemImage: meeting.pausedAt == nil ? "pause.fill" : "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.subtle)

            Button("Verwerfen", role: .destructive) {
                meeting.discard()
            }
            .buttonStyle(.subtle)
            .frame(maxWidth: .infinity)
        }
    }

    private func processing(_ step: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(step)
                    .font(.ui(12.5, .medium))
            }
            Text("Bei langen Meetings dauert das ein paar Minuten, alles l\u{00E4}uft auf diesem Mac. Beim ersten Mal l\u{00E4}dt Blitztext dazu einmalig das Modell f\u{00FC}r die Stimmen.")
                .font(.ui(11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel()
    }

    private func failure(_ message: String, meetingID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.ui(12.5))
                .foregroundStyle(BlitztextTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassPanel()

            HStack(spacing: 8) {
                if let meetingID, meeting.store.meeting(id: meetingID)?.status == .pending {
                    Button("Erneut auswerten") { meeting.process(meetingID) }
                        .buttonStyle(.filledAction)
                }
                Button("Zur\u{00FC}ck") { meeting.close() }
                    .buttonStyle(.glassAction)
                Spacer()
                if let meetingID, meeting.store.meeting(id: meetingID) != nil {
                    Button(role: .destructive) {
                        meeting.delete(meetingID)
                    } label: {
                        Text("L\u{00F6}schen")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.subtle)
                }
            }
        }
    }

    // MARK: - Result

    private func result(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.ui(15, .semibold))
                Text(summaryLine(record))
                    .font(.ui(11.5))
                    .foregroundStyle(.secondary)
            }

            // At the top: a long meeting would put them far below the transcript.
            HStack(spacing: 8) {
                // The bare transcript by person, e.g. to continue in another AI app.
                copyButton("Transkript kopieren", target: .transcript, text: record.transcriptShareText)
                if record.summary != nil {
                    copyButton("Alles kopieren", target: .everything, text: record.shareText)
                }
                Spacer()
            }

            summaryCard(record)

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Personen: Klicken zum Umbenennen")
                FlowLayout(spacing: 6) {
                    ForEach(record.speakers, id: \.self) { speaker in
                        Button {
                            newName = record.speakerNames[speaker] ?? ""
                            renaming = speaker
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(color(for: speaker)).frame(width: 7, height: 7)
                                Text(record.name(for: speaker))
                                Image(systemName: "pencil")
                                    .font(.ui(9, .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.ui(12, .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(BlitztextTheme.card))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Transkript")
                ForEach(record.turns) { turn in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(record.name(for: turn.speaker))
                                .font(.ui(11.5, .semibold))
                                .foregroundStyle(color(for: turn.speaker))
                            Text(Self.clock(turn.start))
                                .font(.ui(11).monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                        Text(turn.text)
                            .font(.ui(12.5))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel()
                }
            }

            HStack(spacing: 8) {
                Spacer()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("L\u{00F6}schen")
                        .lineLimit(1)
                        .fixedSize()
                }
                .buttonStyle(.subtle)
                    .confirmationDialog("Meeting l\u{00F6}schen?", isPresented: $confirmDelete) {
                        Button("L\u{00F6}schen", role: .destructive) { meeting.delete(record.id) }
                    }
            }
        }
    }

    private func summaryCard(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Zusammenfassung", systemImage: "sparkles")
                    .font(.ui(12.5, .semibold))
                    .foregroundStyle(BlitztextTheme.accent)
                Spacer()
                if isResummarizing {
                    ProgressView().controlSize(.small)
                }
            }

            if let summary = record.summary {
                Text(ListDisplay.bullets(summary))
                    .font(.ui(12.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let note = record.summaryNote {
                    Text(note)
                        .font(.ui(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Automatisch erstellt. Bitte vor allem die Zust\u{00E4}ndigkeiten bei den To-dos kurz pr\u{00FC}fen.")
                    .font(.ui(11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    copyButton("Kopieren", target: .summary, text: summary)
                    Button {
                        resummarize(record.id)
                    } label: {
                        Label("Neu erstellen", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glassAction)
                    .disabled(isResummarizing)
                }
            } else {
                Text(record.summaryNote ?? "Noch keine Zusammenfassung.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Zusammenfassung erstellen") { resummarize(record.id) }
                    .buttonStyle(.glassAction)
                    .disabled(isResummarizing)
            }
        }
        .padding(14)
        .glassPanel()
    }

    private func copyButton(_ title: String, target: CopyTarget, text: String) -> some View {
        Button {
            appState.copyToClipboard(text)
            copied = target
        } label: {
            Label(copied == target ? "Kopiert" : title, systemImage: copied == target ? "checkmark" : "doc.on.doc")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.glassAction)
    }

    // MARK: - Helpers

    private func saveName() {
        guard let speaker = renaming, case .showing(let id) = meeting.phase else { return }
        meeting.rename(speaker: speaker, to: newName, in: id)
        renaming = nil
    }

    private func resummarize(_ id: UUID) {
        isResummarizing = true
        copied = nil
        Task {
            await meeting.resummarize(id)
            isResummarizing = false
        }
    }

    private func summaryLine(_ record: MeetingRecord) -> String {
        let minutes = Int((record.duration / 60).rounded())
        let duration = minutes < 1 ? "unter 1 Min." : "\(minutes) Min."
        let people = record.speakers.count == 1 ? "1 Person" : "\(record.speakers.count) Personen"
        return "\(duration), \(people)"
    }

    private func color(for speaker: Int) -> Color {
        Self.personColors[(max(speaker, 1) - 1) % Self.personColors.count]
    }

    /// "4:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
