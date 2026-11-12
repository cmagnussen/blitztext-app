import SwiftUI

/// Popover page for meetings in the room: start with consent, record, evaluate, then read
/// the result with people, summary and transcript. Earlier meetings are listed on the start.
/// Where a meeting takes place: decides whether the Mac's sound is recorded too.
enum MeetingKind: String, CaseIterable, Identifiable {
    case room
    case online

    var id: String { rawValue }

    var title: String {
        switch self {
        case .room: return "Im Raum"
        case .online: return "Online"
        }
    }
}

struct MeetingView: View {
    @Bindable var appState: AppState
    /// The popover height; snapshots render the whole page.
    var height: CGFloat = 560

    @State private var renaming: Int?
    @State private var renamingMeeting = false
    @State private var meetingName = ""
    @State private var newName = ""
    @State private var isResummarizing = false
    @State private var copied: CopyTarget?
    @State private var confirmDelete = false
    /// The meeting a right click in the list wants to delete, until confirmed.
    @State private var deleteCandidate: UUID?
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
            PageHeader(title: headerTitle, onBack: {
                meeting.close()
                appState.page = .main
            })

            Divider().opacity(0.16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let notice = meeting.notice, !isIdle {
                        NoticeRow(icon: "info.circle.fill", title: notice)
                    }

                    if showsArchive {
                        archive
                    } else {
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
                            archive
                        }
                    case .failed(let message, let id):
                        failure(message, meetingID: id)
                    }
                    }
                }
                .padding(16)
            }
        }
        .frame(height: height)
        .confirmationDialog(
            "Meeting l\u{00F6}schen?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
        ) {
            Button("L\u{00F6}schen", role: .destructive) {
                if let id = deleteCandidate { meeting.delete(id) }
                deleteCandidate = nil
            }
            Button("Abbrechen", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("Transkript und Zusammenfassung werden gel\u{00F6}scht.")
        }
        .alert("Person umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Sichern") { saveName() }
            Button("Abbrechen", role: .cancel) { renaming = nil }
        } message: {
            Text("Der Name ersetzt \u{201E}Person \(renaming ?? 0)\u{201C} im Transkript.")
        }
    }

    private var headerTitle: String {
        if showsArchive { return "Meetings" }
        return isIdle ? "Neues Meeting" : "Meeting"
    }

    /// "Meetings" always shows the earlier meetings, also while one is recorded or evaluated.
    /// A result or a failure was opened from the list and shows itself.
    private var showsArchive: Bool {
        guard appState.meetingEntry == .archive else { return false }
        switch meeting.phase {
        case .idle, .recording, .processing: return true
        case .showing, .failed: return false
        }
    }

    private var isIdle: Bool {
        if case .idle = meeting.phase { return true }
        return false
    }

    // MARK: - Start

    /// The main page leads here with the kind of meeting chosen. The switches stay on this
    /// page: they change from meeting to meeting. One row each, the long explanation is the
    /// tooltip.
    private var start: some View {
        VStack(alignment: .leading, spacing: 12) {
            if MeetingController.canRecordSystemAudio {
                SegmentedToggle(
                    options: MeetingKind.allCases,
                    selection: Binding(
                        get: { includesSystemAudio ? .online : .room },
                        set: { includesSystemAudio = $0 == .online }
                    ),
                    label: { $0.title }
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(recordsSystemAudio ? "Online-Meeting" : "Meeting im Raum")
                        .font(.ui(12.5, .semibold))
                    if recordsSystemAudio { BetaBadge() }
                }
                Text(recordsSystemAudio
                     ? "Nimmt dein Mikrofon (Ich) und den Ton des Macs (die anderen) auf, zum Beispiel aus Teams, Zoom oder Meet. Mit Kopfh\u{00F6}rern wird das Transkript am saubersten."
                     : "Nimmt das Mikrofon dieses Macs auf und erkennt, wer spricht. Gedacht f\u{00FC}r Gespr\u{00E4}che vor Ort.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if recordsSystemAudio {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.chatNote, forType: .string)
                        copiedChatNote = true
                    } label: {
                        Label(copiedChatNote ? "Kopiert, im Chat einf\u{00FC}gen" : "Frage f\u{00FC}r den Chat kopieren", systemImage: copiedChatNote ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.subtle)
                    .help("Beim ersten Mal fragt macOS nach der Freigabe f\u{00FC}r Systemaudio.")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPanel()

            VStack(alignment: .leading, spacing: 0) {
                optionRow(
                    "Live-Notizen", isBeta: true,
                    caption: LiveNotesController.isAvailable
                        ? "Schreibt w\u{00E4}hrend des Meetings mit"
                        : "Braucht Apple Intelligence, ein lokales KI-Modell oder einen Modell-Server auf diesem Mac",
                    help: LiveNotesController.isAvailable
                        ? "Alle zweieinhalb Minuten schreibt Blitztext mit, was besprochen und entschieden wurde. Bleibt auf diesem Mac."
                        : "Ein lokales KI-Modell l\u{00E4}dst du in den Einstellungen unter Meeting. Ein Modell-Server l\u{00E4}uft \u{00FC}ber Modelle, Eigene Adresse mit localhost.",
                    isOn: $wantsLiveNotes
                )
                .disabled(!LiveNotesController.isAvailable)
                Divider().opacity(0.5).padding(.horizontal, 14)
                optionRow(
                    "Danach zusammenfassen",
                    caption: "Mit Entscheidungen und To-dos",
                    help: "Aus: nur das Transkript mit Personen, schneller. Die Zusammenfassung geht auch sp\u{00E4}ter.",
                    isOn: $appState.appSettings.summarizesMeetings
                )
            }
            .glassPanel()

            if let blocker = MeetingController.blocker {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    title: blocker,
                    tint: BlitztextTheme.danger,
                    actionTitle: "Einstellungen",
                    action: { appState.openSettings(.models) }
                )
            }

            NoticeRow(
                icon: "hand.raised.fill",
                title: "Bitte vorher alle Anwesenden informieren und um ihr Einverst\u{00E4}ndnis bitten.",
                tint: BlitztextTheme.danger
            )

            Button {
                meeting.start(includingSystemAudio: recordsSystemAudio, liveNotes: wantsLiveNotes)
            } label: {
                Text("Alle sind einverstanden, starten")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.filledAction)
            .disabled(MeetingController.blocker != nil)
        }
    }

    /// "Meetings" on the main page leads here: the earlier meetings, a new one, the settings.
    private var archive: some View {
        VStack(alignment: .leading, spacing: 12) {
            if meeting.isRecording || meeting.isProcessing {
                NoticeRow(
                    icon: "person.2.wave.2.fill",
                    title: meeting.isRecording ? "Meeting wird aufgenommen" : "Meeting wird ausgewertet",
                    actionTitle: "\u{00D6}ffnen",
                    action: { appState.meetingEntry = .start }
                )
            }
            HStack(spacing: 8) {
                Button {
                    appState.meetingEntry = .start
                } label: {
                    Label("Neues Meeting", systemImage: "plus")
                }
                .buttonStyle(.filledAction)
                .disabled(meeting.isRecording || meeting.isProcessing)
                Button {
                    appState.openSettings(.meeting)
                } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .buttonStyle(.glassAction)
                Spacer(minLength: 0)
            }

            if storedMeetings.isEmpty {
                Text("Noch keine Meetings. Nach der Auswertung stehen sie hier mit Transkript und Zusammenfassung.")
                    .font(.ui(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPanel()
            } else {
                earlierMeetings
            }
        }
    }

    private func optionRow(_ title: String, isBeta: Bool = false, caption: String, help: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.ui(12.5, .medium))
                    if isBeta { BetaBadge() }
                }
                Text(caption)
                    .font(.ui(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.trailingSwitch)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .help(help)
    }

    private var recordingTitle: String {
        if meeting.pausedAt != nil { return "Pausiert, nichts wird aufgenommen" }
        return meeting.isRecordingSystemAudio ? "Aufnahme l\u{00E4}uft, mit Ton des Macs" : "Aufnahme l\u{00E4}uft"
    }

    private var recordsSystemAudio: Bool {
        includesSystemAudio && MeetingController.canRecordSystemAudio
    }

    /// Asked in the call's chat before starting, so everyone can agree in writing.
    static let chatNote = "Ich w\u{00FC}rde dieses Meeting gern mit Blitztext aufnehmen und auf meinem Mac transkribieren und zusammenfassen lassen. Ton und Text bleiben auf meinem Mac, die Aufnahme wird nach der Auswertung gel\u{00F6}scht. Ist das f\u{00FC}r alle in Ordnung?"

    private var storedMeetings: [MeetingRecord] {
        meeting.store.meetings.filter { $0.id != meeting.recordingID }
    }

    private var earlierMeetings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Fr\u{00FC}here Meetings")
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
                        Button("L\u{00F6}schen", role: .destructive) { deleteCandidate = record.id }
                    }
                    .help("Rechtsklick zum L\u{00F6}schen")
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
                Button {
                    meetingName = record.title
                    renamingMeeting = true
                } label: {
                    HStack(spacing: 6) {
                        Text(record.title)
                            .font(.ui(15, .semibold))
                            .multilineTextAlignment(.leading)
                        Image(systemName: "pencil")
                            .font(.ui(10, .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Meeting umbenennen")
                .alert("Meeting umbenennen", isPresented: $renamingMeeting) {
                    TextField("Name", text: $meetingName)
                    Button("Sichern") { meeting.rename(meeting: record.id, to: meetingName) }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Leer lassen, um wieder Datum und Uhrzeit zu zeigen.")
                }
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
                SectionHeader(title: "Transkript: Name anklicken zum Zuordnen")
                ForEach(record.turns) { turn in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            // The speaker detection sometimes mixes up two voices; one part can
                            // go to another person without renaming the whole person.
                            Menu {
                                ForEach(record.speakers.filter { $0 != turn.speaker }, id: \.self) { speaker in
                                    Button(record.name(for: speaker)) {
                                        meeting.reassign(turn: turn.id, to: speaker, in: record.id)
                                    }
                                }
                                Divider()
                                Button("Neue Person") {
                                    meeting.reassign(turn: turn.id, to: record.turns.nextSpeaker, in: record.id)
                                }
                            } label: {
                                Text(record.name(for: turn.speaker))
                                    .font(.ui(11.5, .semibold))
                                    .foregroundStyle(color(for: turn.speaker))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Diesen Abschnitt einer anderen Person zuordnen")
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
                Text(summaryText(summary))
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

    /// The summary with its section titles in semibold.
    private func summaryText(_ summary: String) -> AttributedString {
        var text = AttributedString()
        for (index, line) in SummaryDisplay.lines(summary).enumerated() {
            var part = AttributedString((index > 0 ? "\n" : "") + line.text)
            if line.isTitle { part.font = .ui(12.5, .semibold) }
            text += part
        }
        return text
    }

    private func copyButton(_ title: String, target: CopyTarget, text: String) -> some View {
        Button {
            if target == .summary {
                MeetingSummaryClipboard.copy(text)
            } else {
                appState.copyToClipboard(text)
            }
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
