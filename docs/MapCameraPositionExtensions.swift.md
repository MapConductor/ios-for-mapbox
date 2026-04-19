# MapCameraPositionExtensions

Extensions that convert between the SDK's `MapCameraPosition` type and Mapbox camera types.

---

# MapCameraPosition extension

## `toMapboxCameraOptions()`

Converts a `MapCameraPosition` to a Mapbox `CameraOptions` for use with the Mapbox SDK.

### Signature

```swift
public extension MapCameraPosition {
    func toMapboxCameraOptions() -> CameraOptions
}
```

### Returns

- Type: `CameraOptions`
- Description: A Mapbox camera options value with center, zoom, bearing, and pitch derived from
  the `MapCameraPosition`. Zoom is adjusted by subtracting `1.0` (Mapbox offset).

---

## `adjustedZoomForMapbox()`

Returns the zoom level adjusted for Mapbox's zoom coordinate system.

### Signature

```swift
public extension MapCameraPosition {
    func adjustedZoomForMapbox() -> Double
}
```

### Returns

- Type: `Double`
- Description: `zoom - 1.0`. Mapbox zoom levels are one unit lower than Google Maps zoom levels
  for the same visual scale.

---

# CameraState extension

## `toMapCameraPosition(visibleRegion:)`

Converts a Mapbox `CameraState` to a `MapCameraPosition`. Zoom is adjusted by adding `1.0`.

### Signature

```swift
public extension CameraState {
    func toMapCameraPosition(visibleRegion: VisibleRegion? = nil) -> MapCameraPosition
}
```

### Parameters

- `visibleRegion`
    - Type: `VisibleRegion?`
    - Default: `nil`
    - Description: The visible map region. When provided, the resulting `MapCameraPosition`
      includes accurate `visibleRegion` bounds.

### Returns

- Type: `MapCameraPosition`
- Description: A `MapCameraPosition` with zoom = `cameraState.zoom + 1.0`.
