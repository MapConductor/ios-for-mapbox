# MapboxZoomAltitudeConverter

Converts between Mapbox zoom levels and the altitude-based camera model used internally by the
SDK. Implements `ZoomAltitudeConverterProtocol`.

Mapbox zoom levels are offset by `-1.0` relative to Google Maps zoom levels:
- `mapboxZoom = googleZoom - 1.0`
- `googleZoom = mapboxZoom + 1.0`

The converter applies this offset internally, so callers work in Google-style zoom units.

## Signature

```swift
public class MapboxZoomAltitudeConverter: ZoomAltitudeConverterProtocol {
    public let zoom0Altitude: Double

    public init(zoom0Altitude: Double = 171_319_879.0)
}
```

## Constructor Parameters

- `zoom0Altitude`
    - Type: `Double`
    - Default: `171_319_879.0`
    - Description: The reference altitude (in meters) at zoom level 0 near the equator.

## Methods

### `zoomLevelToAltitude(zoomLevel:latitude:tilt:)`

Converts a Google-style zoom level to an altitude in meters.

```swift
public func zoomLevelToAltitude(
    zoomLevel: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

### `altitudeToZoomLevel(altitude:latitude:tilt:)`

Converts an altitude in meters to a Google-style zoom level.

```swift
public func altitudeToZoomLevel(
    altitude: Double,
    latitude: Double,
    tilt: Double
) -> Double
```

## Static Helper Methods

### `mapboxZoomToGoogleZoom(_:)`

Adds the offset to convert a Mapbox zoom level to Google-style zoom.

```swift
public static func mapboxZoomToGoogleZoom(_ mapboxZoom: Double) -> Double
// returns mapboxZoom + 1.0
```

### `googleZoomToMapboxZoom(_:)`

Subtracts the offset to convert a Google-style zoom to a Mapbox zoom level.

```swift
public static func googleZoomToMapboxZoom(_ googleZoom: Double) -> Double
// returns googleZoom - 1.0
```

## Extensions

A convenience `.mapbox` shortcut is available on `ZoomAltitudeConverterProtocol`:

```swift
extension ZoomAltitudeConverterProtocol where Self == MapboxZoomAltitudeConverter {
    public static var mapbox: MapboxZoomAltitudeConverter { MapboxZoomAltitudeConverter() }
}
```

## Example

```swift
let converter = MapboxZoomAltitudeConverter()

// Convert Google zoom 14 to altitude
let altitude = converter.zoomLevelToAltitude(zoomLevel: 14, latitude: 35.0, tilt: 0)

// Convert back
let zoom = converter.altitudeToZoomLevel(altitude: altitude, latitude: 35.0, tilt: 0)
// zoom ≈ 14.0 (Google-style)

// Zoom offset helpers
let mapboxZoom = MapboxZoomAltitudeConverter.googleZoomToMapboxZoom(14.0) // 13.0
let googleZoom = MapboxZoomAltitudeConverter.mapboxZoomToGoogleZoom(13.0) // 14.0
```
