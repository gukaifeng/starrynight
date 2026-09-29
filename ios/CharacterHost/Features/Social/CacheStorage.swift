import Foundation

enum CacheCategory: String, CaseIterable, Identifiable, Sendable {
    case speech, portraits, exports
    var id: String { rawValue }
    var title: String {
        switch self { case .speech: "语音缓存"; case .portraits: "角色头像"; case .exports: "对话长图" }
    }
    var detail: String {
        switch self {
        case .speech: "已生成的朗读，下次播放时重新准备"
        case .portraits: "定制头像的副本，下次见面时重新生成"
        case .exports: "导出与预览的临时图片，不影响已另存的图片"
        }
    }
    var symbol: String {
        switch self { case .speech: "speaker.wave.2"; case .portraits: "person.crop.circle"; case .exports: "photo.on.rectangle.angled" }
    }
}

struct CacheLocations: Sendable {
    let speech: URL
    let portraits: URL
    let exports: URL
    static var live: Self {
        let fm = FileManager.default
        return Self(speech:fm.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("SpeechClips-v1"),
                    portraits:fm.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("CharacterPortraits"),
                    exports:fm.temporaryDirectory.appendingPathComponent("ConversationImages"))
    }
    static var current: Self {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--cache-fixture") {
            let root = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("CacheReview")
            return .fixture(root)
        }
#endif
        return .live
    }
    static func fixture(_ root: URL) -> Self {
        Self(speech:root.appendingPathComponent("speech"),portraits:root.appendingPathComponent("portraits"),exports:root.appendingPathComponent("exports"))
    }
    func directory(_ category: CacheCategory) -> URL {
        switch category { case .speech: speech; case .portraits: portraits; case .exports: exports }
    }
}

struct CacheUsage: Identifiable, Sendable {
    let category: CacheCategory
    var bytes: Int64 = 0
    var protectedBytes: Int64 = 0
    var files = 0
    var removableFiles = 0
    var id: CacheCategory { category }
    var removableBytes: Int64 { max(0,bytes-protectedBytes) }
}
struct CacheSnapshot: Sendable {
    var categories: [CacheUsage]
    var issues: Int
    var bytes: Int64 { categories.reduce(0) { $0+$1.bytes } }
    var protectedBytes: Int64 { categories.reduce(0) { $0+$1.protectedBytes } }
    func removableBytes(in selected: Set<CacheCategory>) -> Int64 {
        categories.filter { selected.contains($0.category) }.reduce(0) { $0+$1.removableBytes }
    }
    func removableFiles(in selected: Set<CacheCategory>) -> Int {
        categories.filter { selected.contains($0.category) }.reduce(0) { $0+$1.removableFiles }
    }
}
struct CacheClearResult: Sendable {
    let removedBytes: Int64
    let removedFiles: Int
    let failures: Int
    let snapshot: CacheSnapshot
}

/// Keeps in-progress exports and their previews alive across actor/UI boundaries.
/// The UI and system share items retain the same lease; deinit releases it.
final class CacheFileLease: Sendable {
    let id: UUID
    let storage: CacheStorage
    init(id: UUID, storage: CacheStorage) { self.id = id; self.storage = storage }
    deinit {
        let id = id, storage = storage
        Task { await storage.release(id) }
    }
}

