// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DNSClient",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "DNSClient",
            targets: [
                "DNSClient"
            ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "DNSProtocol",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .target(
            name: "DNSClient",
            dependencies: [
                "DNSProtocol",
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .target(
            name: "DNSServer",
            dependencies: [
                "DNSProtocol",
                .product(name: "NIO", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "DNSClientTests",
            dependencies: [
                .target(name: "DNSClient"),
                .target(name: "DNSServer"),
                .product(name: "NIO", package: "swift-nio"),
            ]),
    ]
)
