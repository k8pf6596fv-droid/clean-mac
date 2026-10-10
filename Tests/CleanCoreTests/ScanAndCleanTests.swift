import XCTest
@testable import CleanCore

final class ScanAndCleanTests: FixtureTestCase {
    private func makeCache(_ name: String, ageDays: Double) throws {
        try makeFile("Library/Caches/\(name)/data.bin")
        setAge(home + "/Library/Caches/" + name, days: ageDays)
    }

    func testUserCachesFiltering() throws {
        try makeCache("com.example.old", ageDays: 10)
        try makeCache("com.example.recent", ageDays: 0)
        try makeCache("com.example.running", ageDays: 10)
        try makeCache("com.apple.thing", ageDays: 10)
        let e = env(installed: ["com.example.old", "com.example.recent", "com.example.running"],
                    running: ["com.example.running"])
        let r = scan(e)
        XCTAssertEqual(names(r, .userCaches), ["com.example.old"])
    }

    func testLeftoversAreSeparateAndNotSelectedByDefault() throws {
        try makeCache("com.gone.app", ageDays: 10)
        let r = scan(env())
        XCTAssertEqual(names(r, .appLeftovers), ["com.gone.app"])
        XCTAssertEqual(names(r, .userCaches), [])
        XCTAssertFalse(r.defaultSelection.contains(.appLeftovers))
        XCTAssertEqual(r.categories.first?.definition.risk, RiskLevel.review)
    }

    func testNoDoubleCountingBetweenCategories() throws {
        try makeCache("Homebrew", ageDays: 10)
        try makeFile("Library/Caches/Homebrew/downloads/x.bin")
        setAge(home + "/Library/Caches/Homebrew", days: 10)
        try makeCache("com.example.other", ageDays: 10)
        let r = scan(env(installed: ["com.example.other"]))
        XCTAssertEqual(names(r, .homebrew), ["downloads", "data.bin"].sorted())
        XCTAssertEqual(names(r, .userCaches), ["com.example.other"])
        let all = r.categories.flatMap { $0.items.map { $0.path } }
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testLogsAndCrashReports() throws {
        try makeFile("Library/Logs/old.log")
        try makeFile("Library/Logs/new.log")
        try makeFile("Library/Logs/DiagnosticReports/crash.ips")
        setAge(home + "/Library/Logs/old.log", days: 40)
        setAge(home + "/Library/Logs/DiagnosticReports/crash.ips", days: 40)
        let r = scan(env())
        XCTAssertEqual(names(r, .logs), ["old.log"])
        XCTAssertEqual(names(r, .crashReports), ["crash.ips"])
    }

    func testTemporaryFiles() throws {
        try makeFile("tmp/old.tmp")
        try makeFile("tmp/new.tmp")
        try makeFile("tmp/.hidden")
        setAge(home + "/tmp/old.tmp", days: 10)
        setAge(home + "/tmp/.hidden", days: 10)
        let r = scan(env())
        XCTAssertEqual(names(r, .temporaryFiles), ["old.tmp"])
    }

    func testMissingFoldersDoNotCrash() throws {
        try fm.removeItem(atPath: home + "/Library/Caches")
        let r = scan(env())
        XCTAssertTrue(r.categories.isEmpty)
    }

    func testDryRunDeletesNothing() throws {
        try makeCache("com.example.a", ageDays: 10)
        let e = env(installed: ["com.example.a"])
        let r = scan(e)
        let result = CleanEngine(environment: e).clean(report: r, selection: r.defaultSelection, dryRun: true)
        XCTAssertEqual(result.count(.simulated), 1)
        XCTAssertEqual(result.count(.removed), 0)
        XCTAssertTrue(fm.fileExists(atPath: home + "/Library/Caches/com.example.a"))
    }

    func testCleanRemovesOnlySelectedCategories() throws {
        try makeCache("com.example.a", ageDays: 10)
        try makeCache("com.gone.app", ageDays: 10)
        let e = env(installed: ["com.example.a"])
        let r = scan(e)
        let result = CleanEngine(environment: e).clean(report: r, selection: r.defaultSelection, dryRun: false)
        XCTAssertEqual(result.count(.removed), 1)
        XCTAssertFalse(fm.fileExists(atPath: home + "/Library/Caches/com.example.a"))
        XCTAssertTrue(fm.fileExists(atPath: home + "/Library/Caches/com.gone.app"))
        XCTAssertGreaterThan(result.removedBytes, 0)
    }

    func testSymlinkTargetIsNeverTouched() throws {
        let outside = base + "/outside"
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        fm.createFile(atPath: outside + "/precious.txt", contents: Data(repeating: 1, count: 50_000))
        let link = home + "/Library/Caches/com.evil.link"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: outside)
        try makeCache("com.example.ok", ageDays: 10)
        let e = env(installed: ["com.example.ok", "com.evil.link"])
        let r = scan(e)
        XCTAssertEqual(names(r, .userCaches), ["com.example.ok"])
        _ = CleanEngine(environment: e).clean(report: r, selection: r.defaultSelection, dryRun: false)
        XCTAssertTrue(fm.fileExists(atPath: outside + "/precious.txt"))
        XCTAssertNotNil(try? fm.destinationOfSymbolicLink(atPath: link))
        XCTAssertFalse(fm.fileExists(atPath: home + "/Library/Caches/com.example.ok"))
    }

