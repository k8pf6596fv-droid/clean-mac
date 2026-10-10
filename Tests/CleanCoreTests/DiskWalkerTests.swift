import XCTest
@testable import CleanCore

final class DiskWalkerTests: FixtureTestCase {
    func testMeasuresFileSizes() throws {
        try makeFile("Library/Caches/com.example.app/a.bin", bytes: 40_000)
        let r = DiskWalker().measure(path: home + "/Library/Caches/com.example.app")
        XCTAssertGreaterThanOrEqual(r.bytes, 40_000)
        XCTAssertEqual(r.fileCount, 1)
    }

    func testHardLinksAreNotCountedTwice() throws {
        let a = try makeFile("Library/Caches/com.example.app/a.bin", bytes: 40_000)
        try fm.linkItem(atPath: a, toPath: home + "/Library/Caches/com.example.app/b.bin")
        let r = DiskWalker().measure(path: home + "/Library/Caches/com.example.app")
        XCTAssertEqual(r.fileCount, 1)
    }

    func testSymlinksAreNotFollowed() throws {
        let outside = base + "/outside"
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        fm.createFile(atPath: outside + "/big.bin", contents: Data(repeating: 1, count: 2_000_000))
        try fm.createDirectory(atPath: home + "/Library/Caches/com.example.app", withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: home + "/Library/Caches/com.example.app/link", withDestinationPath: outside)
        let r = DiskWalker().measure(path: home + "/Library/Caches/com.example.app")
        XCTAssertLessThan(r.bytes, 100_000)
    }

    func testDetectsProtectedContent() throws {
        try makeFile("Library/Caches/com.example.app/Cookies.binarycookies")
        let r = DiskWalker().measure(path: home + "/Library/Caches/com.example.app")
        XCTAssertEqual(r.protectedHit, "Cookies.binarycookies")
    }

    func testMissingPathDoesNotCrash() {
        let r = DiskWalker().measure(path: home + "/does-not-exist")
        XCTAssertEqual(r.bytes, 0)
        XCTAssertEqual(r.unreadableCount, 1)
    }
}
