import AppKit
import SwiftUI

struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let text: String
    let seconds: Double
}

/// Every dictation, newest first, in ~/Library/Application Support/Yap/history.jsonl.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Yap", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // History recorded under the app's first name, Dictate.
            try? FileManager.default.moveItem(at: support.appendingPathComponent("Dictate/history.jsonl"), to: fileURL)
        }
        if let data = try? Data(contentsOf: fileURL) {
            entries = Array(data.split(separator: 0x0A).compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }.reversed())
        }
    }

    func add(_ text: String, seconds: Double) {
        let entry = HistoryEntry(id: UUID(), date: Date(), text: text, seconds: seconds)
        entries.insert(entry, at: 0)
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        var data = Data()
        for item in entries.reversed() {
            guard let line = try? encoder.encode(item) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Screen state lives here: the Command Line Tools ship no SwiftUI macro plugin for @State.
@MainActor
final class HistoryScreen: ObservableObject {
    @Published var query = ""
    @Published var copied: UUID?
}

struct HistoryView: View {
    @ObservedObject var store = HistoryStore.shared
    @ObservedObject var screen: HistoryScreen

    private var query: String { screen.query }
    private var copied: UUID? { screen.copied }

    private var shown: [HistoryEntry] {
        query.isEmpty ? store.entries : store.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(ui("Search dictations", ru: "Поиск по истории"), text: $screen.query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            if shown.isEmpty {
                Spacer()
                Text(store.entries.isEmpty ? ui("No dictations yet", ru: "Записей пока нет")
                                           : ui("Nothing found", ru: "Ничего не нашлось")).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(shown) { entry in row(entry) }
                    .listStyle(.inset)
            }
        }
        .frame(minWidth: 440, minHeight: 360)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                Text(entry.text).lineLimit(5)
            }
            Spacer(minLength: 8)
            Text(copied == entry.id ? ui("Copied", ru: "Скопировано") : ui("Copy", ru: "Копировать"))
                .font(.caption.weight(.medium))
                .foregroundStyle(copied == entry.id ? Color.green : Color.accentColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copy(entry) }
        .contextMenu { Button(ui("Delete", ru: "Удалить")) { store.delete(entry) } }
    }

    /// Copies, then hides the window so focus returns to the app where ⌘V goes.
    private func copy(_ entry: HistoryEntry) {
        Clipboard.copy(entry.text)
        screen.copied = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.hide(nil) }
    }
}

@MainActor
final class HistoryWindow {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = ui("Dictations", ru: "История диктовок")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(screen: HistoryScreen()))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