    func testItemModifiedAfterScanIsSkipped() throws {
        try makeCache("com.example.a", ageDays: 10)
        let e = env(installed: ["com.example.a"])
        let r = scan(e)
        try makeFile("Library/Caches/com.example.a/new.bin")
        let result = CleanEngine(environment: e).clean(report: r, selection: r.defaultSelection, dryRun: false)
        XCTAssertEqual(result.count(.removed), 0)
        XCTAssertEqual(result.count(.skipped), 1)
        XCTAssertTrue(fm.fileExists(atPath: home + "/Library/Caches/com.example.a"))
    }

    func testCleaningTwiceIsHarmless() throws {
        try makeCache("com.example.a", ageDays: 10)
        let e = env(installed: ["com.example.a"])
        let r = scan(e)
        let engine = CleanEngine(environment: e)
        _ = engine.clean(report: r, selection: r.defaultSelection, dryRun: false)
        let second = engine.clean(report: r, selection: r.defaultSelection, dryRun: false)
        XCTAssertEqual(second.count(.removed), 0)
        XCTAssertEqual(second.count(.failed), 0)
        XCTAssertEqual(second.count(.skipped), 1)
    }

    func testProtectedContentIsNeverDeleted() throws {
        try makeFile("Library/Caches/com.example.a/Cookies.binarycookies")
        setAge(home + "/Library/Caches/com.example.a", days: 10)
        let e = env(installed: ["com.example.a"])
        let r = scan(e)
        XCTAssertEqual(names(r, .userCaches), [])
        XCTAssertTrue(fm.fileExists(atPath: home + "/Library/Caches/com.example.a/Cookies.binarycookies"))
    }

    func testCancellationStopsScan() throws {
        try makeCache("com.example.a", ageDays: 10)
        let r = CleanScanner(environment: env(installed: ["com.example.a"]))
            .scan(progress: { _ in }, isCancelled: { true })
        XCTAssertTrue(r.cancelled)
    }

    func testEmptyTrash() throws {
        try makeFile(".Trash/old.txt")
        let engine = CleanEngine(environment: env())
        let dry = engine.emptyTrash(dryRun: true)
        XCTAssertEqual(dry.removedCount, 1)
        XCTAssertTrue(fm.fileExists(atPath: home + "/.Trash/old.txt"))
        let real = engine.emptyTrash(dryRun: false)
        XCTAssertEqual(real.removedCount, 1)
        XCTAssertFalse(fm.fileExists(atPath: home + "/.Trash/old.txt"))
    }
}
