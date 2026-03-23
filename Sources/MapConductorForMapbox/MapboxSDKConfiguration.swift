import MapboxMaps

/// Sets the Mapbox access token. Call this once before creating any `MapboxMapView`.
/// This is the equivalent of `GMSServices.provideAPIKey(_:)` for Mapbox.
public func initializeMapbox(accessToken: String) {
    MapboxOptions.accessToken = accessToken
}
