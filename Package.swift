// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MdocDataTransfer18013",
	platforms: [.iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MdocDataTransfer18013",
            targets: ["MdocDataTransfer18013"]),
    ],
    dependencies: [
		.package(path: "../MdocDataModel18013"),
		.package(url: "https://github.com/StarryInternet/CombineCoreBluetooth.git", from: "0.3.0"),
	],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MdocDataTransfer18013", dependencies: ["MdocDataModel18013"]),
        .testTarget(
            name: "MdocDataTransfer18013Tests",
            dependencies: ["MdocDataTransfer18013", "CombineCoreBluetooth"]),
    ]
)
