import Foundation

/// Trim only a bounded, almost inaudible PCM prefix. This is not voice activity
/// detection: inner pauses, breathing and original cached bytes are preserved.
struct SpeechOnset {
    private var pending = Data()
    private var decided = false
    private(set) var removedFrames = 0
    private let limit = 6_000 // 250 ms at 24 kHz, mono signed 16-bit PCM.
    private let preRoll = 960 // Keep 40 ms before even a very soft onset.
    mutating func accept(_ pcm:Data) -> Data {
        if decided {return pcm}
        pending.append(pcm)
        let scanned = min(pending.count/2,limit+preRoll)
        let onset:Int? = pending.withUnsafeBytes { bytes in
            (0..<scanned).first {abs(Int(Int16(littleEndian:bytes.loadUnaligned(fromByteOffset:$0*2,as:Int16.self))))>32}
        }
        guard onset != nil || pending.count/2>=limit+preRoll else {return Data()}
        removedFrames = onset.map {min(limit,max(0,$0-preRoll))} ?? limit
        decided = true
        let result = Data(pending.dropFirst(removedFrames*2));pending.removeAll(keepingCapacity:false)
        return result
    }
    mutating func finish() -> Data {
        // A short silent/very quiet event is preserved in full, not discarded.
        decided = true;defer {pending.removeAll(keepingCapacity:false)}
        return pending
    }
}