/// Only explicitly owned, reproducible files are counted/deleted. Never wipe
/// Documents, Application Support, the whole Caches folder, tmp, or the bundle.
/// All enumeration/removal happens off MainActor; leases serialize with deletion.
actor CacheStorage {
    static let shared = CacheStorage(locations:.current)
    static let shareMarker = ".shared-until"
    let locations: CacheLocations
    private var leases: [UUID:URL] = [:]
    private let fm = FileManager()
    private struct Entry {
        let url: URL
        let category: CacheCategory
        let bytes: Int64
        let protected: Bool
    }
    init(locations: CacheLocations) { self.locations = locations }
    private func canonical(_ url: URL) -> URL { url.standardizedFileURL }
    private func isExportDirectory(_ url: URL) -> Bool {
        canonical(url.deletingLastPathComponent()) == canonical(locations.exports) && UUID(uuidString:url.lastPathComponent) != nil
    }
    func leaseExport(_ directory: URL) throws -> CacheFileLease {
        guard isExportDirectory(directory) else { throw CocoaError(.fileWriteInvalidFileName) }
        let id = UUID(); leases[id] = canonical(directory)
        return CacheFileLease(id:id,storage:self)
    }
    func release(_ id: UUID) { leases.removeValue(forKey:id) }
    /// Completed system shares can still be read lazily by another process.
    /// Persist the existing 24h retention rule across launches, only for shares.
    func retainSharedExport(_ directory: URL, now: Date = Date()) throws {
        guard isExportDirectory(directory), try regularDirectory(directory) else { throw CocoaError(.fileNoSuchFile) }
        try Data(String(now.addingTimeInterval(86_400).timeIntervalSince1970).utf8)
            .write(to:directory.appendingPathComponent(Self.shareMarker),options:.atomic)
    }
    func cancelShareRetention(_ directory: URL) {
        guard isExportDirectory(directory), (try? regularDirectory(directory)) == true else { return }
        try? fm.removeItem(at:directory.appendingPathComponent(Self.shareMarker))
    }
    func pruneExports(now: Date = Date()) {
        for entry in entries(now:now).0 where entry.category == .exports && !entry.protected {
            guard let created = try? entry.url.deletingLastPathComponent().resourceValues(forKeys:[.creationDateKey]).creationDate,
                  created < now.addingTimeInterval(-86_400),
                  (try? safePath(entry.url,under:locations.exports)) == true else { continue }
            try? fm.removeItem(at:entry.url)
        }
    }
    func snapshot(now: Date = Date()) -> CacheSnapshot {
        let (entries, issues) = entries(now:now)
        return summary(entries,issues:issues)
    }
    func clear(_ selected: Set<CacheCategory>, now: Date = Date()) -> CacheClearResult {
        let (entries, scanIssues) = entries(now:now)
        var removedBytes: Int64 = 0, removedFiles = 0, failures = scanIssues
        for entry in entries where selected.contains(entry.category) && !entry.protected {
            do {
                // Recheck the path immediately before deleting; never follow links.
                guard try safePath(entry.url,under:locations.directory(entry.category)),
                      try entry.url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey]).isRegularFile == true else {
                    failures += 1; continue
                }
                try fm.removeItem(at:entry.url); removedBytes += entry.bytes; removedFiles += 1
            } catch {
                if !Self.missing(error) { failures += 1 }
            }
        }
        // Leave each feature root in place so writers can immediately reuse it.
        if selected.contains(.exports), (try? regularDirectory(locations.exports)) == true {
            for directory in (try? fm.contentsOfDirectory(at:locations.exports,includingPropertiesForKeys:nil)) ?? [] {
                if isExportDirectory(directory), (try? regularDirectory(directory)) == true,
                   (try? fm.contentsOfDirectory(atPath:directory.path).isEmpty) == true { try? fm.removeItem(at:directory) }
            }
        }
        return CacheClearResult(removedBytes:removedBytes,removedFiles:removedFiles,failures:failures,snapshot:snapshot(now:now))
    }
    private static func missing(_ error: Error) -> Bool {
        let e = error as NSError
        return e.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(e.code)
    }
    private func regularDirectory(_ url: URL) throws -> Bool {
        let value = try url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        return value.isDirectory == true && value.isSymbolicLink != true
    }
    private func safePath(_ url: URL, under root: URL) throws -> Bool {
        var cursor = canonical(url)
        let base = canonical(root)
        guard cursor.path.hasPrefix(base.path + "/") else { return false }
        while cursor.path != base.path {
            if try cursor.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink == true { return false }
            cursor.deleteLastPathComponent()
        }
        return try regularDirectory(base)
    }
    private func entries(now: Date) -> ([Entry],Int) {
        var output: [Entry] = [], issues = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey,.isDirectoryKey,.isSymbolicLinkKey,.totalFileAllocatedSizeKey,.fileSizeKey]
        for category in CacheCategory.allCases {
            let root = locations.directory(category)
            do {
                guard try regularDirectory(root) else { issues += 1; continue }
                let children = try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:Array(keys))
                for child in children {
                    do {
                        let value = try child.resourceValues(forKeys:keys)
                        if value.isSymbolicLink == true { continue }
                        if category == .exports {
                            guard isExportDirectory(child), value.isDirectory == true else { continue }
                            let marker = child.appendingPathComponent(Self.shareMarker)
                            var shared = false
                            do {
                                let markerValues = try marker.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey])
                                if markerValues.isSymbolicLink != true, markerValues.isRegularFile == true,
                                   let until = Double(try String(contentsOf:marker,encoding:.utf8)), until.isFinite {
                                    shared = until > now.timeIntervalSince1970
                                } else {
                                    shared = true; issues += 1
                                }
                            } catch { if !Self.missing(error) { shared = true; issues += 1 } }
                            let protected = leases.values.contains(canonical(child)) || shared
                            for file in try fm.contentsOfDirectory(at:child,includingPropertiesForKeys:Array(keys)) {
                                guard ["png","jpg"].contains(file.pathExtension.lowercased()) || file.lastPathComponent == Self.shareMarker else { continue }
                                let values = try file.resourceValues(forKeys:keys)
                                if values.isRegularFile == true && values.isSymbolicLink != true {
                                    output.append(Entry(url:file,category:category,bytes:Int64(max(0,values.totalFileAllocatedSize ?? values.fileSize ?? 0)),protected:protected))
                                }
                            }
                        } else {
                            let allowed = category == .speech ? (child.pathExtension == "wav" && child.deletingPathExtension().lastPathComponent.count == 64 && child.deletingPathExtension().lastPathComponent.allSatisfy(\.isHexDigit)) : ["png","json"].contains(child.pathExtension)
                            guard allowed, value.isRegularFile == true else { continue }
                            output.append(Entry(url:child,category:category,bytes:Int64(max(0,value.totalFileAllocatedSize ?? value.fileSize ?? 0)),protected:false))
                        }
                    } catch { if !Self.missing(error) { issues += 1 } }
                }
            } catch { if !Self.missing(error) { issues += 1 } }
        }
        return (output,issues)
    }
    private func summary(_ entries: [Entry], issues: Int) -> CacheSnapshot {
        CacheSnapshot(categories:CacheCategory.allCases.map { category in
            var value = CacheUsage(category:category)
            for entry in entries where entry.category == category {
                value.bytes += entry.bytes; value.files += 1
                if entry.protected { value.protectedBytes += entry.bytes } else { value.removableFiles += 1 }
            }
            return value
        },issues:issues)
    }
}
