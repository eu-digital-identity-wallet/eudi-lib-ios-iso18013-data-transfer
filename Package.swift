// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MdocDataTransfer18013",
	platforms: [.macOS(.v12), .iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MdocDataTransfer18013",
            targets: ["MdocDataTransfer18013"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"), 
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-data-model.git", exact: "0.3.3"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-security.git", exact: "0.2.6"),
	],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MdocDataTransfer18013", dependencies: [
                .product(name: "MdocDataModel18013", package: "eudi-lib-ios-iso18013-data-model"),
				.product(name: "MdocSecurity18013", package: "eudi-lib-ios-iso18013-security")]),
        .testTarget(
            name: "MdocDataTransfer18013Tests",
            dependencies: ["MdocDataTransfer18013"]),
    ]
)
