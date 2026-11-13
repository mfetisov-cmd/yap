import AppKit

/// Soft low two-note «ту-лун»: up when recording starts, down when it stops. Synthesized, no sound files.
/// Low register and a slow fade, like Spokenly's sounds (measured there at ~290 and ~440 Hz).
@MainActor
enum Chime {
    static let startNotes = [293.66, 440.0]  // D4 → A4
    static let stopNotes = [440.0, 293.66]   // A4 → D4
    private static let startSound = sound(startNotes)
    private static let stopSound = sound(stopNotes)

    static func playStart() { play(startSound) }
    static func playStop() { play(stopSound) }

    private static func play(_ sound: NSSound?) {
        sound?.stop()
        sound?.play()
    }

    private static func sound(_ notes: [Double]) -> NSSound? {
        let sound = NSSound(data: wav(notes))
        sound?.volume = 0.6
        return sound
    }

    /// Warm sine notes (soft attack, slow fade) as 16-bit mono WAV.
    static func wav(_ notes: [Double]) -> Data {
        let rate = 44_100.0
        let gap = 0.09
        let length = 0.32
        let total = Int(rate * (gap * Double(notes.count - 1) + length + 0.05))
        var samples = [Float](repeating: 0, count: total)
        for (index, frequency) in notes.enumerated() {
            let offset = Int(rate * gap * Double(index))
            for i in 0..<Int(rate * length) where offset + i < total {
                let t = Double(i) / rate
                let envelope = min(t / 0.012, 1) * exp(-t / 0.085)
                let phase = 2 * .pi * frequency * t
                let wave = sin(phase) + 0.15 * sin(2 * phase) + 0.05 * sin(3 * phase)
                samples[offset + i] += Float(0.3 * envelope * wave)
            }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(total * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate) * 2)
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}
