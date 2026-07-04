import AppKit

enum MenuBarStatus: Equatable {
    case idle
    case recording(WorkflowType)
    case processing(WorkflowType)
    case success(WorkflowType?)
    case error(WorkflowType?)
}

@MainActor
final class MenuBarStatusController {
    private weak var button: NSStatusBarButton?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var animationPhase: Double = 0
    private var currentStatus: MenuBarStatus = .idle

    /// Umschaltbares Theme: modern = Ring-Icon, klassisch = Streifen-Icon.
    var useModernTheme = false {
        didSet {
            guard oldValue != useModernTheme else { return }
            configureAnimationIfNeeded()
            renderCurrentStatus()
        }
    }

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        renderCurrentStatus()
    }

    func update(to status: MenuBarStatus) {
        currentStatus = status
        animationFrame = 0
        animationPhase = 0
        configureAnimationIfNeeded()
        renderCurrentStatus()
    }

    private func configureAnimationIfNeeded() {
        stopAnimation()

        switch currentStatus {
        case .recording:
            startAnimation(interval: useModernTheme ? 1.0 / 30.0 : 0.12)
        case .processing:
            startAnimation(interval: useModernTheme ? 1.0 / 30.0 : 0.18)
        default:
            break
        }
    }

    private func startAnimation(interval: TimeInterval) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick(interval)
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func tick(_ interval: TimeInterval) {
        animationFrame = (animationFrame + 1) % 4
        animationPhase += interval
        renderCurrentStatus()
    }

    private func renderCurrentStatus() {
        guard let button else { return }
        if useModernTheme {
            let rendered = MenuBarRingIcon.makeImage(for: currentStatus, phase: animationPhase)
            rendered.image.isTemplate = rendered.isTemplate
            button.image = rendered.image
        } else {
            let image = MenuBarStatusIconRenderer.makeImage(for: currentStatus, frame: animationFrame)
            image.isTemplate = true
            button.image = image
        }
        button.toolTip = tooltip(for: currentStatus)
    }

    private func tooltip(for status: MenuBarStatus) -> String {
        switch status {
        case .idle:
            return "Blitztext ist bereit"
        case .recording(let type):
            return "\(type.displayName): Aufnahme läuft"
        case .processing(let type):
            return "\(type.displayName): Verarbeitung läuft"
        case .success(let type):
            if let type {
                return "\(type.displayName): Fertig"
            }
            return "Blitztext: Fertig"
        case .error(let type):
            if let type {
                return "\(type.displayName): Fehler"
            }
            return "Blitztext: Fehler"
        }
    }

    deinit {
        animationTimer?.invalidate()
    }
}

