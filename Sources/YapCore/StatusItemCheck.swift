import AppKit
import notify

/// Records what every copy of the menu-bar icon holds.
///
/// macOS 27 gives each desktop (and each app in full screen) its own menu bar. The icon's real button sits in one of
/// them; the others show copies that Yap draws separately. Several times the icon vanished from some desktops while
/// Yap kept running and the system still kept a slot for it. Each line here says how many pixels the real button and
/// each copy paint, so the moment a copy goes blank is on record.
///
/// File: ~/Library/Caches/Yap/statusitem.log. A line on demand: `notifyutil -p local.yap.debug.statusitem`.
@MainActor
final class StatusItemCheck: NSObject {
    private weak var item: NSStatusItem?
    private var token: Int32 = 0
    private var lastDesktopLine = Date.distantPast
    private let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/Yap/statusitem.log")

    func watch(_ item: NSStatusItem) { self.item = item }

    func start() {
        notify_register_dispatch("local.yap.debug.statusitem", &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("asked") }
        }
        Timer.scheduledTimer(timeInterval: 600, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(desktopChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(themeChanged), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func tick() { record("every 10 min") }

    /// The desktop notification can fire every few seconds; one line per 30 s is enough.
    @objc private func desktopChanged() {
        guard Date().timeIntervalSince(lastDesktopLine) > 30 else { return }
        lastDesktopLine = Date()
        later(2, "desktop changed")
    }

    @objc private func woke() { later(5, "woke") }
    @objc private func themeChanged() { later(3, "theme changed") }
    @objc private func screensChanged() { later(3, "screens changed") }

    func later(_ seconds: Double, _ reason: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.record(reason) }
    }

    func record(_ reason: String) {
        var parts: [String] = []
        for window in NSApp.windows where String(describing: type(of: window)) == "NSStatusBarWindow" {
            let real = window === item?.button?.window
            parts.append("\(real ? "real" : "copy") \(Self.painted(window))px")
        }
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        append("\(Self.stamp()) \(reason) | front \(front) | \(parts.isEmpty ? "no icon windows" : parts.joined(separator: ", "))\n")
    }

    /// Pixels the window's content paints when drawn offscreen; a blank copy paints 0.
    private static func painted(_ window: NSWindow) -> Int {
        guard let view = window.contentView, view.bounds.width > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return -1 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var count = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { count += 1 }
        }
        return count
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func append(_ line: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? manager.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 2_000_000 {
            try? manager.removeItem(at: file)
        }
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
