# MapboxViewState

`MapboxViewState` manages the state of a `MapboxMapView`, including the camera position and the
map design type. It is an `ObservableObject` — changes to its published properties automatically
trigger SwiftUI view updates.

Typically held with `@StateObject` in the parent view and passed to `MapboxMapView`.

## Signature

```swift
public final class MapboxViewState: MapViewState<MapboxMapDesignType>
```

## Initializers

### `init(id:mapDesignType:cameraPosition:)`

Creates an instance with an explicit identifier.

```swift
public init(
    id: String,
    mapDesignType: MapboxMapDesignType = MapboxMapDesign.Standard,
    cameraPosition: MapCameraPosition = .Default
)
```

### `init(mapDesignType:cameraPosition:)`

Creates an instance with an auto-generated UUID identifier.

```swift
public convenience init(
    mapDesignType: MapboxMapDesignType = MapboxMapDesign.Standard,
    cameraPosition: MapCameraPosition = .Default
)
```

**Parameters (shared)**

- `id`
    - Type: `String`
    - Description: A stable identifier for this state instance. The convenience initializer
      generates a `UUID` automatically.
- `mapDesignType`
    - Type: `MapboxMapDesignType`
    - Default: `MapboxMapDesign.Standard`
    - Description: The initial base map style.
- `cameraPosition`
    - Type: `MapCameraPosition`
    - Default: `.Default`
    - Description: The initial camera position (location, zoom, bearing, tilt).

## Properties

- `id` — Type: `String` — The unique identifier of this state instance.
- `cameraPosition` — Type: `MapCameraPosition` — The current camera position. Updated
  automatically as the user pans or zooms the map.
- `mapDesignType` — Type: `MapboxMapDesignType` — The active base map style. Setting this
  property updates the map immediately.

## Methods

### `moveCameraTo(cameraPosition:durationMillis:)`

Moves or animates the camera to the specified position.

```swift
public override func moveCameraTo(
    cameraPosition: MapCameraPosition,
    durationMillis: Long? = 0
)
```

### `moveCameraTo(position:durationMillis:)`

Moves or animates the camera to center on the specified geographic point.

```swift
public override func moveCameraTo(
    position: GeoPoint,
    durationMillis: Long? = 0
)
```

**Parameters (shared)**

- `durationMillis`
    - Type: `Long?`
    - Default: `0`
    - Description: Animation duration in milliseconds. `0` or `nil` moves the camera instantly.

## Example

```swift
@StateObject private var mapState = MapboxViewState(
    mapDesignType: MapboxMapDesign.Dark,
    cameraPosition: MapCameraPosition(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
        zoom: 12.0
    )
)

// Animate camera
mapState.moveCameraTo(
    position: GeoPoint(latitude: 40.7128, longitude: -74.0060),
    durationMillis: 800
)
```
