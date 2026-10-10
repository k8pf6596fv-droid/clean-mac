// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Clean",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Clean", targets: ["Clean"])
    ],
    targets: [
        // Moteur d'analyse, de classification, de sécurité et de suppression (sans interface).
        .target(name: "CleanCore", path: "Sources/CleanCore"),
        // Application SwiftUI.
        .executableTarget(name: "Clean", dependencies: ["CleanCore"], path: "Sources/Clean"),
        // Tests unitaires du moteur.
        .testTarget(name: "CleanCoreTests", dependencies: ["CleanCore"], path: "Tests/CleanCoreTests")
    ]
)
