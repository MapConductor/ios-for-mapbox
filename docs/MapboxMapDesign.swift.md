# MapboxMapDesign

`MapboxMapDesign` is a struct that represents a Mapbox map style. It conforms to
`MapboxMapDesignTypeProtocol` and wraps a `styleURI` string value.

Use the static presets in most cases. Use `custom(styleURI:)` to supply a custom style URL.

## Signature

```swift
public struct MapboxMapDesign: MapboxMapDesignTypeProtocol, Hashable {
    public let id: String
    public let styleURI: String

    public init(id: String, styleURI: String)
}
```

## Static Presets

- `Standard` — Mapbox Standard style.
- `StandardSatellite` — Mapbox Standard Satellite style.
- `Streets` — Mapbox Streets style.
- `Outdoors` — Mapbox Outdoors style.
- `Light` — Mapbox Light style.
- `Dark` — Mapbox Dark style.
- `Satellite` — Satellite imagery without labels.
- `SatelliteStreets` — Satellite imagery with roads and labels.
- `NavigationDay` — Navigation-optimized daytime style.
- `NavigationNight` — Navigation-optimized nighttime style.

## Methods

### `getValue()`

Returns the style URI string.

```swift
public func getValue() -> String
```

### `custom(styleURI:)`

Creates a `MapboxMapDesign` from a custom style URI string.

```swift
public static func custom(styleURI: String) -> MapboxMapDesign
```

**Parameters**

- `styleURI`
    - Type: `String`
    - Description: A Mapbox style URI (e.g. `"mapbox://styles/..."`) or a URL to a JSON style.

**Returns**

- Type: `MapboxMapDesign`

## Example

```swift
// Use a preset
mapState.mapDesignType = MapboxMapDesign.Dark

// Custom style
let myStyle = MapboxMapDesign.custom(styleURI: "mapbox://styles/user/abc123")
mapState.mapDesignType = myStyle
```

---

# MapboxMapDesignType

A type alias for `any MapboxMapDesignTypeProtocol`.

## Signature

```swift
public typealias MapboxMapDesignType = any MapboxMapDesignTypeProtocol
```

---

# MapboxMapDesignTypeProtocol

A protocol extending `MapDesignTypeProtocol` and constraining `Identifier` to `String`.
Conforming types represent a Mapbox map style via a style URI string.

## Signature

```swift
public protocol MapboxMapDesignTypeProtocol: MapDesignTypeProtocol
    where Identifier == String {
    var styleURI: String { get }
}
```
