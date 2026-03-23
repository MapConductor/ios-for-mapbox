import Foundation
import MapConductorCore

/// Zoom offset: GoogleZoom ≈ MapboxSDK.zoom + 1.0 (same as MapLibre)
let mapboxToGoogleZoomOffset = 1.0

extension ZoomAltitudeConverterProtocol where Self == MapboxZoomAltitudeConverter {
    public static var mapbox: MapboxZoomAltitudeConverter { MapboxZoomAltitudeConverter() }
}

public class MapboxZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    private let minZoomLevel: Double = 0.0
    private let maxZoomLevel: Double = 22.0
    private let minAltitude: Double = 100.0
    private let maxAltitude: Double = 50_000_000.0
    private let minCosLat: Double = 0.01
    private let minCosTilt: Double = 0.05

    public init(zoom0Altitude: Double = 171_319_879.0) {
        self.zoom0Altitude = zoom0Altitude
    }

    public static func mapboxZoomToGoogleZoom(_ zoom: Double) -> Double {
        (zoom + mapboxToGoogleZoomOffset).clamped(to: 0...22)
    }

    public static func googleZoomToMapboxZoom(_ zoom: Double) -> Double {
        (zoom - mapboxToGoogleZoomOffset).clamped(to: 0...22)
    }

    public func zoomLevelToAltitude(
        zoomLevel: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        let clampedZoom = max(minZoomLevel, min(zoomLevel, maxZoomLevel))

        let clampedLat = max(-85.0, min(latitude, 85.0))
        let latitudeRadians = clampedLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let clampedTilt = max(0.0, min(tilt, 90.0))
        let tiltRadians = clampedTilt * .pi / 180.0
        let cosTilt = max(cos(tiltRadians), minCosTilt)

        let distance = (zoom0Altitude * cosLat) / pow(2.0, clampedZoom)
        let altitude = distance * cosTilt

        return max(minAltitude, min(altitude, maxAltitude))
    }

    public func altitudeToZoomLevel(
        altitude: Double,
        latitude: Double,
        tilt: Double
    ) -> Double {
        let clampedAltitude = max(minAltitude, min(altitude, maxAltitude))

        let clampedLat = max(-85.0, min(latitude, 85.0))
        let latitudeRadians = clampedLat * .pi / 180.0
        let cosLat = max(abs(cos(latitudeRadians)), minCosLat)

        let clampedTilt = max(0.0, min(tilt, 90.0))
        let tiltRadians = clampedTilt * .pi / 180.0
        let cosTilt = max(cos(tiltRadians), minCosTilt)

        let distance = clampedAltitude / cosTilt
        let zoomLevel = log2((zoom0Altitude * cosLat) / distance)

        return max(minZoomLevel, min(zoomLevel, maxZoomLevel))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
