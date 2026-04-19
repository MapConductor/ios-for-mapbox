# MapboxMapView

A SwiftUI view that renders a Mapbox map. Accepts a declarative overlay tree via
`@MapViewContentBuilder`.

## Signature

```swift
public struct MapboxMapView: View {
    public init(
        state: MapboxViewState,
        onMapLoaded: OnMapLoadedHandler<MapboxViewState>? = nil,
        onMapClick: OnMapEventHandler? = nil,
        onCameraMoveStart: OnCameraMoveHandler? = nil,
        onCameraMove: OnCameraMoveHandler? = nil,
        onCameraMoveEnd: OnCameraMoveHandler? = nil,
        sdkInitialize: (() -> Void)? = nil,
        @MapViewContentBuilder content: @escaping () -> MapViewContent = { MapViewContent() }
    )
}
```

## Parameters

- `state`
    - Type: `MapboxViewState`
    - Description: The observable state object controlling camera position and map design.
      Hold with `@StateObject` in the parent view.
- `onMapLoaded`
    - Type: `OnMapLoadedHandler<MapboxViewState>?`
    - Default: `nil`
    - Description: Called once when the map finishes loading. Receives the `MapboxViewState`.
- `onMapClick`
    - Type: `OnMapEventHandler?`
    - Default: `nil`
    - Description: Called with the tapped geographic coordinate when the user taps the map.
- `onCameraMoveStart`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called with the camera position when a camera movement begins.
- `onCameraMove`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called continuously with the current camera position during movement.
- `onCameraMoveEnd`
    - Type: `OnCameraMoveHandler?`
    - Default: `nil`
    - Description: Called with the final camera position when movement ends.
- `sdkInitialize`
    - Type: `(() -> Void)?`
    - Default: `nil`
    - Description: Called once before the map view is created. Use to call
      `initializeMapbox(accessToken:)` if not already initialized elsewhere.
- `content`
    - Type: `@MapViewContentBuilder () -> MapViewContent`
    - Default: empty
    - Description: Declarative overlay tree. Supports `Marker`, `Polyline`, `Polygon`,
      `Circle`, `GroundImage`, `RasterLayer`, `InfoBubble`, and `ForArray`.

## Example

```swift
import MapConductorForMapbox
import SwiftUI

struct MyMapScreen: View {
    @StateObject private var mapState = MapboxViewState(
        mapDesignType: MapboxMapDesign.Streets,
        cameraPosition: MapCameraPosition(
            position: GeoPoint(latitude: 35.6812, longitude: 139.7671),
            zoom: 13.0
        )
    )
    @StateObject private var markerState = MarkerState(
        position: GeoPoint(latitude: 35.6812, longitude: 139.7671)
    )

    var body: some View {
        MapboxMapView(
            state: mapState,
            onMapLoaded: { _ in print("Map loaded") },
            sdkInitialize: { initializeMapbox(accessToken: "YOUR_TOKEN") }
        ) {
            Marker(state: markerState)
        }
        .ignoresSafeArea()
    }
}
```
