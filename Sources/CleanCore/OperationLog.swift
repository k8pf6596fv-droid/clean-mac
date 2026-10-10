import Foundation

/// Journal local des opérations (jamais envoyé nulle part).
public final class OperationLog: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLog(home: String) -> OperationLog {
        let dir = URL(fileURLWithPath: home)
            .appendingPathComponent("Library/Application Support/CLEAN", isDirectory: true)
        return OperationLog(fileURL: dir.appendingPathComponent("operations.log"))
    }

    public func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? NSNumber, size.intValue > 2_000_000 {
            let old = dir.appendingPathComponent("operations.1.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: fileURL, to: old)
        }
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let data = (formatter.string(from: Date()) + " " + line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
