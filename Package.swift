// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SingBoxManager",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .executable(name: "SingBoxManager", targets: ["SingBoxManager"]),
        .library(name: "SingBoxManagerLib", targets: ["SingBoxManagerLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "SingBoxManager",
            dependencies: ["SingBoxManagerLib"],
            path: "Sources/CLI"
        ),
        .target(
            name: "SingBoxManagerLib",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Sources/Library"
        ),
        .testTarget(
            name: "SingBoxManagerTests",
            dependencies: ["SingBoxManagerLib"],
            path: "Tests"
        )
    ]
)
