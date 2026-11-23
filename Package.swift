// swift-tools-version: 6.3.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MdocDataTransfer18013",
	platforms: [.macOS(.v15), .iOS(.v17), .watchOS(.v10)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MdocDataTransfer18013",
            targets: ["MdocDataTransfer18013"]),
    ],
    dependencies: [
		// workaround for secp256k1 dependency (https://github.com/beatt83/jose-swift/issues/71)
		.package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", exact: "0.24.0"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-security", exact: "0.32.1"),
		.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MdocDataTransfer18013", dependencies: [
				.product(name: "MdocSecurity18013", package: "eudi-lib-ios-iso18013-security"),
			]),
        .testTarget(
            name: "MdocDataTransfer18013Tests",
            dependencies: ["MdocDataTransfer18013"]),
    ]
)
