// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhoopMetrics",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "WhoopMetrics", targets: ["WhoopMetrics"])],
    dependencies: [
        .package(path: "../WhoopStore"),
        .package(path: "../WhoopProtocol"),
    ],
    targets: [
        .target(
            name: "WhoopMetrics",
            dependencies: ["WhoopStore", "WhoopProtocol"]
        ),
        .testTarget(
            name: "WhoopMetricsTests",
            dependencies: ["WhoopMetrics", "WhoopStore", "WhoopProtocol"]
        ),
    ]
)
