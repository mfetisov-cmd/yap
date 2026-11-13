import AVFoundation
import CoreAudio
import IOKit

/// Records 16 kHz mono samples and reports loudness for the waveform.
/// Opens only the microphone it picks: the Mac's own while the lid is open (Spokenly's order here), otherwise the
/// input chosen in System Settings. An audio engine opens the default input first, and with AirPods connected that
/// switched them into call mode on every dictation: a second and a half of lag and a lost start sound.
final class Recorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Failure: Error { case noInput }

    var onLevel: ((Float) -> Void)?
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "local.yap.recorder.session")
    private let dataQueue = DispatchQueue(label: "local.yap.recorder.data")
    private var device: AVCaptureDevice?
    private var samples: [Float] = []
    private let lock = NSLock()

    override init() {
        super.init()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        output.setSampleBufferDelegate(self, queue: dataQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    /// Returns at once: the microphone starts on its own queue, so the start sound and the pill never wait for it.
    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        guard let microphone = Self.builtInMicrophone() ?? AVCaptureDevice.default(for: .audio) else { throw Failure.noInput }
        if microphone.uniqueID != device?.uniqueID || device?.isConnected != true {
            let input = try AVCaptureDeviceInput(device: microphone)
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            let added = session.canAddInput(input)
            if added { session.addInput(input) }
            session.commitConfiguration()
            guard added else { throw Failure.noInput }
            device = microphone
        }
        sessionQueue.async { [session] in session.startRunning() }
    }

    func stop() -> [Float] {
        sessionQueue.sync { session.stopRunning() }
        dataQueue.sync {}
        lock.lock()
        defer { lock.unlock() }
        let recorded = samples
        samples = []
        return recorded
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
        guard count > 0 else { return }
        var chunk = [Float](repeating: 0, count: count)
        let status = chunk.withUnsafeMutableBytes { bytes in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { return }
        let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-6))
        let level = min(max((decibels + 52) / 40, 0), 1)
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }

    /// The Mac's own microphone; nil without one or with the lid closed, which cuts it off.
    private static func builtInMicrophone() -> AVCaptureDevice? {
        guard !lidClosed else { return nil }
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices.first { $0.transportType == Int32(kAudioDeviceTransportTypeBuiltIn) }
    }

    private static var lidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
    }
}
