// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MdocDataTransfer18013",
	platforms: [.macOS(.v12), .iOS("13.1")],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MdocDataTransfer18013",
            targets: ["MdocDataTransfer18013"]),
    ],
    dependencies: [
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-security.git", branch: "develop"),
		.package(url: "https://github.com/apple/swift-log.git", branch: "main"),
		.package(url: "https://github.com/valpackett/SwiftCBOR.git", branch: "master"),
	],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MdocDataTransfer18013", dependencies: [
				.product(name: "MdocSecurity18013", package: "eudi-lib-ios-iso18013-security"),
				.product(name: "Logging", package: "swift-log"),
				"SwiftCBOR"]),
        .testTarget(
            name: "MdocDataTransfer18013Tests",
            dependencies: ["MdocDataTransfer18013"]),
    ]
)
