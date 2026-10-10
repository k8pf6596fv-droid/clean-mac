import Foundation
import Darwin

public enum SafetyVerdict: Equatable, Sendable {
    case allowed
    case denied(String)

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Dernier rempart avant toute suppression.
/// Règles : on ne supprime que des ENFANTS DIRECTS d'un dossier racine autorisé,
/// jamais la racine elle-même, jamais un lien symbolique, jamais hors du dossier personnel
/// (hors dossier temporaire de l'utilisateur), jamais dans une zone protégée.
public struct SafetyGuard: Sendable {
    public let home: String
    public let extraRoots: [String]

    public init(home: String, extraRoots: [String] = []) {
        self.home = SafetyGuard.stripTrailingSlash(home)
        self.extraRoots = extraRoots.map { SafetyGuard.stripTrailingSlash($0) }
    }

    static func stripTrailingSlash(_ p: String) -> String {
        var s = p
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// Zones qui ne peuvent jamais être une racine de nettoyage.
    static let protectedHomeSubpaths: [String] = [
        "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
        "Library/Mobile Documents", "Library/CloudStorage", "Library/Keychains", "Library/Cookies",
        "Library/Photos", "Library/Messages", "Library/Mail", "Library/Safari", "Library/Accounts",
        "Library/Calendars", "Library/Preferences", "Library/Application Support",
        "Library/Containers", "Library/Group Containers",
        "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator",
        ".ssh", ".gnupg", ".aws", ".config"
    ]

    /// Noms d'éléments qui ne doivent jamais être supprimés (ni contenus dans un élément supprimé).
    public static func isProtectedName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let exact: Set<String> = [
            "cookies", "cookies.binarycookies", "cookies.sqlite", "keychains", "mobilesync",
            "mobile documents", "login data", "backups.backupdb", "com~apple~clouddocs"
        ]
        if exact.contains(lower) { return true }
        let suffixes = [
            ".photoslibrary", ".keychain", ".keychain-db", ".backupdb", ".sparsebundle",
            ".sparseimage", ".tmbackup", ".icloud", ".kdbx"
        ]
        return suffixes.contains { lower.hasSuffix($0) }
    }

    static func isNormalized(_ p: String) -> Bool {
        let parts = p.components(separatedBy: "/")
        return !parts.dropFirst().contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private func rootProblem(_ root: String) -> String? {
        if extraRoots.contains(root) { return nil }
        guard root.hasPrefix(home + "/") else { return "Dossier racine hors du dossier personnel" }
        for sub in SafetyGuard.protectedHomeSubpaths {
            let p = home + "/" + sub
            if root == p || root.hasPrefix(p + "/") { return "Zone protégée (\(sub))" }
        }
        return nil
    }

    /// Contrôles purement textuels (aucun accès disque).
    public func validate(path: String, allowedRoot: String) -> SafetyVerdict {
        guard path.hasPrefix("/"), allowedRoot.hasPrefix("/") else { return .denied("Chemin non absolu") }
        if !SafetyGuard.isNormalized(path) || !SafetyGuard.isNormalized(allowedRoot) {
            return .denied("Chemin non normalisé")
        }
        if let why = rootProblem(allowedRoot) { return .denied(why) }
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        if parent != allowedRoot { return .denied("Hors du dossier autorisé") }
        if name.isEmpty || name == "." || name == ".." { return .denied("Nom invalide") }
        if SafetyGuard.isProtectedName(name) { return .denied("Élément protégé (\(name))") }
        return .allowed
    }

    /// Contrôles sur le disque : lien symbolique, propriétaire, parent réel, volume.
    public func validateOnDisk(path: String, allowedRoot: String, allowSymlinkLeaf: Bool = false) -> SafetyVerdict {
        guard let info = FileInfo.at(path) else { return .denied("Introuvable") }
        if info.isSymlink && !allowSymlinkLeaf { return .denied("Lien symbolique ignoré") }
        if info.uid != UInt32(getuid()) { return .denied("Appartient à un autre utilisateur") }
        guard let rootInfo = FileInfo.at(allowedRoot), rootInfo.isDirectory, !rootInfo.isSymlink else {
            return .denied("Dossier racine invalide")
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard let rootReal = FileInfo.realPath(allowedRoot),
              let parentReal = FileInfo.realPath(parent),
              rootReal == parentReal else {
            return .denied("Dossier parent modifié")
        }
        if info.device != rootInfo.device { return .denied("Autre volume") }
        return .allowed
    }
}
