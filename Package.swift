// swift-tools-version: 6.2
import PackageDescription

// Test the same non-UI sources used by the Xcode app, without requiring Apple Intelligence
// to generate responses. The app's macOS 26.5 deployment target is preserved.
let package = Package(
    name: "OrderlyCore",
    platforms: [.macOS("26.5")],
    products: [.library(name: "OrderlyCore", targets: ["OrderlyCore"])],
    targets: [
        .target(name: "OrderlyCore", path: "Orderly",
                exclude: ["AI", "App", "Assets.xcassets", "DesignSystem", "UI"],
                sources: ["FileSystem", "FoundationModel", "Intelligence", "Models"],
                swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "OrderlyCoreTests", dependencies: ["OrderlyCore"], path: "Tests/OrderlyCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
