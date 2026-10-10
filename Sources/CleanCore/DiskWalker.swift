import Foundation

public struct WalkResult: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var fileCount: Int = 0
    public var newestModification: Date = Date.distantPast
    public var unreadableCount: Int = 0
    /// Nom du premier élément protégé rencontré à l'intérieur (cookies, trousseau, photothèque…).
    public var protectedHit: String? = nil
    public var cancelled: Bool = false
    public init() {}
}

/// Mesure l'espace réellement occupé (blocs alloués), sans jamais suivre un lien symbolique
/// et sans compter deux fois un fichier à liens physiques multiples.
public final class DiskWalker {
    private struct FileID: Hashable {
        let device: Int64
        let inode: UInt64
    }

    private var seen = Set<FileID>()

    public init() {}

    public func measure(path: String, isCancelled: () -> Bool = { false }) -> WalkResult {
        var result = WalkResult()
        walk(path, &result, isCancelled, 0)
        return result
    }

    private func walk(_ path: String, _ result: inout WalkResult, _ isCancelled: () -> Bool, _ depth: Int) {
        if result.cancelled { return }
        if isCancelled() {
            result.cancelled = true
            return
        }
        guard let info = FileInfo.at(path) else {
            result.unreadableCount += 1
            return
        }
        if info.modified > result.newestModification { result.newestModification = info.modified }

        if info.isSymlink {
            result.fileCount += 1
            return
        }

        if info.isDirectory {
            result.bytes += info.allocatedBytes
            if depth >= 100 {
                result.unreadableCount += 1
                return
            }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                result.unreadableCount += 1
                return
            }
            for name in names {
                if result.protectedHit == nil && SafetyGuard.isProtectedName(name) {
                    result.protectedHit = name
                }
                walk(path + "/" + name, &result, isCancelled, depth + 1)
                if result.cancelled { return }
            }
            return
        }

        if info.linkCount > 1 {
            let id = FileID(device: info.device, inode: info.inode)
            if !seen.insert(id).inserted { return }
        }
        result.bytes += info.allocatedBytes
        result.fileCount += 1
    }
}
