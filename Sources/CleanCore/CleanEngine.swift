import Foundation

/// Suppression : chaque élément est revalidé juste avant d'être supprimé.
public final class CleanEngine: @unchecked Sendable {
    private let env: SystemEnvironment
    private let guardian: SafetyGuard
    private let log: OperationLog?

    public init(environment: SystemEnvironment, log: OperationLog? = nil) {
        self.env = environment
        self.log = log
        self.guardian = SafetyGuard(home: environment.homeDirectory,
                                    extraRoots: [CategoryCatalog.temporaryRoot(environment)])
    }

    public func clean(report: ScanReport,
                      selection: Set<CategoryID>,
                      dryRun: Bool,
                      progress: @Sendable (ProgressUpdate) -> Void = { _ in },
                      isCancelled: @Sendable () -> Bool = { false }) -> CleanReport {
        let started = Date()
        let before = DiskInfo.current(path: env.homeDirectory)
        let running = env.runningBundleIdentifiers()
        var outcomes: [CleanOutcome] = []
        var cancelled = false
        let chosen = report.categories.filter { selection.contains($0.id) }
        let total = max(1, chosen.reduce(0) { $0 + $1.items.count })
        var done = 0
        var lastFraction = -1.0

        let ids = chosen.map { $0.id.rawValue }.joined(separator: ",")
        log?.write("DEBUT nettoyage simulation=\(dryRun) categories=\(ids)")

        outer: for cat in chosen {
            for item in cat.items {
                if isCancelled() {
                    cancelled = true
                    break outer
                }
                outcomes.append(process(item, definition: cat.definition, running: running, dryRun: dryRun))
                done += 1
                let f = Double(done) / Double(total)
                if f - lastFraction >= 0.01 || done == total {
                    lastFraction = f
                    progress(ProgressUpdate(fraction: f, message: cat.definition.title))
                }
            }
        }

        let after = DiskInfo.current(path: env.homeDirectory)
        let report = CleanReport(outcomes: outcomes, dryRun: dryRun,
                                 availableBefore: before?.availableBytes,
                                 availableAfter: after?.availableBytes,
                                 duration: Date().timeIntervalSince(started),
                                 cancelled: cancelled)
        log?.write("FIN nettoyage supprimes=\(report.removedBytes) simules=\(report.simulatedBytes) ignores=\(report.count(.skipped)) echecs=\(report.count(.failed)) interrompu=\(cancelled)")
        return report
    }

    private func process(_ item: CleanItem, definition: CategoryDefinition,
                         running: Set<String>, dryRun: Bool) -> CleanOutcome {
        func outcome(_ status: OutcomeStatus, _ bytes: Int64 = 0, _ message: String? = nil) -> CleanOutcome {
            if let message = message {
                log?.write("\(status) \(item.path) : \(message)")
            }
            return CleanOutcome(path: item.path, name: item.name, categoryID: item.categoryID,
                                status: status, bytes: bytes, message: message)
        }

        if definition.blockedWhileRunning.contains(where: { running.contains($0) }) {
            return outcome(.skipped, 0, "Application ouverte")
        }
        if running.contains(item.name) {
            return outcome(.skipped, 0, "Application ouverte")
        }
        if case .denied(let why) = guardian.validate(path: item.path, allowedRoot: item.rootPath) {
            return outcome(.skipped, 0, why)
        }
        if FileInfo.at(item.path) == nil {
            return outcome(.skipped, 0, "Déjà supprimé")
        }
        if case .denied(let why) = guardian.validateOnDisk(path: item.path, allowedRoot: item.rootPath) {
            return outcome(.skipped, 0, why)
        }

        let m = DiskWalker().measure(path: item.path)
        if let hit = m.protectedHit {
            return outcome(.skipped, 0, "Contient des données protégées (\(hit))")
        }
        if m.newestModification > item.newestModification.addingTimeInterval(1) {
            return outcome(.skipped, 0, "Modifié depuis l'analyse")
        }
        if definition.minimumAge > 0 && m.newestModification > env.now.addingTimeInterval(-definition.minimumAge) {
            return outcome(.skipped, 0, "Modifié récemment")
        }

        if dryRun {
            log?.write("SIMULATION \(item.path) (\(m.bytes) octets)")
            return outcome(.simulated, m.bytes)
        }

        log?.write("SUPPRESSION \(item.path) (\(m.bytes) octets)")
        do {
            try FileManager.default.removeItem(atPath: item.path)
        } catch {
            let remaining = DiskWalker().measure(path: item.path).bytes
            let partial = max(0, m.bytes - remaining)
            return outcome(.failed, partial, error.localizedDescription)
        }
        if FileInfo.at(item.path) != nil {
            let remaining = DiskWalker().measure(path: item.path).bytes
            return outcome(.failed, max(0, m.bytes - remaining), "Suppression incomplète")
        }
        return outcome(.removed, m.bytes)
    }

    // MARK: - Corbeille (action séparée, confirmée par l'utilisateur)

    public func emptyTrash(dryRun: Bool) -> TrashResult {
        var result = TrashResult()
        result.dryRun = dryRun
        let trashRoot = SafetyGuard.stripTrailingSlash(env.homeDirectory) + "/.Trash"
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: trashRoot) else {
            result.requiresFinder = true
            result.message = "CLEAN n'a pas accès à la Corbeille directement."
            return result
        }
        log?.write("DEBUT corbeille simulation=\(dryRun)")
        for name in names {
            let path = trashRoot + "/" + name
            if case .denied(let why) = guardian.validate(path: path, allowedRoot: trashRoot) {
                result.skippedCount += 1
                log?.write("IGNORE \(path) : \(why)")
                continue
            }
            if FileInfo.at(path) == nil { continue }
            if case .denied(let why) = guardian.validateOnDisk(path: path, allowedRoot: trashRoot, allowSymlinkLeaf: true) {
                result.skippedCount += 1
                log?.write("IGNORE \(path) : \(why)")
                continue
            }
            let bytes = DiskWalker().measure(path: path).bytes
            if dryRun {
                result.removedBytes += bytes
                result.removedCount += 1
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: path)
                result.removedBytes += bytes
                result.removedCount += 1
                log?.write("SUPPRESSION corbeille \(path) (\(bytes) octets)")
            } catch {
                result.failedCount += 1
                log?.write("ECHEC \(path) : \(error.localizedDescription)")
            }
        }
        log?.write("FIN corbeille supprimes=\(result.removedBytes) ignores=\(result.skippedCount) echecs=\(result.failedCount)")
        return result
    }
}
