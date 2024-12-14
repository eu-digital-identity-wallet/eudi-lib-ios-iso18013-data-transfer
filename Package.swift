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
        .package(path: "../eudi-lib-ios-iso18013-security"),
		//.package(path: "../eudi-lib-ios-wallet-storage"),
        //.package(path: "../eudi-lib-sdjwt-swift"),
		//.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-wallet-storage.git", exact: "0.4.1"),
		//.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-security.git", exact: "0.3.1"),
	    // .package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-sdjwt-swift.git", exact: "0.3.2"),
],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MdocDataTransfer18013", dependencies: [
				.product(name: "MdocSecurity18013", package: "eudi-lib-ios-iso18013-security")]),
				//.product(name: "WalletStorage", package: "eudi-lib-ios-wallet-storage"),
                //.product(name: "eudi-lib-sdjwt-swift", package: "eudi-lib-sdjwt-swift")]),
        .testTarget(
            name: "MdocDataTransfer18013Tests",
            dependencies: ["MdocDataTransfer18013"]),
    ]
)
