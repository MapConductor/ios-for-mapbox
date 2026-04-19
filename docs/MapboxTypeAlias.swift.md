# MapboxTypeAlias

Type aliases that map Mapbox SDK concrete types to the generic names used by the SDK's overlay
system.

## Aliases

- `MapboxActualMarker`
    - Type: `Feature`
    - Description: The Mapbox feature type used internally by the marker controller and renderer.
- `MapboxActualPolyline`
    - Type: `[Feature]`
    - Description: A list of Mapbox features used to represent a polyline.
- `MapboxActualCircle`
    - Type: `Feature`
    - Description: The Mapbox feature type used for circle rendering.
- `MapboxActualPolygon`
    - Type: `[Feature]`
    - Description: A list of Mapbox features used to represent a polygon.

## Signature

```swift
public typealias MapboxActualMarker   = Feature
public typealias MapboxActualPolyline = [Feature]
public typealias MapboxActualCircle   = Feature
public typealias MapboxActualPolygon  = [Feature]
```
