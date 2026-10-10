import SwiftUI
import AppKit
import CleanCore

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum Phase {
        case idle, scanning, ready, cleaning, done
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var report: ScanReport?
    @Published var cleanReport: CleanReport?
    @Published var selected: Set<CategoryID> = []
    @Published var disk: DiskUsage?
    @Published var notice: String?
    @Published var trashMessage: String?
    @Published var trashBusy = false
    @Published var showDetails = false
    @Published var showReport = false
    @Published var showReviewConfirm = false
    @Published var showTrashConfirm = false
    @Published var dryRun: Bool = UserDefaults.standard.bool(forKey: "clean.dryRun") {
        didSet { UserDefaults.standard.set(dryRun, forKey: "clean.dryRun") }
    }

    private var cancelFlag = CancelFlag()

    init() {
        refreshDisk()
    }

    // MARK: - État

    func refreshDisk() {
        disk = DiskInfo.current(path: NSHomeDirectory())
    }

    var selectedBytes: Int64 {
        report?.bytes(for: selected) ?? 0
    }

    func setSelected(_ id: CategoryID, _ on: Bool) {
        if on { selected.insert(id) } else { selected.remove(id) }
    }

    func reset() {
        report = nil
        cleanReport = nil
        notice = nil
        trashMessage = nil
        phase = .idle
        refreshDisk()
    }

    func cancel() {
        cancelFlag.cancel()
        statusMessage = "Annulation…"
    }

    private func apply(_ update: ProgressUpdate) {
        if update.fraction >= progress { progress = update.fraction }
        statusMessage = update.message
    }

    // MARK: - Analyse

    func startScan() {
        guard phase == .idle || phase == .ready || phase == .done else { return }
        notice = nil
        report = nil
        cleanReport = nil
        trashMessage = nil
        progress = 0
        statusMessage = "Préparation"
        phase = .scanning
        let flag = CancelFlag()
        cancelFlag = flag
        Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = CleanScanner(environment: LiveEnvironment())
            let result = scanner.scan(
                progress: { update in
                    Task { @MainActor in self?.apply(update) }
                },
                isCancelled: { flag.isCancelled })
            let wasCancelled = flag.isCancelled
            await MainActor.run { self?.finishScan(result, cancelled: wasCancelled) }
        }
    }

    private func finishScan(_ result: ScanReport, cancelled: Bool) {
        refreshDisk()
        if cancelled {
            notice = "Analyse annulée. Rien n'a été modifié."
            report = nil
            phase = .idle
            return
        }
        report = result
        selected = result.defaultSelection
        phase = .ready
    }

    // MARK: - Nettoyage

    func requestClean() {
        guard let r = report else { return }
        let hasReview = r.categories.contains {
            selected.contains($0.id) && $0.definition.risk == .review && $0.totalBytes > 0
        }
        if hasReview {
            showReviewConfirm = true
        } else {
            startClean()
        }
    }

    func startClean() {
        guard let current = report, phase == .ready else { return }
        let selection = selected
        let dry = dryRun
        progress = 0
        statusMessage = "Préparation"
        phase = .cleaning
        showDetails = false
        let flag = CancelFlag()
        cancelFlag = flag
        Task.detached(priority: .userInitiated) { [weak self] in
            let log = OperationLog.defaultLog(home: NSHomeDirectory())
            let engine = CleanEngine(environment: LiveEnvironment(), log: log)
            let result = engine.clean(
                report: current, selection: selection, dryRun: dry,
                progress: { update in
                    Task { @MainActor in self?.apply(update) }
                },
                isCancelled: { flag.isCancelled })
            await MainActor.run { self?.finishClean(result) }
        }
    }

    private func finishClean(_ result: CleanReport) {
        refreshDisk()
        cleanReport = result
        report = nil
        phase = .done
    }

    // MARK: - Corbeille

    func emptyTrash() {
        guard report != nil, !trashBusy else { return }
        trashBusy = true
        trashMessage = nil
        let dry = dryRun
        Task.detached(priority: .userInitiated) { [weak self] in
            let log = OperationLog.defaultLog(home: NSHomeDirectory())
            let engine = CleanEngine(environment: LiveEnvironment(), log: log)
            let result = engine.emptyTrash(dryRun: dry)
            await MainActor.run { self?.finishTrash(result) }
        }
    }

    private func finishTrash(_ result: TrashResult) {
        defer { trashBusy = false }
        if result.requiresFinder {
            if result.dryRun {
                trashMessage = "Simulation : la Corbeille n'est pas mesurable sans autorisation. Rien n'a été vidé."
                return
            }
            let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
            var errorInfo: NSDictionary?
            _ = script?.executeAndReturnError(&errorInfo)
            if errorInfo == nil {
                report?.trash = .empty
                trashMessage = "Corbeille vidée par le Finder."
            } else {
                trashMessage = "La Corbeille n'a pas pu être vidée. Autorisez CLEAN à contrôler le Finder dans Réglages Système > Confidentialité et sécurité > Automatisation."
            }
            refreshDisk()
            return
        }
        if result.dryRun {
            trashMessage = "Simulation : \(Fmt.bytes(result.removedBytes)) seraient libérés. Rien n'a été supprimé."
            return
        }
        var text = "\(Fmt.bytes(result.removedBytes)) libérés depuis la Corbeille."
        if result.skippedCount > 0 { text += " \(result.skippedCount) élément(s) ignoré(s) par sécurité." }
        if result.failedCount > 0 { text += " \(result.failedCount) élément(s) n'ont pas pu être supprimés." }
        trashMessage = text
        if result.failedCount == 0 && result.skippedCount == 0 { report?.trash = .empty }
        refreshDisk()
    }

    // MARK: - Finder

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openLogFolder() {
        let log = OperationLog.defaultLog(home: NSHomeDirectory())
        let dir = log.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
