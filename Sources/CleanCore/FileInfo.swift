import Foundation
import Darwin

/// Lecture bas niveau (lstat) : ne suit jamais les liens symboliques.
struct FileInfo {
    let mode: mode_t
    let allocatedBytes: Int64
    let uid: UInt32
    let device: Int64
    let inode: UInt64
    let linkCount: Int
    let modified: Date

    var isSymlink: Bool { (mode & S_IFMT) == S_IFLNK }
    var isDirectory: Bool { (mode & S_IFMT) == S_IFDIR }

    static func at(_ path: String) -> FileInfo? {
        var st = stat()
        if lstat(path, &st) != 0 { return nil }
        let seconds = TimeInterval(st.st_mtimespec.tv_sec)
        let nanos = TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileInfo(
            mode: st.st_mode,
            allocatedBytes: Int64(st.st_blocks) * 512,
            uid: UInt32(st.st_uid),
            device: Int64(st.st_dev),
            inode: UInt64(st.st_ino),
            linkCount: Int(st.st_nlink),
            modified: Date(timeIntervalSince1970: seconds + nanos)
        )
    }

    static func realPath(_ path: String) -> String? {
        guard let p = realpath(path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }
}
