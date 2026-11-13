import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let dictation = DictationController()
    private let iconCheck = StatusItemCheck()
    private var statusItem: NSStatusItem?
    private var menuIsOpen = false
    private var rebuildAfterMenu = false
    private var pendingRebuild: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        dictation.onRecordingChange = { [weak self] recording in
            self?.statusItem?.button?.contentTintColor = recording ? .systemRed : nil
        }
        addStatusItem()
        iconCheck.start()
        iconCheck.later(5, "launch")
        dictation.setup()
    }

    /// Opening Yap again while it runs brings the icon back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        yapLog.notice("opened again by the user")
        iconCheck.record("opened again, before redraw")
        addStatusItem()
        iconCheck.later(3, "opened again, after redraw")
        dictation.pill.flash(.hint(ui("Yap is running", ru: "Yap работает")), seconds: 1.6)
        return false
    }

    @objc private func menuBarChanged(_ notification: Notification) {
        yapLog.notice("menu bar changed (\(notification.name.rawValue, privacy: .public)), new icon in 3 s")
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.menuIsOpen { self.rebuildAfterMenu = true } else { self.addStatusItem() }
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func addStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "yap"
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Yap")
        item.button?.contentTintColor = dictation.isRecording ? .systemRed : nil
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        iconCheck.watch(item)
        yapLog.notice("menu-bar icon drawn anew")
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        guard rebuildAfterMenu else { return }
        rebuildAfterMenu = false
        DispatchQueue.main.async { self.addStatusItem() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let line = Self.modelLine() {
            // Only a failed load is clickable: it tries again.
            let item = NSMenuItem(title: line, action: ModelStatus.state == .failed ? #selector(retryModel) : nil, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }
        add(menu, dictation.isRecording ? ui("Stop recording", ru: "Закончить запись")
                                        : ui("Start recording (right ⌥)", ru: "Начать запись (правый ⌥)"), #selector(toggleRecording))
        menu.addItem(.separator())
        let recent = HistoryStore.shared.entries.prefix(8)
        let header = NSMenuItem(title: recent.isEmpty ? ui("No dictations yet", ru: "Записей пока нет")
                                                      : ui("Click one to copy it:", ru: "Нажми, чтобы скопировать:"),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for entry in recent {
            let item = NSMenuItem(title: Self.preview(entry.text), action: #selector(copyEntry(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.text
            item.toolTip = entry.text
            menu.addItem(item)
        }
        add(menu, ui("All dictations…", ru: "Вся история…"), #selector(openHistory))
        menu.addItem(.separator())
        add(menu, ui("Move the indicator", ru: "Передвинуть плашку"), #selector(showPillForMoving))
        if !Paster.isTrusted { add(menu, ui("Allow right ⌥ and pasting…", ru: "Разрешить правый ⌥ и вставку…"), #selector(allowPasting)) }
        add(menu, ui("Open at login", ru: "Запускать при входе"), #selector(toggleLoginItem)).state =
            SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        add(menu, ui("Quit Yap", ru: "Выйти"), #selector(quit))
    }

    private static func modelLine() -> String? {
        switch ModelStatus.state {
        case .ready:
            return nil
        case .loading:
            return ui("Loading the speech model…", ru: "Загружаю модель распознавания…")
        case .downloading(let fraction):
            let percent = Int(fraction * 100)
            return ui("Downloading the speech model: \(percent)%", ru: "Скачиваю модель распознавания: \(percent)%")
        case .failed:
            return ui("The speech model did not load. Try again", ru: "Модель не загрузилась. Попробовать ещё раз")
        }
    }

    @objc private func retryModel() { dictation.prepareModel() }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            yapLog.error("login item change failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func preview(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    @objc private func toggleRecording() { dictation.toggle() }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        Clipboard.copy(text)
        dictation.pill.flash(.done(Phrase.copied), seconds: 1.6)
    }

    @objc private func openHistory() { HistoryWindow.shared.show() }

    @objc private func showPillForMoving() {
        dictation.pill.flash(.hint(ui("Drag it wherever you like", ru: "Перетащи плашку, куда удобно")), seconds: 6)
    }

    @objc private func allowPasting() {
        Paster.askForTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
