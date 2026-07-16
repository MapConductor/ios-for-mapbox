import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore

// Mapbox zoom is offset by +1.0 from "Google-style" zoom (same as MapLibre).
internal let mapboxCameraZoomAdjustValue = 1.0
private let converter = MapboxZoomAltitudeConverter()

public extension MapCameraPosition {
    /// Convert to Mapbox CameraOptions with adjusted zoom.
    func toMapboxCameraOptions() -> CameraOptions {
        if tilt >= 0 {
            return CameraOptions(
                center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
                zoom: MapboxZoomAltitudeConverter.googleZoomToMapboxZoom(zoom),
                bearing: bearing,
                pitch: tilt
            )
        }
        
        // tilt < 0: MapLibre cannot represent upward pitch directly.
        // Move the ground target forward and render with abs(tilt) — mirrors Android workaround.
        let tiltAbsDeg = max(0, min(60, abs(tilt)))
        let tiltAbsRad = tiltAbsDeg * .pi / 180
        let maplibreZoomForAltitude = MapboxZoomAltitudeConverter.googleZoomToMapboxZoom(zoom)
        let altitude = converter.zoomLevelToAltitude(zoomLevel: maplibreZoomForAltitude, latitude: position.latitude, tilt: 0.0)
        let distanceForward = altitude * tan(tiltAbsRad)
        let target = Spherical.computeOffset(origin: position, distance: distanceForward, heading: bearing)
        let mapboxZoom = converter.altitudeToZoomLevel(altitude: altitude/cos(tiltAbsRad), latitude: target.latitude, tilt: 0.0)
        
        return CameraOptions(
            center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            zoom: mapboxZoom,
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
    func toMapCameraPosition(
        logicalTiltHint: Double? = nil,
        visibleRegion: VisibleRegion? = nil
    ) -> MapCameraPosition {
        let pitchAbsDeg = min(abs(pitch), 90.0)
        let shiftedCenter = GeoPoint(latitude: center.latitude, longitude: center.longitude)

        guard let logicalTiltHint, logicalTiltHint < 0.0, pitchAbsDeg > 0.0 else {
            return MapCameraPosition(
                position: shiftedCenter,
                zoom: MapboxZoomAltitudeConverter.mapboxZoomToGoogleZoom(zoom),
                bearing: bearing,
                tilt: pitch,
                visibleRegion: visibleRegion
            )
        }

        let tiltRadians = pitchAbsDeg * .pi / 180.0
        let adjustedAltitude = converter.zoomLevelToAltitude(
            zoomLevel: zoom,
            latitude: shiftedCenter.latitude,
            tilt: 0.0
        )
        let originalAltitude = adjustedAltitude * cos(tiltRadians)
        let originalCenter = Spherical.computeOffset(
            origin: shiftedCenter,
            distance: originalAltitude * tan(tiltRadians),
            heading: bearing + 180.0
        )
        let originalMapboxZoom = converter.altitudeToZoomLevel(
            altitude: originalAltitude,
            latitude: originalCenter.latitude,
            tilt: 0.0
        )

        return MapCameraPosition(
            position: originalCenter,
            zoom: MapboxZoomAltitudeConverter.mapboxZoomToGoogleZoom(originalMapboxZoom),
            bearing: bearing,
            tilt: -pitchAbsDeg,
            visibleRegion: visibleRegion
        )
    }
}
