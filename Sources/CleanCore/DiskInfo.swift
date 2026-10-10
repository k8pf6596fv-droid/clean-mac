import Foundation

public enum DiskInfo {
    public static func current(path: String) -> DiskUsage? {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let raw = values.volumeAvailableCapacity else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? Int64(raw)
        return DiskUsage(
            totalBytes: Int64(total),
            availableBytes: Int64(raw),
            availableWithPurgeableBytes: max(important, Int64(raw))
        )
    }
}
