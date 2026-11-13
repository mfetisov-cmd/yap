import Foundation
import FluidAudio

/// Where the speech model stands. The first launch downloads it, about 600 MB, so the menu says so,
/// and a dictation started before it arrives says so instead of waiting minutes for it.
@MainActor
enum ModelStatus {
    enum State: Equatable {
        case loading
        case downloading
        case ready
        case failed
    }

    static var onChange: (_ old: State, _ new: State) -> Void = { _, _ in }

    static var state: State = .loading {
        didSet { if state != oldValue { onChange(oldValue, state) } }
    }
}

/// Parakeet Ultra through FluidAudio: loads once, then stays in memory.
actor Transcriber {
    private var manager: AsrManager?
    private var loading: Task<AsrManager, Error>?

    @discardableResult
    func prepare() async throws -> AsrManager {
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task { () throws -> AsrManager in
            await MainActor.run { ModelStatus.state = .loading }
            Transcriber.reuseSpokenlyModel()
            let models = try await AsrModels.downloadAndLoad(version: .ultra, progressHandler: { progress in
                // A model already on disk reports a finished download of zero files; only a real one counts,
                // and it stays "downloading" through the compile steps between files until the model is ready.
                let downloading: Bool
                switch progress.phase {
                case .listing: downloading = true
                case .downloading(_, let totalFiles): downloading = totalFiles > 0
                case .compiling: downloading = false
                }
                // A main-actor task, not assumeIsolated on the main queue: the --transcribe check runs under
                // dispatchMain(), where main-queue blocks leave the main thread and that assumption crashes.
                if downloading { Task { @MainActor in ModelStatus.state = .downloading } }
            })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loading = task
        defer { loading = nil }
        do {
            let ready = try await task.value
            manager = ready
            await MainActor.run { ModelStatus.state = .ready }
            return ready
        } catch {
            yapLog.error("speech model not loaded: \(String(describing: error), privacy: .public)")
            await MainActor.run { ModelStatus.state = .failed }
            throw error
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        let manager = try await prepare()
        // The model refuses clips under a second: pad a short «да» with silence.
        let padded = samples.count < 16_000 ? samples + [Float](repeating: 0, count: 16_000 - samples.count) : samples
        var state = try TdtDecoderState()
        let result = try await manager.transcribe(padded, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Spokenly keeps the same model under another folder name. An APFS clone takes no extra disk space.
    nonisolated static func reuseSpokenlyModel() {
        let target = AsrModels.defaultCacheDirectory(for: .ultra)
        let spokenly = target.deletingLastPathComponent().appendingPathComponent("parakeet-ultra")
        let files = FileManager.default
        guard !files.fileExists(atPath: target.path), files.fileExists(atPath: spokenly.path) else { return }
        try? files.copyItem(at: spokenly, to: target)
    }
}
