// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StockWatch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StockWatch", targets: ["StockWatch"]),
        .library(name: "StockWatchCore", targets: ["StockWatchCore"]),
    ],
    targets: [
        .target(
            name: "StockWatchCore"
        ),
        .executableTarget(
            name: "StockWatch",
            dependencies: ["StockWatchCore"]
        ),
        .testTarget(
            name: "StockWatchTests",
            dependencies: ["StockWatchCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
