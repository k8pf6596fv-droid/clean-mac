import XCTest
@testable import CleanCore

final class SafetyGuardTests: FixtureTestCase {
    func testRejectsRootItself() {
        let g = SafetyGuard(home: home)
        let root = home + "/Library/Caches"
        XCTAssertFalse(g.validate(path: root, allowedRoot: root).isAllowed)
    }

    func testRejectsPathOutsideRoot() {
        let g = SafetyGuard(home: home)
        XCTAssertFalse(g.validate(path: "/etc/hosts", allowedRoot: home + "/Library/Caches").isAllowed)
    }

    func testRejectsParentTraversal() {
        let g = SafetyGuard(home: home)
        let root = home + "/Library/Caches"
        XCTAssertFalse(g.validate(path: root + "/../../Documents", allowedRoot: root).isAllowed)
    }

    func testRejectsGrandchildren() {
        let g = SafetyGuard(home: home)
        let root = home + "/Library/Caches"
        XCTAssertFalse(g.validate(path: root + "/a/b", allowedRoot: root).isAllowed)
    }

    func testAcceptsDirectChild() {
        let g = SafetyGuard(home: home)
        let root = home + "/Library/Caches"
        XCTAssertTrue(g.validate(path: root + "/com.example.app", allowedRoot: root).isAllowed)
    }

    func testRejectsProtectedRoots() {
        let g = SafetyGuard(home: home)
        XCTAssertFalse(g.validate(path: home + "/Documents/a.txt", allowedRoot: home + "/Documents").isAllowed)
        XCTAssertFalse(g.validate(path: home + "/Library/Mobile Documents/x",
                                  allowedRoot: home + "/Library/Mobile Documents").isAllowed)
        XCTAssertFalse(g.validate(path: home + "/Library/Keychains/x",
                                  allowedRoot: home + "/Library/Keychains").isAllowed)
    }

    func testRejectsRootOutsideHome() {
        let g = SafetyGuard(home: home)
        XCTAssertFalse(g.validate(path: "/Library/Caches/x", allowedRoot: "/Library/Caches").isAllowed)
    }

    func testRejectsProtectedNames() {
        let g = SafetyGuard(home: home)
        let root = home + "/Library/Caches"
        XCTAssertFalse(g.validate(path: root + "/Photos Library.photoslibrary", allowedRoot: root).isAllowed)
        XCTAssertFalse(g.validate(path: root + "/Cookies", allowedRoot: root).isAllowed)
    }

    func testRejectsSymlinkOnDisk() throws {
        let g = SafetyGuard(home: home)
        let target = base + "/target"
        try fm.createDirectory(atPath: target, withIntermediateDirectories: true)
        let link = home + "/Library/Caches/link"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertFalse(g.validateOnDisk(path: link, allowedRoot: home + "/Library/Caches").isAllowed)
    }

    func testAcceptsRegularDirectoryOnDisk() throws {
        let g = SafetyGuard(home: home)
        try makeFile("Library/Caches/com.example.app/a.bin")
        let verdict = g.validateOnDisk(path: home + "/Library/Caches/com.example.app",
                                       allowedRoot: home + "/Library/Caches")
        XCTAssertTrue(verdict.isAllowed)
    }
}
