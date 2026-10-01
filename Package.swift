// swift-tools-version: 6.2
import PackageDescription

var products: [Product] = [
    .executable(name: "kohai-hook", targets: ["kohai-hook"]),
]

var targets: [Target] = [
    .target(name: "KohaiCore"),
    .executableTarget(name: "kohai-hook", dependencies: ["KohaiCore"]),
    .testTarget(
        name: "KohaiCoreTests",
        dependencies: ["KohaiCore"],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(
        name: "KohaiHookTests",
        dependencies: ["KohaiCore", "kohai-hook"]
    ),
]

// The menu bar app needs AppKit/SwiftUI, so it only exists when the manifest is
// evaluated on macOS. Core and hook stay buildable elsewhere.
#if os(macOS)
products.append(.executable(name: "Kohai", targets: ["Kohai"]))
targets.append(.executableTarget(
    name: "Kohai",
    dependencies: ["KohaiCore"],
    // The design system (built separately, not yet integrated) lives here too; keep it out of M1.
    exclude: ["Design", "Views", "Previews"]
))
#endif

let package = Package(
    name: "Kohai",
    platforms: [.macOS(.v26)],
    products: products,
    targets: targets
)
