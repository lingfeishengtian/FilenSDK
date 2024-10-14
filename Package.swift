// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FilenSDK",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FilenSDK",
            targets: ["FilenSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", .upToNextMajor(from: "5.9.1")),
        .package(url: "https://github.com/krzyzanowskim/OpenSSL", .upToNextMajor(from: "3.3.2000")),
        .package(url: "https://github.com/orlandos-nl/IkigaJSON", .upToNextMajor(from: "2.2.3")),
        .package(url: "https://github.com/TakeScoop/SwiftyRSA", .upToNextMajor(from: "1.8.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FilenSDK",
            dependencies: ["Alamofire", "OpenSSL", "IkigaJSON", "SwiftyRSA"]),
        .testTarget(
            name: "FilenSDKTests",
            dependencies: ["FilenSDK"],
            resources: [
                .copy("TestResources/config.json")
            ]
        ),
    ]
)
