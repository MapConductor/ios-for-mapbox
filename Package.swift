// swift-tools-version: 5.9
import Foundation
import PackageDescription

let frameworkLibraryType: Product.Library.LibraryType? =
    ProcessInfo.processInfo.environment["MAPCONDUCTOR_BUILD_XCFRAMEWORK"] == "1" ? .dynamic : nil
let usingLocalCore = FileManager.default.fileExists(atPath: "../ios-sdk-core/Package.swift")
let coreDependency: Package.Dependency = usingLocalCore
    ? .package(path: "../ios-sdk-core")
    : .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.1.4")

let package = Package(
    name: "ios-for-mapbox",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MapConductorForMapbox",
            type: frameworkLibraryType,
            targets: ["MapConductorForMapbox"]
        ),
    ],
    dependencies: [
        coreDependency,
        .package(url: "https://github.com/mapbox/mapbox-maps-ios-binary", from: "11.0.0"),
    ],
    targets: [
        .target(
            name: "MapConductorForMapbox",
            dependencies: [
                .product(name: "MapConductorCore", package: "ios-sdk-core"),
                .product(name: "MapboxMaps", package: "mapbox-maps-ios-binary"),
            ]
        ),
    ]
)
