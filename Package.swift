// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ios-for-mapbox",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MapConductorForMapbox",
            targets: ["MapConductorForMapbox"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/MapConductor/ios-sdk-core", from: "1.0.0"),
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
