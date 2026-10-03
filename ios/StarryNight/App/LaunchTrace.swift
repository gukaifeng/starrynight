import Foundation
import OSLog

/// Separate the usable native shell from the first prepared Unity frame. This
/// measures app-owned scene work, not dyld / the OS launch-screen interval.
@MainActor enum LaunchTrace {
    private static var startedAt: TimeInterval?
    private static let logger = Logger(subsystem:"com.modelspace.viewer",category:"Startup")
    private static var file: URL? {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--startup-review") {
            return FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first?
                .appendingPathComponent("startup-events.jsonl")
        }
#endif
        return nil
    }
    static func begin() {
        startedAt = ProcessInfo.processInfo.systemUptime
        if let file { try? FileManager.default.removeItem(at:file) }
        mark("sceneConnected")
    }
    static func mark(_ phase: String) {
        guard let startedAt else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime-startedAt
        logger.info("launch_phase=\(phase,privacy:.public) elapsed=\(elapsed)")
        guard let file, let data = try? JSONSerialization.data(withJSONObject:["phase":phase,"elapsed":elapsed]) else { return }
        if !FileManager.default.fileExists(atPath:file.path) { FileManager.default.createFile(atPath:file.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd(); try? handle.write(contentsOf:data+Data("\n".utf8))
        }
    }
}
