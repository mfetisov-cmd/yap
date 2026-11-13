import AppKit
import AVFoundation
import Carbon.HIToolbox

/// Right Option → record. Enter → paste and press Enter in the app (sends a chat message), like Spokenly.
/// Right Option again → paste only. Esc → drop the recording.
@MainActor
final class DictationController {
    let pill = PillController()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let trigger = RightOptionTap()
    private var sessionKeys: [UInt32] = []
    private(set) var isRecording = false
    private var isTranscribing = false
    private var announcedDownload = false
    private var startedAt = Date()
    var onRecordingChange: (Bool) -> Void = { _ in }

    func setup() {
        trigger.onTap = { [weak self] in self?.toggle() }
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.pill.model.push(level: level) }
        }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        if !Paster.isTrusted { Paster.askForTrust() }
        trigger.start()
        // First launch: say that the model is coming, then how to start once it is here.
        ModelStatus.onChange = { [weak self] old, new in
            guard let self, !self.isRecording, !self.isTranscribing else { return }
            if case .downloading = new, !self.announcedDownload {
                self.announcedDownload = true
                self.pill.flash(.download(ui("Downloading the speech model", ru: "Скачиваю модель распознавания")), seconds: 4)
            } else if new == .ready, self.announcedDownload {
                self.pill.flash(.done(ui("Ready: tap right ⌥ and speak", ru: "Готово: нажми правый ⌥ и говори")), seconds: 5)
            }
        }
        prepareModel()
    }

    func prepareModel() {
        Task { try? await transcriber.prepare() }
    }

    func toggle() {
        isRecording ? finish(submit: false) : start()
    }

    func start() {
        guard !isRecording, !isTranscribing else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .denied else {
            pill.flash(.notice(ui("No access to the microphone", ru: "Нет доступа к микрофону")), seconds: 2.5)
            return
        }
        if case .downloading(let fraction) = ModelStatus.state {
            let percent = Int(fraction * 100)
            pill.flash(.download(ui("Downloading the model: \(percent)%", ru: "Скачиваю модель: \(percent)%")), seconds: 2.5)
            return
        }
        Chime.playStart()
        do {
            try recorder.start()
        } catch {
            pill.flash(.notice(ui("The microphone did not start", ru: "Микрофон не запустился")), seconds: 2.5)
            return
        }
        isRecording = true
        startedAt = Date()
        onRecordingChange(true)
        pill.showRecording()
        let keys = HotKeyCenter.shared
        sessionKeys = [
            keys.register(keyCode: UInt32(kVK_Escape), modifiers: 0) { [weak self] in self?.cancel() },
            keys.register(keyCode: UInt32(kVK_Return), modifiers: 0) { [weak self] in self?.finish(submit: true) },
            keys.register(keyCode: UInt32(kVK_ANSI_KeypadEnter), modifiers: 0) { [weak self] in self?.finish(submit: true) },
        ].compactMap { $0 }
    }

    func cancel() {
        guard isRecording else { return }
        endSession()
        _ = recorder.stop()
        pill.hide()
    }

    func finish(submit: Bool) {
        guard isRecording else { return }
        endSession()
        let samples = recorder.stop()
        let seconds = Double(samples.count) / 16_000
        guard seconds >= 0.4 else {
            // Held a second or more and still no sound: the microphone gave nothing, not a slip of the finger.
            if Date().timeIntervalSince(startedAt) >= 1 {
                pill.flash(.notice(ui("The microphone recorded nothing", ru: "Микрофон не записал звук")), seconds: 2.5)
            } else {
                pill.hide()
            }
            return
        }
        isTranscribing = true
        pill.showTranscribing()
        Task {
            defer { self.isTranscribing = false }
            do {
                let text = try await self.transcriber.transcribe(samples)
                guard !text.isEmpty else {
                    self.pill.flash(.notice(ui("Heard nothing", ru: "Ничего не услышал")))
                    return
                }
                HistoryStore.shared.add(text, seconds: seconds)
                if Paster.paste(text) {
                    self.pill.hide()
                    if submit { Paster.pressReturn(after: 0.25) }
                } else {
                    self.pill.flash(.done(Phrase.copied), seconds: 2.2)
                }
            } catch {
                yapLog.error("transcription failed: \(String(describing: error), privacy: .public)")
                self.pill.flash(.notice(ui("Could not recognise the speech", ru: "Не получилось распознать")), seconds: 2.5)
            }
        }
    }

    private func endSession() {
        Chime.playStop()
        isRecording = false
        onRecordingChange(false)
        sessionKeys.forEach { HotKeyCenter.shared.unregister($0) }
        sessionKeys = []
    }
}