private enum MenuBarStatusIconRenderer {
    static func makeImage(for status: MenuBarStatus, frame: Int) -> NSImage {
        if case .idle = status, let baseImage = baseTemplateImage() {
            return baseImage
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { bounds in
            drawBaseIcon(in: bounds, status: status, frame: frame)

            switch status {
            case .recording(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .recording
                )
            case .processing(let type):
                drawActivityBadge(
                    type: type,
                    systemName: badgeSymbol(for: type),
                    in: bounds,
                    frame: frame,
                    phase: .processing
                )
            case .success:
                drawBadge(systemName: "checkmark", in: bounds, fillOpacity: 1.0)
            case .error:
                drawBadge(systemName: "exclamationmark", in: bounds, fillOpacity: 1.0)
            default:
                break
            }

            return true
        }
        image.isTemplate = true
        image.size = size
        return image
    }

    private enum ActivityPhase {
        case recording
        case processing
    }

    private static func drawBaseIcon(in bounds: CGRect, status: MenuBarStatus, frame: Int) {
        let stripeWidths: [CGFloat] = [12, 10, 8, 6]
        let stripeHeight: CGFloat = 2
        let stripeSpacing: CGFloat = 1.6
        let totalHeight = (CGFloat(stripeWidths.count) * stripeHeight) + (CGFloat(stripeWidths.count - 1) * stripeSpacing)
        let originY = bounds.midY - (totalHeight / 2)
        let baseAlpha = baseAlphaValues(for: status, frame: frame)

        for (index, width) in stripeWidths.enumerated() {
            let x = bounds.midX - (width / 2)
            let y = originY + CGFloat(index) * (stripeHeight + stripeSpacing)
            let rect = CGRect(x: x, y: y, width: width, height: stripeHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            NSColor.black.withAlphaComponent(baseAlpha[index]).setFill()
            path.fill()
        }
    }

    private static func drawActivityBadge(
        type: WorkflowType,
        systemName: String,
        in bounds: CGRect,
        frame: Int,
        phase: ActivityPhase
    ) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgeOpacity: CGFloat
        let haloOpacity: CGFloat

        switch phase {
        case .recording:
            let values: [CGFloat]
            switch type {
            case .transcription, .localTranscription:
                values = [0.74, 1.0, 0.82, 0.92]
            case .textImprover:
                values = [0.66, 0.84, 1.0, 0.8]
            case .dampfAblassen:
                values = [1.0, 0.76, 0.94, 0.68]
            case .emojiText, .translate, .summarize, .format:
                values = [0.8, 0.92, 0.7, 1.0]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.14 + (CGFloat(frame % 4) * 0.04)
        case .processing:
            let values: [CGFloat]
            switch type {
            case .transcription, .localTranscription:
                values = [0.58, 0.72, 0.9, 0.72]
            case .textImprover:
                values = [0.48, 0.68, 0.92, 0.84]
            case .dampfAblassen:
                values = [0.84, 0.62, 0.9, 0.56]
            case .emojiText, .translate, .summarize, .format:
                values = [0.54, 0.76, 0.88, 0.68]
            }
            badgeOpacity = values[frame % values.count]
            haloOpacity = 0.12 + (CGFloat((frame + 2) % 4) * 0.03)
        }

        let haloInset = phase == .recording ? -0.8 : -0.45
        let haloRect = badgeRect.insetBy(dx: haloInset, dy: haloInset)
        let haloPath = NSBezierPath(ovalIn: haloRect)
        NSColor.black.withAlphaComponent(haloOpacity).setStroke()
        haloPath.lineWidth = phase == .recording ? 0.9 : 0.75
        haloPath.stroke()

        drawBadge(systemName: systemName, in: bounds, fillOpacity: badgeOpacity)

        if phase == .processing {
            drawProcessingDot(around: badgeRect, frame: frame)
        }
    }

    private static func drawBadge(systemName: String, in bounds: CGRect, fillOpacity: CGFloat) {
        let badgeSize: CGFloat = 7.5
        let badgeRect = CGRect(
            x: bounds.maxX - badgeSize - 0.8,
            y: bounds.minY + 0.8,
            width: badgeSize,
            height: badgeSize
        )

        let badgePath = NSBezierPath(ovalIn: badgeRect)
        NSColor.black.withAlphaComponent(fillOpacity).setFill()
        badgePath.fill()

        guard let symbol = NSImage(
            systemSymbolName: systemName,
            accessibilityDescription: nil
        ) else {
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 5.5, weight: .bold)
        let configuredSymbol = symbol.withSymbolConfiguration(config) ?? symbol
        let symbolRect = badgeRect.insetBy(dx: 1.2, dy: 1.2)
        configuredSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .destinationOut,
            fraction: 1.0
        )
    }

    private static func drawProcessingDot(around badgeRect: CGRect, frame: Int) {
        let orbitPoints: [CGPoint] = [
            CGPoint(x: badgeRect.midX, y: badgeRect.maxY + 0.35),
            CGPoint(x: badgeRect.maxX + 0.35, y: badgeRect.midY),
            CGPoint(x: badgeRect.midX, y: badgeRect.minY - 0.35),
            CGPoint(x: badgeRect.minX - 0.35, y: badgeRect.midY),
        ]
        let point = orbitPoints[frame % orbitPoints.count]
        let dotRect = CGRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7)
        let dotPath = NSBezierPath(ovalIn: dotRect)
        NSColor.black.withAlphaComponent(0.92).setFill()
        dotPath.fill()
    }

    private static func baseAlphaValues(for status: MenuBarStatus, frame: Int) -> [CGFloat] {
        switch status {
        case .idle:
            return [1.0, 0.82, 0.64, 0.46]
        case .recording(let type):
            return recordingAlphaValues(for: type, frame: frame)
        case .processing(let type):
            return processingAlphaValues(for: type, frame: frame)
        case .success:
            return [1.0, 0.9, 0.78, 0.62]
        case .error:
            return [1.0, 0.7, 0.52, 0.36]
        }
    }

