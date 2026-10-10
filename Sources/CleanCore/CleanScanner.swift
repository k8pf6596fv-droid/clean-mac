import Foundation

/// Analyse en LECTURE SEULE : ne modifie rien sur le disque.
public final class CleanScanner: @unchecked Sendable {
    private struct Candidate {
        let path: String
        let name: String
        let root: String
    }

    private enum Evaluation {
        case accept(CleanItem)
        case skip(String)
        case ignore
    }

    private let env: SystemEnvironment
    private let guardian: SafetyGuard
    private let home: String

    public init(environment: SystemEnvironment) {
        self.env = environment
        self.home = SafetyGuard.stripTrailingSlash(environment.homeDirectory)
        self.guardian = SafetyGuard(home: environment.homeDirectory,
                                    extraRoots: [CategoryCatalog.temporaryRoot(environment)])
    }

    public func scan(progress: @Sendable (ProgressUpdate) -> Void,
                     isCancelled: @Sendable () -> Bool) -> ScanReport {
        let fm = FileManager.default
        let defs = CategoryCatalog.definitions(for: env)
        let running = env.runningBundleIdentifiers()
        var claimed = Set<String>()
        var plans: [(def: CategoryDefinition, candidates: [Candidate], notice: String?)] = []
        var total = 0

        progress(ProgressUpdate(fraction: 0, message: "Préparation"))

        for def in defs {
            let blocked = def.blockedWhileRunning.filter { running.contains($0) }
            if !blocked.isEmpty {
                let present = def.roots.contains { fm.fileExists(atPath: $0) }
                plans.append((def, [], present ? "Application ouverte : fermez-la pour nettoyer cette catégorie." : nil))
                continue
            }
            let cands = listCandidates(def, running: running, claimed: &claimed)
            total += cands.count
            plans.append((def, cands, nil))
        }

        let walker = DiskWalker()
        var results: [CategoryResult] = []
        var done = 0
        var cancelled = false
        var lastFraction = -1.0
        let totalSteps = Double(max(total + 2, 1))

        outer: for plan in plans {
            var items: [CleanItem] = []
            var skipped: [SkippedItem] = []
            for c in plan.candidates {
                if isCancelled() {
                    cancelled = true
                    break outer
                }
                let m = walker.measure(path: c.path, isCancelled: isCancelled)
                if m.cancelled {
                    cancelled = true
                    break outer
                }
                switch evaluate(c, m, plan.def) {
                case .accept(let item):
                    items.append(item)
                case .skip(let reason):
                    if skipped.count < 200 {
                        skipped.append(SkippedItem(path: c.path, name: c.name, reason: reason))
                    }
                case .ignore:
                    break
                }
                done += 1
                let f = Double(done) / totalSteps
                if f - lastFraction >= 0.01 {
                    lastFraction = f
                    progress(ProgressUpdate(fraction: min(f, 0.97), message: plan.def.title))
                }
            }
            if !items.isEmpty || plan.notice != nil {
                items.sort { $0.sizeBytes > $1.sizeBytes }
                results.append(CategoryResult(definition: plan.def, items: items, skipped: skipped, notice: plan.notice))
            }
        }

        var trash: TrashState = .empty
        var suggestions: [ReviewSuggestion] = []
        var warnings: [String] = []

        if !cancelled {
            progress(ProgressUpdate(fraction: 0.97, message: "Corbeille"))
            trash = measureTrash(isCancelled: isCancelled)
            if case .unavailable = trash {
                warnings.append("La Corbeille n'a pas pu être mesurée (accès non autorisé).")
            }
            progress(ProgressUpdate(fraction: 0.98, message: "Fichiers volumineux à examiner"))
            suggestions = reviewSuggestions(isCancelled: isCancelled)
            cancelled = isCancelled()
        }

        results.sort { a, b in
            if a.definition.risk != b.definition.risk { return a.definition.risk == .safe }
            return a.totalBytes > b.totalBytes
        }
        progress(ProgressUpdate(fraction: 1, message: "Terminé"))

        return ScanReport(categories: results, suggestions: suggestions, trash: trash,
                          disk: DiskInfo.current(path: home), warnings: warnings,
                          cancelled: cancelled, scannedAt: env.now)
    }

    // MARK: - Candidats

