// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Magritte",
    products: [.library(name: "Magritte", targets: ["Magritte"])],
    targets: [
        .target(name: "Magritte"),
        .testTarget(name: "MagritteTests", dependencies: ["Magritte"], resources: [.copy("Fixtures")])
    ]
)
