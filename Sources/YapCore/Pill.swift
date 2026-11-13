import AppKit
import SwiftUI

enum PillLayout {
    static let height: CGFloat = 28
    static let compactWidth: CGFloat = 108
    static let glowRoom: CGFloat = 16
    /// Wide enough for the longest notice; the capsule sits in the middle, the rest is transparent.
    static let windowSize = NSSize(width: 300, height: height + glowRoom * 2)
}

enum Palette {
    static let red = Color(red: 1.0, green: 0.3, blue: 0.38)
    static let pink = Color(red: 1.0, green: 0.42, blue: 0.68)
    static let violet = Color(red: 0.55, green: 0.38, blue: 1.0)
    static let blue = Color(red: 0.28, green: 0.56, blue: 1.0)
    static let green = Color(red: 0.16, green: 0.72, blue: 0.42)
    static let orange = Color(red: 0.96, green: 0.56, blue: 0.12)
    static let ink = Color.black.opacity(0.75)
    static let bars = LinearGradient(colors: [pink, violet, blue], startPoint: .top, endPoint: .bottom)

    static func tint(_ phase: PillModel.Phase) -> Color {
        switch phase {
        case .recording: return pink
        case .transcribing: return blue
        case .done: return green
        case .notice: return orange
        case .hint: return violet
        case .download: return blue
        }
    }

    static func border(_ phase: PillModel.Phase) -> Gradient {
        switch phase {
        case .recording: return Gradient(colors: [pink, violet, blue, .clear, .clear, pink])
        case .transcribing: return Gradient(colors: [blue, violet, .clear, .clear, blue])
        default:
            let color = tint(phase)
            return Gradient(colors: [color.opacity(0.7), color.opacity(0.2), color.opacity(0.7)])
        }
    }
}

@MainActor
final class PillModel: ObservableObject {
    enum Phase: Equatable {
        case recording
        case transcribing
        case done(String)
        case notice(String)
        case hint(String)
        case download(String)
    }

    static let barCount = 16

    @Published var phase: Phase = .recording
    /// The animation runs only while the pill is on screen: hidden, it kept redrawing its border and took 15–20% of a core.
    @Published var isShown = false
    @Published var levels = [CGFloat](repeating: 0, count: PillModel.barCount)
    weak var window: NSWindow?

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    var loudness: CGFloat { levels.suffix(4).reduce(0, +) / 4 }

    func push(level: Float) {
        levels.removeFirst()
        levels.append(CGFloat(level))
    }

    func resetLevels() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
    }

    func drag() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, window.frame.origin) }
        guard let start = dragStart else { return }
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    func endDrag() {
        if let window { PillPosition.save(window.frame.origin) }
        dragStart = nil
    }
}

/// A small light glass capsule: red dot and waveform while recording, a flowing wave while recognising.
struct PillView: View {
    @ObservedObject var model: PillModel
    var preview = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !model.isShown && !preview)) { timeline in
            pill(t: timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: PillLayout.windowSize.width, height: PillLayout.windowSize.height)
    }

    private var compact: Bool { model.phase == .recording || model.phase == .transcribing }

    private func pill(t: Double) -> some View {
        content(t: t)
            .padding(.horizontal, 11)
            .frame(width: compact ? PillLayout.compactWidth : nil, height: PillLayout.height)
            .background(background(t: t))
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { _ in model.drag() }
                .onEnded { _ in model.endDrag() })
    }

    @ViewBuilder
    private func content(t: Double) -> some View {
        switch model.phase {
        case .recording:
            let pulse = 1 + 0.12 * sin(t * 5) + 0.4 * Double(model.loudness)
            HStack(spacing: 7) {
                ZStack {
                    Circle().fill(Palette.red.opacity(0.22)).frame(width: 12, height: 12).scaleEffect(pulse)
                    Circle().fill(Palette.red).frame(width: 6.5, height: 6.5)
                }
                .frame(width: 14, height: 14)
                Waveform(levels: model.levels)
            }
        case .transcribing:
            HStack(spacing: 7) {
                Circle().fill(Palette.violet).frame(width: 6.5, height: 6.5)
                    .opacity(0.45 + 0.45 * sin(t * 9))
                    .frame(width: 14, height: 14)
                Shimmer(t: t)
            }
        case .done(let text), .notice(let text), .hint(let text), .download(let text):
            HStack(spacing: 6) {
                Image(systemName: Self.symbol(model.phase))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tint(model.phase))
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
            }
        }
    }

    private func background(t: Double) -> some View {
        let speed: Double = model.phase == .transcribing ? 240 : 90
        let angle = Angle.degrees((t * speed).truncatingRemainder(dividingBy: 360))
        let loud: Double = model.phase == .recording ? Double(model.loudness) : 0.3
        return ZStack {
            if preview {
                Capsule().fill(Color.white.opacity(0.6))
            } else {
                Frost()
            }
            Capsule().fill(Color.white.opacity(0.18))
        }
        .overlay(Capsule().strokeBorder(AngularGradient(gradient: Palette.border(model.phase), center: .center, angle: angle), lineWidth: 1))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 5, y: 1.5)
        .shadow(color: Palette.tint(model.phase).opacity(0.15 + 0.35 * loud), radius: 5 + 8 * loud)
    }

    private static func symbol(_ phase: PillModel.Phase) -> String {
        switch phase {
        case .notice: return "exclamationmark.circle.fill"
        case .hint: return "hand.draw.fill"
        case .download: return "arrow.down.circle.fill"
        default: return "checkmark.circle.fill"
        }
    }
}

struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Palette.bars)
                    .frame(width: 2.5, height: 3 + min(levels[index], 1) * 13)
                    .opacity(0.35 + 0.65 * Double(index + 1) / Double(levels.count))
            }
        }
        .frame(height: 18)
        .animation(.interpolatingSpring(stiffness: 280, damping: 24), value: levels)
    }
}

struct Shimmer: View {
    let t: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<PillModel.barCount, id: \.self) { index in
                Capsule()
                    .fill(Palette.bars)
                    .frame(width: 2.5, height: 3 + 9 * (0.5 + 0.5 * sin(t * 7 - Double(index) * 0.6)))
            }
        }
        .frame(height: 18)
    }
}

/// Light frosted glass that blurs whatever is behind the pill.
struct Frost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        view.maskImage = Self.capsuleMask
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private static let capsuleMask: NSImage = {
        let side = PillLayout.height
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: side / 2, left: side / 2, bottom: side / 2, right: side / 2)
        image.resizingMode = .stretch
        return image
    }()
}

/// Never takes focus, so ⌘V still lands in the app the user is typing in.
final class PillPanel: NSPanel {
    init(model: PillModel) {
        super.init(contentRect: NSRect(origin: .zero, size: PillLayout.windowSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Opens in the space in front, full-screen apps included. With «all spaces» the pill stayed tied to the desktop
        // once full-screen spaces came and went, so over Claude, Slack and Chrome in full screen it never showed (05–10.11).
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        contentView = FirstClickHostingView(rootView: PillView(model: model).environment(\.colorScheme, .light))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
enum PillPosition {
    private static let key = "pillOrigin"

    static func origin(for size: NSSize) -> NSPoint {
        if let saved = UserDefaults.standard.array(forKey: key) as? [Double], saved.count == 2 {
            let point = NSPoint(x: saved[0], y: saved[1])
            let visiblePart = NSRect(origin: point, size: size).insetBy(dx: PillLayout.glowRoom, dy: PillLayout.glowRoom)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(visiblePart) }) { return point }
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 40)
    }

    static func save(_ origin: NSPoint) {
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: key)
    }
}

@MainActor
final class PillController {
    let model = PillModel()
    private lazy var panel: PillPanel = {
        let panel = PillPanel(model: model)
        model.window = panel
        return panel
    }()
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringToActiveSpace() }
        }
    }

    func showRecording() {
        model.resetLevels()
        model.phase = .recording
        present()
    }

    func showTranscribing() {
        model.phase = .transcribing
        present()
    }

    func flash(_ phase: PillModel.Phase, seconds: Double = 1.2) {
        model.phase = phase
        present()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard panel.isVisible else { return }
        let token = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                self.panel.orderOut(nil)
                self.model.isShown = false
            }
        })
    }

    private func present() {
        hideWork?.cancel()
        generation += 1
        model.isShown = true
        if !panel.isVisible {
            panel.setFrameOrigin(PillPosition.origin(for: panel.frame.size))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        } else {
            bringToActiveSpace()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        yapLog.notice("pill shown, on the space in front: \(self.panel.isOnActiveSpace)")
    }

    /// A pill already up moves to the space in front: after a swipe mid-recording, or when it was left on another space.
    private func bringToActiveSpace() {
        guard model.isShown, panel.isVisible, !panel.isOnActiveSpace else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}

/// Renders every state to PNG for a visual check without touching the screen.
@MainActor
enum PillPreview {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let wave = (0..<PillModel.barCount).map { index in
            CGFloat(0.12 + 0.8 * abs(sin(Double(index) * 0.7)) * Double(index + 2) / Double(PillModel.barCount))
        }
        let phases: [(String, PillModel.Phase)] = [
            ("recording", .recording), ("transcribing", .transcribing),
            ("copied", .done(Phrase.copied)), ("notice", .notice(ui("Heard nothing", ru: "Ничего не услышал"))),
            ("download", .download(ui("Downloading the model: 42%", ru: "Скачиваю модель: 42%"))),
            ("ready", .done(ui("Ready: tap right ⌥ and speak", ru: "Готово: нажми правый ⌥ и говори"))),
        ]
        let desktop = LinearGradient(colors: [Color(red: 0.2, green: 0.35, blue: 0.6), Color(red: 0.85, green: 0.6, blue: 0.45)],
                                     startPoint: .leading, endPoint: .trailing)
        for (name, phase) in phases {
            let model = PillModel()
            model.phase = phase
            model.levels = wave
            let view = PillView(model: model, preview: true).environment(\.colorScheme, .light).background(desktop)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            try? png?.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
