// swift-tools-version:4.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NioDNS",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "NioDNS",
            targets: ["NioDNS"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-nio.git", from: "1.9.5"),
        .package(url: "https://github.com/Joannis/cResolv.git", from: "0.2.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
//        .systemLibrary(name: "CResolv", path: "/usr/lib/resolv/"),
        .target(
            name: "NioDNS",
            dependencies: ["NIO", "CResolvHelpers"]),
        .target(name: "CResolvHelpers"),
        .testTarget(
            name: "NioDNSTests",
            dependencies: ["NioDNS"]),
    ]
)
