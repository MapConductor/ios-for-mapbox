# MapboxSDKConfiguration

Global function for initializing the Mapbox SDK with an access token. Call this once before
displaying any `MapboxMapView`, typically in `AppDelegate` or via the `sdkInitialize` callback.

## Signature

```swift
public func initializeMapbox(accessToken: String)
```

## Parameters

- `accessToken`
    - Type: `String`
    - Description: Your Mapbox public access token. Obtain from the Mapbox account dashboard.

## Example

```swift
// In AppDelegate or App init:
initializeMapbox(accessToken: "pk.eyJ1IjoiZXhhbXBsZSIsImEiOiJja...")

// Or via sdkInitialize in MapboxMapView:
MapboxMapView(
    state: mapState,
    sdkInitialize: { initializeMapbox(accessToken: "pk.eyJ1...") }
) { ... }
```
