import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore

// Mapbox zoom is offset by +1.0 from "Google-style" zoom (same as MapLibre).
internal let mapboxCameraZoomAdjustValue = 1.0

public extension MapCameraPosition {
    /// Convert to Mapbox CameraOptions with adjusted zoom.
    func toMapboxCameraOptions() -> CameraOptions {
        CameraOptions(
            center: CLLocationCoordinate2D(
                latitude: position.latitude,
                longitude: position.longitude
            ),
            zoom: adjustedZoomForMapbox(),
            bearing: bearing,
            pitch: tilt
        )
    }

    /// Returns the adjusted zoom level for Mapbox SDK.
    func adjustedZoomForMapbox() -> Double {
        max(zoom - mapboxCameraZoomAdjustValue, 0.0)
    }
}

public extension CameraState {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition {
        MapCameraPosition(
            position: GeoPoint(
                latitude: center.latitude,
                longitude: center.longitude,
                altitude: 0
            ),
            zoom: zoom + mapboxCameraZoomAdjustValue,
            bearing: bearing,
            tilt: pitch,
            visibleRegion: visibleRegion
        )
    }
}