    private static func recordingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .transcription, .localTranscription:
            let patterns: [[CGFloat]] = [
                [1.0, 0.42, 0.28, 0.18],
                [0.82, 1.0, 0.4, 0.24],
                [0.58, 0.86, 1.0, 0.36],
                [0.4, 0.62, 0.88, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .textImprover:
            let patterns: [[CGFloat]] = [
                [1.0, 0.88, 0.52, 0.3],
                [0.86, 1.0, 0.84, 0.44],
                [0.64, 0.9, 1.0, 0.68],
                [0.48, 0.68, 0.9, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .dampfAblassen:
            let patterns: [[CGFloat]] = [
                [1.0, 0.44, 0.78, 1.0],
                [0.86, 0.34, 0.96, 0.9],
                [0.72, 0.3, 1.0, 0.78],
                [0.94, 0.4, 0.74, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .emojiText, .translate, .summarize, .format:
            let patterns: [[CGFloat]] = [
                [1.0, 0.7, 0.46, 0.28],
                [0.78, 1.0, 0.72, 0.42],
                [0.52, 0.82, 1.0, 0.66],
                [0.36, 0.58, 0.84, 1.0],
            ]
            return patterns[frame % patterns.count]
        }
    }

    private static func processingAlphaValues(for type: WorkflowType, frame: Int) -> [CGFloat] {
        switch type {
        case .transcription, .localTranscription:
            let patterns: [[CGFloat]] = [
                [1.0, 0.84, 0.68, 0.52],
                [0.92, 0.8, 0.64, 0.5],
                [0.84, 0.74, 0.6, 0.48],
                [0.92, 0.8, 0.64, 0.5],
            ]
            return patterns[frame % patterns.count]
        case .textImprover:
            let patterns: [[CGFloat]] = [
                [1.0, 0.76, 0.52, 0.34],
                [0.86, 1.0, 0.74, 0.48],
                [0.7, 0.88, 1.0, 0.72],
                [0.56, 0.74, 0.9, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .dampfAblassen:
            let patterns: [[CGFloat]] = [
                [0.9, 0.5, 0.72, 1.0],
                [0.78, 0.44, 0.9, 1.0],
                [0.66, 0.38, 1.0, 0.88],
                [0.84, 0.48, 0.78, 1.0],
            ]
            return patterns[frame % patterns.count]
        case .emojiText, .translate, .summarize, .format:
            let patterns: [[CGFloat]] = [
                [1.0, 0.8, 0.58, 0.4],
                [0.88, 1.0, 0.78, 0.54],
                [0.74, 0.9, 1.0, 0.7],
                [0.6, 0.76, 0.92, 1.0],
            ]
            return patterns[frame % patterns.count]
        }
    }

    private static func badgeSymbol(for type: WorkflowType) -> String {
        switch type {
        case .transcription:
            return "mic.fill"
        case .localTranscription:
            return "lock.shield.fill"
        case .textImprover:
            return "text.alignleft"
        case .dampfAblassen:
            return "flame.fill"
        case .emojiText:
            return "face.smiling"
        case .translate:
            return "globe"
        case .summarize:
            return "doc.plaintext"
        case .format:
            return "list.bullet"
        }
    }

    private static func baseTemplateImage() -> NSImage? {
        guard let image = NSImage(named: "menubar_icon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

// MARK: - Modern Ring Icon (Theme "Modern")

private enum MenuBarRingIcon {
    struct Rendered {
        let image: NSImage
        let isTemplate: Bool
    }

    private static let size = NSSize(width: 18, height: 18)
    private static let recordingYellow = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
    private static let successGreen = NSColor(srgbRed: 0.30, green: 0.78, blue: 0.36, alpha: 1.0)
    private static let errorOrange = NSColor(srgbRed: 1.0, green: 0.46, blue: 0.20, alpha: 1.0)

    static func makeImage(for status: MenuBarStatus, phase: Double) -> Rendered {
        switch status {
        case .idle:
            // Monochromer Template-Ring — passt sich hell/dunkel an.
            return Rendered(image: ring(color: .black, alpha: 1.0), isTemplate: true)
        case .processing:
            let alpha = 0.55 + 0.45 * pulse(phase, period: 1.4)
            return Rendered(image: ring(color: .black, alpha: alpha), isTemplate: true)
        case .recording:
            let alpha = 0.45 + 0.55 * pulse(phase, period: 1.0)
            let image = ring(color: recordingYellow, alpha: alpha, haloAlpha: alpha * 0.45)
            return Rendered(image: image, isTemplate: false)
        case .success:
            return Rendered(image: ring(color: successGreen, alpha: 1.0), isTemplate: false)
        case .error:
            return Rendered(image: ring(color: errorOrange, alpha: 1.0), isTemplate: false)
        }
    }

    /// Weicher 0...1 Sinus-Puls.
    private static func pulse(_ phase: Double, period: Double) -> Double {
        let x = sin((phase / period) * 2 * .pi)
        return (x + 1) / 2
    }

    private static func ring(color: NSColor, alpha: CGFloat, haloAlpha: CGFloat = 0) -> NSImage {
        let image = NSImage(size: size, flipped: false) { bounds in
            let inset: CGFloat = 3.4
            let lineWidth: CGFloat = 1.7
            let rect = bounds.insetBy(dx: inset, dy: inset)

            if haloAlpha > 0 {
                let haloRect = rect.insetBy(dx: -1.4, dy: -1.4)
                let haloPath = NSBezierPath(ovalIn: haloRect)
                color.withAlphaComponent(haloAlpha).setStroke()
                haloPath.lineWidth = 2.2
                haloPath.stroke()
            }

            let path = NSBezierPath(ovalIn: rect)
            color.withAlphaComponent(alpha).setStroke()
            path.lineWidth = lineWidth
            path.stroke()
            return true
        }
        image.size = size
        return image
    }
}
