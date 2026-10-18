import AVFoundation

/// Records mic audio as 16 kHz mono 16-bit PCM and returns it as WAV data.
/// The engine only exists while recording, so idle cost is ~zero.
final class Recorder {
    private var engine: AVAudioEngine?
    private var pcm = Data()
    private let lock = NSLock()
    /// Loudest sample (0...32767) of the last recording; near 0 means the mic gave silence.
    private(set) var lastPeak: Int = 0
    /// Called on the main queue with the live mic level (0...1) while recording.
    var onLevel: ((CGFloat) -> Void)?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    func start() throws {
        pcm = Data()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inFormat, to: target) else {
            throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio converter"])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let ratio = self.target.sampleRate / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: cap) else { return }
            var consumed = false
            var err: NSError?
            converter.convert(to: out, error: &err) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard err == nil, let ch = out.int16ChannelData else { return }
            let bytes = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
            self.lock.lock(); self.pcm.append(bytes); self.lock.unlock()
            if let onLevel = self.onLevel, out.frameLength > 0 {
                var sum: Double = 0
                for i in 0..<Int(out.frameLength) { let s = Double(ch[0][i]); sum += s * s }
                let rms = (sum / Double(out.frameLength)).squareRoot() / 32768
                let level = CGFloat(min(1, rms * 9))   // speech RMS is small; scale it to fill the bars
                DispatchQueue.main.async { onLevel(level) }
            }
        }
        try engine.start()
        self.engine = engine
    }

    /// Stops recording; returns WAV data, or nil if nothing meaningful was captured.
    func stop() -> Data? {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        lock.lock(); let data = pcm; pcm = Data(); lock.unlock()
        guard data.count > 16000 * 2 / 4 else { return nil } // < 0.25 s
        lastPeak = data.withUnsafeBytes { raw in
            raw.bindMemory(to: Int16.self).reduce(0) { max($0, abs(Int($1))) }
        }
        return Self.wav(from: data)
    }

    func cancel() { _ = stop() }

    private static func wav(from pcm: Data) -> Data {
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count))
        h.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(16000); u32(16000 * 2); u16(2); u16(16)
        h.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
        return h + pcm
    }
}
