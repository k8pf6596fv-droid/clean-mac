import Foundation

/// Accès aux informations du système. Isolé derrière un protocole pour pouvoir tester le moteur.
public protocol SystemEnvironment: Sendable {
    var homeDirectory: String { get }
    var temporaryDirectory: String { get }
    var now: Date { get }
    func isAppInstalled(bundleIdentifier: String) -> Bool
    func runningBundleIdentifiers() -> Set<String>
}

public struct ProgressUpdate: Sendable {
    public let fraction: Double
    public let message: String
    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}
