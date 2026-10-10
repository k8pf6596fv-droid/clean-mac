import XCTest
@testable import CleanCore

struct MockEnvironment: SystemEnvironment {
    var homeDirectory: String
    var temporaryDirectory: String
    var now: Date
    var installed: Set<String>
    var running: Set<String>

    func isAppInstalled(bundleIdentifier: String) -> Bool { installed.contains(bundleIdentifier) }
    func runningBundleIdentifiers() -> Set<String> { running }
}

class FixtureTestCase: XCTestCase {
    var base = ""
    var home = ""
    let fm = FileManager.default

    override func setUpWithError() throws {
        base = NSTemporaryDirectory() + "clean-tests-" + UUID().uuidString
        home = base + "/home"
        try fm.createDirectory(atPath: home + "/Library/Caches", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: home + "/tmp", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: base)
    }

    @discardableResult
    func makeFile(_ relative: String, bytes: Int = 20_000) throws -> String {
        let path = home + "/" + relative
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        XCTAssertTrue(fm.createFile(atPath: path, contents: Data(repeating: 7, count: bytes)))
        return path
    }

    /// Vieillit un fichier ou un dossier (et son contenu) de `days` jours.
    func setAge(_ path: String, days: Double) {
        let date = Date().addingTimeInterval(-days * 86_400)
        if let names = try? fm.contentsOfDirectory(atPath: path) {
            for n in names { setAge(path + "/" + n, days: days) }
        }
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: path)
    }

    func env(installed: Set<String> = [], running: Set<String> = []) -> MockEnvironment {
        MockEnvironment(homeDirectory: home, temporaryDirectory: home + "/tmp",
                        now: Date(), installed: installed, running: running)
    }

    func scan(_ e: MockEnvironment) -> ScanReport {
        CleanScanner(environment: e).scan(progress: { _ in }, isCancelled: { false })
    }

    func names(_ report: ScanReport, _ id: CategoryID) -> [String] {
        let cat = report.categories.first { $0.id == id }
        return (cat?.items.map { $0.name } ?? []).sorted()
    }
}
