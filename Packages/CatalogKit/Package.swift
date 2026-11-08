// swift-tools-version: 6.2
// 6.2 is the first compiler that knows `@concurrent` (Images); an older Xcode then says so instead of failing
// on the attribute.
import PackageDescription

let package = Package(
    name: "CatalogKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CatalogKit", targets: ["Catalog", "Networking", "Images", "DesignSystem", "Persistence"])
    ],
    targets: [
        .target(name: "Networking", path: "Sources/Core/Networking"),
        .target(name: "Images", path: "Sources/Core/Images"),
        .target(name: "DesignSystem", dependencies: ["Images"], path: "Sources/Core/DesignSystem"),
        .target(name: "Persistence", path: "Sources/Core/Persistence"),
        .target(name: "Catalog", dependencies: ["Networking", "DesignSystem"], path: "Sources/Features/Catalog"),
        .testTarget(name: "NetworkingTests", dependencies: ["Networking"]),
        .testTarget(name: "ImagesTests", dependencies: ["Images"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
        .testTarget(name: "CatalogTests", dependencies: ["Catalog", "Networking"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