    private func listCandidates(_ def: CategoryDefinition, running: Set<String>, claimed: inout Set<String>) -> [Candidate] {
        var out: [Candidate] = []
        let fm = FileManager.default
        for root in def.roots {
            guard let rootInfo = FileInfo.at(root), rootInfo.isDirectory, !rootInfo.isSymlink else { continue }
            guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for name in names.sorted() {
                if def.reservedNames.contains(name) { continue }
                let path = root + "/" + name
                if claimed.contains(path) { continue }
                switch def.id {
                case .userCaches:
                    if name.hasPrefix("com.apple.") || running.contains(name) { continue }
                case .temporaryFiles:
                    if name.hasPrefix(".") || name.hasPrefix("com.apple.") || running.contains(name) { continue }
                case .appLeftovers:
                    guard let bid = CategoryCatalog.bundleIdentifier(fromEntryName: name),
                          !bid.hasPrefix("com.apple."),
                          !isRelatedAppInstalled(bid) else { continue }
                    claimed.insert(path)
                default:
                    break
                }
                out.append(Candidate(path: path, name: name, root: root))
            }
        }
        return out
    }

    private func isRelatedAppInstalled(_ bid: String) -> Bool {
        if env.isAppInstalled(bundleIdentifier: bid) { return true }
        var parts = bid.components(separatedBy: ".")
        while parts.count > 3 {
            parts.removeLast()
            if env.isAppInstalled(bundleIdentifier: parts.joined(separator: ".")) { return true }
        }
        return false
    }

    private func evaluate(_ c: Candidate, _ m: WalkResult, _ def: CategoryDefinition) -> Evaluation {
        if let hit = m.protectedHit { return .skip("Contient des données protégées (\(hit))") }
        if m.bytes <= 0 { return .ignore }
        if def.minimumAge > 0 && m.newestModification > env.now.addingTimeInterval(-def.minimumAge) {
            return .skip("Modifié récemment")
        }
        if case .denied(let why) = guardian.validate(path: c.path, allowedRoot: c.root) { return .skip(why) }
        if case .denied(let why) = guardian.validateOnDisk(path: c.path, allowedRoot: c.root) { return .skip(why) }
        return .accept(CleanItem(path: c.path, name: c.name, categoryID: def.id, rootPath: c.root,
                                 sizeBytes: m.bytes, fileCount: m.fileCount,
                                 newestModification: m.newestModification))
    }

    // MARK: - Corbeille

    private func measureTrash(isCancelled: () -> Bool) -> TrashState {
        let path = home + "/.Trash"
        guard FileManager.default.fileExists(atPath: path) else { return .empty }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return .unavailable("Accès à la Corbeille non autorisé")
        }
        let visible = names.filter { $0 != ".DS_Store" }
        if visible.isEmpty { return .empty }
        let walker = DiskWalker()
        var total: Int64 = 0
        for n in visible {
            if isCancelled() { break }
            total += walker.measure(path: path + "/" + n, isCancelled: isCancelled).bytes
        }
        return .measured(bytes: total, itemCount: visible.count)
    }

    // MARK: - Suggestions d'examen (jamais supprimées)

    private func reviewSuggestions(isCancelled: () -> Bool) -> [ReviewSuggestion] {
        var out: [ReviewSuggestion] = []
        let fm = FileManager.default

        let known: [(String, String, String)] = [
            (home + "/Library/Developer/Xcode/Archives", "Archives Xcode",
             "Archives d'applications : à examiner depuis Xcode."),
            (home + "/Library/Developer/CoreSimulator", "Simulateurs Xcode",
             "À gérer depuis Xcode. CLEAN n'y touche jamais."),
            (home + "/Library/Developer/Xcode/iOS DeviceSupport", "Supports d'appareils iOS",
             "Recréés au branchement d'un appareil, mais à examiner avec soin.")
        ]
        for (path, title, detail) in known {
            if isCancelled() { return out }
            guard fm.fileExists(atPath: path) else { continue }
            let bytes = DiskWalker().measure(path: path, isCancelled: isCancelled).bytes
            if bytes >= 200_000_000 {
                out.append(ReviewSuggestion(title: title, detail: detail, path: path, bytes: bytes))
            }
        }

        let downloads = home + "/Downloads"
        if fm.fileExists(atPath: downloads) {
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
            if let en = fm.enumerator(at: URL(fileURLWithPath: downloads),
                                      includingPropertiesForKeys: keys,
                                      options: [.skipsPackageDescendants],
                                      errorHandler: { _, _ in true }) {
                var found: [(String, Int64)] = []
                var visited = 0
                while let obj = en.nextObject() {
                    guard let url = obj as? URL else { continue }
                    visited += 1
                    if visited > 50_000 || isCancelled() { break }
                    guard let v = try? url.resourceValues(forKeys: Set(keys)),
                          v.isRegularFile == true, let size = v.fileSize else { continue }
                    if size >= 500_000_000 { found.append((url.path, Int64(size))) }
                }
                found.sort { $0.1 > $1.1 }
                for (path, size) in found.prefix(6) {
                    out.append(ReviewSuggestion(title: (path as NSString).lastPathComponent,
                                                detail: "Fichier volumineux dans Téléchargements",
                                                path: path, bytes: size))
                }
            }
        }
        out.sort { $0.bytes > $1.bytes }
        return out
    }
}
