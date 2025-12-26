// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "RSDatabase",
	platforms: [.macOS(.v15), .iOS(.v17)],
	products: [
		.library(
			name: "RSDatabase",
			type: .dynamic,
			targets: ["RSDatabase"]),
		.library(
			name: "RSDatabaseObjC",
			type: .dynamic,
			targets: ["RSDatabaseObjC"]),
	],
	dependencies: [
		.package(path: "../RSCore"),
	],
	targets: [
		.target(
			name: "RSDatabase",
			dependencies: ["RSCore", "RSDatabaseObjC"],
			swiftSettings: [
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
			]
		),
		.target(
			name: "RSDatabaseObjC",
			dependencies: []
		),
		.testTarget(
			name: "RSDatabaseTests",
			dependencies: ["RSDatabase"]),
	]
)
