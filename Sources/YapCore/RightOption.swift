import AppKit
import Carbon.HIToolbox

/// A tap of the right Option key on its own; holding it for a combo (⌥ + letter) does not count.
/// Watching keys in other apps needs the Accessibility permission, so it waits until macOS grants it.
@MainActor
final class RightOptionTap {
    var onTap: () -> Void = {}
    private var monitors: [Any] = []
    private var pressedAt: Date?
    private var combined = false
    private var waitTimer: Timer?
    private let rightOptionMask: UInt = 0x40  // NX_DEVICERALTKEYMASK

    func start() {
        guard AXIsProcessTrusted() else {
            waitTimer?.invalidate()
            waitTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard AXIsProcessTrusted() else { return }
                    self.waitTimer?.invalidate()
                    self.waitTimer = nil
                    self.install()
                }
            }
            return
        }
        install()
    }

    private func install() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { self.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { self.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            if pressedAt != nil { combined = true }
            return
        }
        guard event.keyCode == UInt16(kVK_RightOption) else {
            if pressedAt != nil { combined = true }
            return
        }
        if event.modifierFlags.rawValue & rightOptionMask != 0 {
            pressedAt = Date()
            combined = !event.modifierFlags.intersection([.command, .control, .shift]).isEmpty
        } else if let pressedAt {
            self.pressedAt = nil
            if !combined, Date().timeIntervalSince(pressedAt) < 0.8 { onTap() }
        }
    }
}
