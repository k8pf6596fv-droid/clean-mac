import AppKit
import CleanCore

/// Implémentation réelle de l'environnement système (NSWorkspace, dossier personnel).
struct LiveEnvironment: SystemEnvironment {
    var homeDirectory: String { NSHomeDirectory() }
    var temporaryDirectory: String { NSTemporaryDirectory() }
    var now: Date { Date() }

    func isAppInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }
}

enum Fmt {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
