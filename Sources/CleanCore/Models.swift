import Foundation

public enum RiskLevel: String, Sendable, Codable {
    case safe
    case review
}

public enum CategoryID: String, Sendable, Codable, CaseIterable, Hashable {
    case xcode, npm, pnpm, homebrew, appLeftovers, userCaches, crashReports, logs, temporaryFiles
}

public struct CategoryDefinition: Sendable, Identifiable {
    public let id: CategoryID
    public let title: String
    public let detail: String
    public let symbol: String
    public let risk: RiskLevel
    public let selectedByDefault: Bool
    /// Dossiers dont seuls les ENFANTS DIRECTS peuvent être nettoyés.
    public let roots: [String]
    /// Un élément modifié depuis moins longtemps que cela est ignoré.
    public let minimumAge: TimeInterval
    /// Si l'une de ces applications est ouverte, la catégorie est ignorée.
    public let blockedWhileRunning: [String]
    /// Noms d'enfants réservés à une autre catégorie (évite le double comptage).
    public let reservedNames: Set<String>
}

public struct CleanItem: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let categoryID: CategoryID
    public let rootPath: String
    public let sizeBytes: Int64
    public let fileCount: Int
    public let newestModification: Date
}

public struct SkippedItem: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let reason: String
}

public struct CategoryResult: Sendable, Identifiable {
    public let definition: CategoryDefinition
    public var items: [CleanItem]
    public var skipped: [SkippedItem]
    public var notice: String?
    public var id: CategoryID { definition.id }
    public var totalBytes: Int64 { items.reduce(Int64(0)) { $0 + $1.sizeBytes } }
}

/// Éléments volumineux à examiner : JAMAIS supprimés par CLEAN.
public struct ReviewSuggestion: Sendable, Identifiable {
    public var id: String { path }
    public let title: String
    public let detail: String
    public let path: String
    public let bytes: Int64
}

public enum TrashState: Sendable, Equatable {
    case empty
    case measured(bytes: Int64, itemCount: Int)
    case unavailable(String)
}

public struct DiskUsage: Sendable, Equatable {
    public let totalBytes: Int64
    /// Espace réellement libre.
    public let availableBytes: Int64
    /// Espace libre + espace purgeable que macOS libère à la demande (valeur affichée par Réglages Système).
    public let availableWithPurgeableBytes: Int64
    public var usedBytes: Int64 { max(0, totalBytes - availableWithPurgeableBytes) }
    public var purgeableBytes: Int64 { max(0, availableWithPurgeableBytes - availableBytes) }
    public var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

public struct ScanReport: Sendable {
    public var categories: [CategoryResult]
    public var suggestions: [ReviewSuggestion]
    public var trash: TrashState
    public var disk: DiskUsage?
    public var warnings: [String]
    public var cancelled: Bool
    public var scannedAt: Date

    public func bytes(for selection: Set<CategoryID>) -> Int64 {
        categories.filter { selection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    public var safeBytes: Int64 {
        categories.filter { $0.definition.risk == .safe }.reduce(Int64(0)) { $0 + $1.totalBytes }
    }

    public var defaultSelection: Set<CategoryID> {
        Set(categories.filter { $0.definition.selectedByDefault && $0.totalBytes > 0 }.map { $0.id })
    }
}

public enum OutcomeStatus: Sendable, Equatable {
    case removed, simulated, skipped, failed
}

public struct CleanOutcome: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let categoryID: CategoryID
    public let status: OutcomeStatus
    public let bytes: Int64
    public let message: String?
}

public struct CleanReport: Sendable {
    public var outcomes: [CleanOutcome]
    public var dryRun: Bool
    public var availableBefore: Int64?
    public var availableAfter: Int64?
    public var duration: TimeInterval
    public var cancelled: Bool

    /// Octets réellement supprimés (y compris suppression partielle d'un élément en échec).
    public var removedBytes: Int64 {
        outcomes.filter { $0.status == .removed || $0.status == .failed }.reduce(Int64(0)) { $0 + $1.bytes }
    }
    public var simulatedBytes: Int64 {
        outcomes.filter { $0.status == .simulated }.reduce(Int64(0)) { $0 + $1.bytes }
    }
    public func count(_ status: OutcomeStatus) -> Int {
        outcomes.filter { $0.status == status }.count
    }
    /// Variation mesurée de l'espace libre (peut différer de removedBytes : purgeable, snapshots, activité du système).
    public var measuredDelta: Int64? {
        guard let b = availableBefore, let a = availableAfter else { return nil }
        return a - b
    }
}

public struct TrashResult: Sendable {
    public var removedBytes: Int64 = 0
    public var removedCount: Int = 0
    public var skippedCount: Int = 0
    public var failedCount: Int = 0
    public var requiresFinder: Bool = false
    public var dryRun: Bool = false
    public var message: String? = nil
}
