import Foundation

public enum CategoryCatalog {
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 86_400

    public static func temporaryRoot(_ env: SystemEnvironment) -> String {
        SafetyGuard.stripTrailingSlash(env.temporaryDirectory)
    }

    /// Ordre important : une catégorie « revendique » ses éléments avant les suivantes (anti double comptage).
    public static func definitions(for env: SystemEnvironment) -> [CategoryDefinition] {
        let h = SafetyGuard.stripTrailingSlash(env.homeDirectory)
        return [
            CategoryDefinition(
                id: .xcode, title: "Xcode et Swift",
                detail: "Données de compilation et caches de paquets, recréés automatiquement.",
                symbol: "hammer", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Developer/Xcode/DerivedData", h + "/Library/Caches/org.swift.swiftpm"],
                minimumAge: day, blockedWhileRunning: ["com.apple.dt.Xcode"], reservedNames: []),
            CategoryDefinition(
                id: .npm, title: "Cache npm",
                detail: "Paquets téléchargés, retéléchargés au besoin.",
                symbol: "shippingbox", risk: .safe, selectedByDefault: true,
                roots: [h + "/.npm/_cacache"],
                minimumAge: day, blockedWhileRunning: [], reservedNames: []),
            CategoryDefinition(
                id: .pnpm, title: "Cache pnpm",
                detail: "Métadonnées mises en cache, recréées automatiquement.",
                symbol: "shippingbox", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Caches/pnpm"],
                minimumAge: day, blockedWhileRunning: [], reservedNames: []),
            CategoryDefinition(
                id: .homebrew, title: "Cache Homebrew",
                detail: "Archives téléchargées par Homebrew, retéléchargées au besoin.",
                symbol: "cup.and.saucer", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Caches/Homebrew"],
                minimumAge: day, blockedWhileRunning: [], reservedNames: []),
            CategoryDefinition(
                id: .appLeftovers, title: "Résidus d'applications désinstallées",
                detail: "Caches et états sauvegardés dont l'application semble absente. Origine non garantie : à vérifier.",
                symbol: "app.dashed", risk: .review, selectedByDefault: false,
                roots: [h + "/Library/Caches", h + "/Library/Saved Application State"],
                minimumAge: 0, blockedWhileRunning: [], reservedNames: []),
            CategoryDefinition(
                id: .userCaches, title: "Caches des applications",
                detail: "Fichiers que les applications recréent seules. Les caches Apple et des applications ouvertes sont ignorés.",
                symbol: "archivebox", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Caches"],
                minimumAge: day, blockedWhileRunning: [],
                reservedNames: ["Homebrew", "pnpm", "org.swift.swiftpm"]),
            CategoryDefinition(
                id: .crashReports, title: "Rapports de plantage anciens",
                detail: "Rapports de diagnostic de plus de 30 jours.",
                symbol: "exclamationmark.triangle", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Logs/DiagnosticReports"],
                minimumAge: 30 * day, blockedWhileRunning: [], reservedNames: []),
            CategoryDefinition(
                id: .logs, title: "Journaux anciens",
                detail: "Journaux d'applications inchangés depuis plus de 30 jours.",
                symbol: "doc.text", risk: .safe, selectedByDefault: true,
                roots: [h + "/Library/Logs"],
                minimumAge: 30 * day, blockedWhileRunning: [], reservedNames: ["DiagnosticReports"]),
            CategoryDefinition(
                id: .temporaryFiles, title: "Fichiers temporaires",
                detail: "Fichiers temporaires de votre session inchangés depuis plus de 3 jours.",
                symbol: "timer", risk: .safe, selectedByDefault: true,
                roots: [temporaryRoot(env)],
                minimumAge: 3 * day, blockedWhileRunning: [], reservedNames: [])
        ]
    }

    /// Extrait un identifiant d'application d'un nom de dossier (« com.exemple.app » ou « …savedState »).
    public static func bundleIdentifier(fromEntryName name: String) -> String? {
        var n = name
        let suffix = ".savedState"
        if n.hasSuffix(suffix) { n = String(n.dropLast(suffix.count)) }
        let parts = n.components(separatedBy: ".")
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard n.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return n
    }
}
