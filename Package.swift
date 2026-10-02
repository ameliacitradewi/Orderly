// swift-tools-version: 6.2
import PackageDescription

// Test the same non-UI sources used by the Xcode app.
// The package target matches the app's macOS 27 deployment requirement for PCC.
let package = Package(
    name: "OrderlyCore",
    platforms: [.macOS("27.0")],
    products: [.library(name: "OrderlyCore", targets: ["OrderlyCore"])],
    targets: [
        .target(name: "OrderlyCore", path: "Orderly",
                exclude: [
                    "AI/ContectBuilder.swift",
                    "AI/Untitled.swift",
                    "App",
                    "Assets.xcassets",
                    "DesignSystem",
                    "UI"
                ],
                sources: [
                    "Agent",
                    "AI/LLMService.swift",
                    "Content",
                    "FileSystem",
                    "FoundationModel",
                    "Intelligence",
                    "Models",
                    "Tools"
                ],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "OrderlyCoreTests", dependencies: ["OrderlyCore"], path: "Tests/OrderlyCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
