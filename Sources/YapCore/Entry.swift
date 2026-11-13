import AppKit
import ApplicationServices
import FluidAudio

/// Called by the launcher.
/// Debug modes: --transcribe <audio file>, --render <dir> (pill previews), --icon <png>, --chime <wav>, --hotkeys,
/// --mic <seconds> (records from the microphone Yap picks; run it as `open -n` so it gets Yap's microphone access),
/// --pill-idle (shows and hides the pill, then measures the processor use while it is hidden),
/// --menubar (where every menu-bar icon sits; needs Yap's Accessibility grant, so run it as `open -n`).
@_cdecl("yap_run")
public func yapRun() {
    let arguments = CommandLine.arguments

    if let index = arguments.firstIndex(of: "--transcribe"), index + 1 < arguments.count {
        let url = URL(fileURLWithPath: arguments[index + 1])
        MainActor.assumeIsolated {
            ModelStatus.onChange = { old, new in print("model: \(old) → \(new)") }
        }
        Task.detached {
            do {
                let started = Date()
                let transcriber = Transcriber()
                try await transcriber.prepare()
                let loaded = Date()
                let samples = try AudioConverter().resampleAudioFile(url)
                let text = try await transcriber.transcribe(samples)
                print(String(format: "model %.1fs, transcription %.2fs for %.1fs of audio",
                             loaded.timeIntervalSince(started), Date().timeIntervalSince(loaded), Double(samples.count) / 16_000))
                print("TEXT: \(text)")
                exit(0)
            } catch {
                print("ERROR: \(error)")
                exit(1)
            }
        }
        dispatchMain()
    }

    if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
        MainActor.assumeIsolated { PillPreview.render(to: URL(fileURLWithPath: arguments[index + 1])) }
        exit(0)
    }

    if let index = arguments.firstIndex(of: "--icon"), index + 1 < arguments.count {
        MainActor.assumeIsolated { AppIconRenderer.render(to: URL(fileURLWithPath: arguments[index + 1])) }
        exit(0)
    }

    if let index = arguments.firstIndex(of: "--chime"), index + 1 < arguments.count {
        MainActor.assumeIsolated { try? Chime.wav(Chime.startNotes).write(to: URL(fileURLWithPath: arguments[index + 1])) }
        exit(0)
    }

    if let index = arguments.firstIndex(of: "--mic"), index + 1 < arguments.count, let seconds = Double(arguments[index + 1]) {
        let recorder = Recorder()
        var peak: Float = 0
        var firstSound: Date?
        recorder.onLevel = { level in
            if firstSound == nil { firstSound = Date() }
            peak = max(peak, level)
        }
        // Two rounds: the first one also opens the microphone, the second is every later dictation.
        func record(round: Int) {
            peak = 0
            firstSound = nil
            let started = Date()
            do {
                try recorder.start()
            } catch {
                print("ERROR: \(error)")
                exit(1)
            }
            let returned = Date().timeIntervalSince(started)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                let stopping = Date()
                let samples = recorder.stop()
                print(String(format: "round %d: start returned in %.3fs, first sound after %.2fs, stop took %.3fs, recorded %.2fs, peak level %.2f",
                             round, returned, firstSound.map { $0.timeIntervalSince(started) } ?? -1, Date().timeIntervalSince(stopping),
                             Double(samples.count) / 16_000, peak))
                if round == 2 { exit(0) }
                record(round: 2)
            }
        }
        record(round: 1)
        dispatchMain()
    }

    if arguments.contains("--pill-idle") {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let pill = PillController()
            pill.flash(.hint("Yap check"), seconds: 0.8)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let start = clock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withExtendedLifetime(pill) {
                        print(String(format: "hidden pill: %.1f%% of a core", Double(clock() - start) / Double(CLOCKS_PER_SEC) / 3 * 100))
                    }
                    exit(0)
                }
            }
            app.run()
        }
    }

    if arguments.contains("--menubar") {
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            AXUIElementCopyAttributeValue(element, name as CFString, &result)
            return result
        }
        var rows: [(x: CGFloat, line: String)] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bar = value(AXUIElementCreateApplication(app.processIdentifier), "AXExtrasMenuBar"),
                  let items = value(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement] else { continue }
            for item in items {
                var origin = CGPoint.zero
                var size = CGSize.zero
                if let raw = value(item, kAXPositionAttribute as String) { AXValueGetValue(raw as! AXValue, .cgPoint, &origin) }
                if let raw = value(item, kAXSizeAttribute as String) { AXValueGetValue(raw as! AXValue, .cgSize, &size) }
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
                    .compactMap { value(item, $0 as String) as? String }.filter { !$0.isEmpty }.joined(separator: " | ")
                rows.append((origin.x, "x=\(Int(origin.x)) y=\(Int(origin.y)) width=\(Int(size.width)) \(app.localizedName ?? "?"): \(label)"))
            }
        }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bar = value(AXUIElementCreateApplication(app.processIdentifier), kAXMenuBarAttribute as String),
                  let menus = value(bar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement] else { continue }
            var right: CGFloat = 0
            for menu in menus {
                var origin = CGPoint.zero
                var size = CGSize.zero
                if let raw = value(menu, kAXPositionAttribute as String) { AXValueGetValue(raw as! AXValue, .cgPoint, &origin) }
                if let raw = value(menu, kAXSizeAttribute as String) { AXValueGetValue(raw as! AXValue, .cgSize, &size) }
                right = max(right, origin.x + size.width)
            }
            print("menus of \(app.localizedName ?? "?")\(app.isActive ? " (in front)" : ""): \(menus.count), reach x=\(Int(right))")
        }
        print("Accessibility: \(AXIsProcessTrusted()), icons: \(rows.count)")
        rows.sorted { $0.x < $1.x }.forEach { print($0.line) }
        for screen in NSScreen.screens {
            let notch = screen.auxiliaryTopLeftArea.map { left in
                ", notch from x=\(Int(left.maxX)) to x=\(Int(screen.auxiliaryTopRightArea?.minX ?? left.maxX))"
            } ?? ""
            print("screen \(screen.localizedName), width \(Int(screen.frame.width))\(notch)")
        }
        exit(0)
    }

    if arguments.contains("--mbtree") {
        // The menu-bar process's own view of the bar on the current desktop: every element it exposes, with its frame.
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var result: CFTypeRef?
            AXUIElementCopyAttributeValue(element, name as CFString, &result)
            return result
        }
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 7 else { return }
            var origin = CGPoint.zero
            var size = CGSize.zero
            if let raw = value(element, kAXPositionAttribute as String) { AXValueGetValue(raw as! AXValue, .cgPoint, &origin) }
            if let raw = value(element, kAXSizeAttribute as String) { AXValueGetValue(raw as! AXValue, .cgSize, &size) }
            let label = [kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXHelpAttribute]
                .compactMap { value(element, $0 as String) as? String }.filter { !$0.isEmpty }.joined(separator: " | ")
            print(String(repeating: "  ", count: depth) + "x=\(Int(origin.x)) y=\(Int(origin.y)) w=\(Int(size.width)) h=\(Int(size.height)) \(label)")
            for child in (value(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] { walk(child, depth + 1) }
        }
        print("front: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"), Accessibility: \(AXIsProcessTrusted())")
        for app in NSWorkspace.shared.runningApplications where ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"].contains(app.bundleIdentifier ?? "") {
            print("== \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier)")
            walk(AXUIElementCreateApplication(app.processIdentifier), 0)
        }
        exit(0)
    }

    if arguments.contains("--hotkeys") {
        MainActor.assumeIsolated { HotKeyCenter.selfTest() }
        exit(0)
    }

    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
