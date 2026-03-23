import Foundation
import MapConductorCore

public protocol MapboxMapDesignTypeProtocol: MapDesignTypeProtocol where Identifier == String {
    var styleURI: String { get }
}

public typealias MapboxMapDesignType = any MapboxMapDesignTypeProtocol

public struct MapboxMapDesign: MapboxMapDesignTypeProtocol, Hashable {
    public let id: String
    public let styleURI: String

    private static let mapboxBaseURL = "mapbox://styles/mapbox"

    public init(id: String, styleURI: String) {
        self.id = id
        self.styleURI = styleURI
    }

    public func getValue() -> String { styleURI }

    // Mapbox built-in styles
    public static let Standard = MapboxMapDesign(
        id: "standard",
        styleURI: "\(mapboxBaseURL)/standard"
    )
    public static let StandardSatellite = MapboxMapDesign(
        id: "standard-satellite",
        styleURI: "\(mapboxBaseURL)/standard-satellite"
    )
    public static let Streets = MapboxMapDesign(
        id: "streets-v12",
        styleURI: "\(mapboxBaseURL)/streets-v12"
    )
    public static let Outdoors = MapboxMapDesign(
        id: "outdoors-v12",
        styleURI: "\(mapboxBaseURL)/outdoors-v12"
    )
    public static let Light = MapboxMapDesign(
        id: "light-v11",
        styleURI: "\(mapboxBaseURL)/light-v11"
    )
    public static let Dark = MapboxMapDesign(
        id: "dark-v11",
        styleURI: "\(mapboxBaseURL)/dark-v11"
    )
    public static let Satellite = MapboxMapDesign(
        id: "satellite-v9",
        styleURI: "\(mapboxBaseURL)/satellite-v9"
    )
    public static let SatelliteStreets = MapboxMapDesign(
        id: "satellite-streets-v12",
        styleURI: "\(mapboxBaseURL)/satellite-streets-v12"
    )
    public static let NavigationDay = MapboxMapDesign(
        id: "navigation-day-v1",
        styleURI: "\(mapboxBaseURL)/navigation-day-v1"
    )
    public static let NavigationNight = MapboxMapDesign(
        id: "navigation-night-v1",
        styleURI: "\(mapboxBaseURL)/navigation-night-v1"
    )

    public static func custom(styleURI: String) -> MapboxMapDesign {
        MapboxMapDesign(id: styleURI, styleURI: styleURI)
    }
}
