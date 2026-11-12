import CoreLocation
import Foundation
import UIKit
import MapboxMaps
@_spi(MapConductorDriver) import MapConductorCore

// Mapbox zoom is offset by +1.0 from "Google-style" zoom (same as MapLibre).
internal let mapboxCameraZoomAdjustValue = 1.0
private let converter = MapboxZoomAltitudeConverter()

/// Mapbox のカメラの縦の視野角（度）。Mapbox Maps の既定値（`2·atan(1/3)`）で、
/// iPad Pro 11 の実測（tilt 30°〜60°）でも一致した。
let mapboxVerticalFieldOfView: Double = 36.87

public extension MapCameraPosition {
    /// Convert to Mapbox CameraOptions with adjusted zoom.
    func toMapboxCameraOptions() -> CameraOptions {
        // パディングは CameraOptions.padding には当てない（常に 0 で、以前のパディングも消す）。
        // tilt があると上のパディングが視野を地平線の向こうまで広げて固まるので、
        // コントローラが中心をずらして再現する（``CameraPaddingEmulation``）。
        let padding = UIEdgeInsets.zero
        if tilt >= 0 {
            return CameraOptions(
                center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
                padding: padding,
                zoom: MapboxZoomAltitudeConverter.googleZoomToMapboxZoom(zoom),
                bearing: CameraBearing.toNativeHeading(bearing),
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
        let target = Spherical.computeOffset(origin: position, distance: distanceForward, heading: CameraBearing.toNativeHeading(bearing))
        let mapboxZoom = converter.altitudeToZoomLevel(altitude: altitude/cos(tiltAbsRad), latitude: target.latitude, tilt: 0.0)
        
        return CameraOptions(
            center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
            padding: padding,
            zoom: mapboxZoom,
            bearing: CameraBearing.toNativeHeading(bearing),
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
                bearing: CameraBearing.bearingFromNativeHeading(bearing),
                tilt: pitch,
                visibleRegion: visibleRegion,
                fov: mapboxVerticalFieldOfView
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
            bearing: CameraBearing.bearingFromNativeHeading(bearing),
            tilt: -pitchAbsDeg,
            visibleRegion: visibleRegion,
            fov: mapboxVerticalFieldOfView
        )
    }
}
