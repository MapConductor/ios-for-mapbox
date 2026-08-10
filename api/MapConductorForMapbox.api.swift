import Combine
import CoreGraphics
import CoreLocation
import Foundation
import MapConductorCore
import MapboxMaps
import QuartzCore
import Swift
import SwiftUI
import UIKit
import _Concurrency
import _StringProcessing
import _SwiftConcurrencyShims
extension MapConductorCore.MapCameraPosition {
  final public func toMapboxCameraOptions() -> MapboxCoreMaps.CameraOptions
  final public func adjustedZoomForMapbox() -> Swift.Double
}
extension MapboxCoreMaps.CameraState {
  public func toMapCameraPosition(logicalTiltHint: Swift.Double? = nil, visibleRegion: MapConductorCore.VisibleRegion? = nil) -> MapConductorCore.MapCameraPosition
}
public protocol MapboxMapDesignTypeProtocol : MapConductorCore.MapDesignTypeProtocol where Self.Identifier == Swift.String {
  var styleURI: Swift.String { get }
}
public typealias MapboxMapDesignType = any MapConductorForMapbox.MapboxMapDesignTypeProtocol
public struct MapboxMapDesign : MapConductorForMapbox.MapboxMapDesignTypeProtocol, Swift.Hashable {
  public let id: Swift.String
  public let styleURI: Swift.String
  public let attributionRules: [MapConductorCore.AttributionRule]
  public init(id: Swift.String, styleURI: Swift.String, attributionRules: [MapConductorCore.AttributionRule] = [])
  public func getValue() -> Swift.String
  public static let Standard: MapConductorForMapbox.MapboxMapDesign
  public static let StandardSatellite: MapConductorForMapbox.MapboxMapDesign
  public static let Streets: MapConductorForMapbox.MapboxMapDesign
  public static let Outdoors: MapConductorForMapbox.MapboxMapDesign
  public static let Light: MapConductorForMapbox.MapboxMapDesign
  public static let Dark: MapConductorForMapbox.MapboxMapDesign
  public static let Satellite: MapConductorForMapbox.MapboxMapDesign
  public static let SatelliteStreets: MapConductorForMapbox.MapboxMapDesign
  public static let NavigationDay: MapConductorForMapbox.MapboxMapDesign
  public static let NavigationNight: MapConductorForMapbox.MapboxMapDesign
  public static func custom(styleURI: Swift.String) -> MapConductorForMapbox.MapboxMapDesign
  public static func == (a: MapConductorForMapbox.MapboxMapDesign, b: MapConductorForMapbox.MapboxMapDesign) -> Swift.Bool
  public typealias Identifier = Swift.String
  public func hash(into hasher: inout Swift.Hasher)
  public var hashValue: Swift.Int {
    get
  }
}
@_Concurrency.MainActor @preconcurrency public struct MapboxMapView : SwiftUICore.View {
  @_Concurrency.MainActor @preconcurrency public init(state: MapConductorForMapbox.MapboxViewState, projection: MapConductorCore.MapProjection = .mercator, cameraRestriction: MapConductorCore.CameraRestriction? = nil, onMapLoaded: MapConductorCore.OnMapLoadedHandler<MapConductorForMapbox.MapboxViewState>? = nil, onMapClick: MapConductorCore.OnMapEventHandler? = nil, onMapLongClick: MapConductorCore.OnMapEventHandler? = nil, onCameraMoveStart: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMove: MapConductorCore.OnCameraMoveHandler? = nil, onCameraMoveEnd: MapConductorCore.OnCameraMoveHandler? = nil, sdkInitialize: (() -> Swift.Void)? = nil, @MapConductorCore.MapViewContentBuilder content: @escaping () -> MapConductorCore.MapViewContent = { MapViewContent() })
  @_Concurrency.MainActor @preconcurrency public var body: some SwiftUICore.View {
    get
  }
  public typealias Body = @_opaqueReturnTypeOf("$s21MapConductorForMapbox0dA4ViewV4bodyQrvp", 0) __
}
public func initializeMapbox(accessToken: Swift.String)
public typealias MapboxActualMarker = MapboxMaps.Feature
public typealias MapboxActualPolyline = [MapboxMaps.Feature]
public typealias MapboxActualCircle = MapboxMaps.Feature
public typealias MapboxActualPolygon = [MapboxMaps.Feature]
final public class MapboxViewState : MapConductorCore.MapViewState<MapConductorForMapbox.MapboxMapDesignType> {
  final public var mapViewHolder: MapConductorForMapbox.MapboxMapViewHolder? {
    get
  }
  override final public var mapDesignType: MapConductorForMapbox.MapboxMapDesignType {
    get
    set
  }
  public init(id: Swift.String, mapDesignType: MapConductorForMapbox.MapboxMapDesignType = MapboxMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  convenience public init(mapDesignType: MapConductorForMapbox.MapboxMapDesignType = MapboxMapDesign.Standard, cameraPosition: MapConductorCore.MapCameraPosition = .Default, uiSettings: MapConductorCore.MapUISettings = MapUISettings())
  override final public func getMapViewHolder() -> MapConductorCore.AnyMapViewHolder?
  @objc deinit
}
extension MapConductorCore.ZoomAltitudeConverterProtocol where Self == MapConductorForMapbox.MapboxZoomAltitudeConverter {
  public static var mapbox: MapConductorForMapbox.MapboxZoomAltitudeConverter {
    get
  }
}
public class MapboxZoomAltitudeConverter : MapConductorCore.WebMercatorZoomAltitudeConverter {
  public init(zoom0Altitude: Swift.Double = AbstractZoomAltitudeConverter.defaultZoom0Altitude)
  public static func mapboxZoomToGoogleZoom(_ zoom: Swift.Double) -> Swift.Double
  public static func googleZoomToMapboxZoom(_ zoom: Swift.Double) -> Swift.Double
  @objc deinit
}
@_hasMissingDesignatedInitializers final public class MapboxMapViewHolder : MapConductorCore.MapViewHolderProtocol {
  public typealias ActualMapView = MapboxMaps.MapView
  public typealias ActualMap = MapboxMaps.MapboxMap
  final public let mapView: MapboxMaps.MapView
  final public var map: MapboxMaps.MapboxMap {
    get
  }
  final public func toScreenOffset(position: any MapConductorCore.GeoPointProtocol) -> CoreFoundation.CGPoint?
  final public func fromScreenOffset(offset: CoreFoundation.CGPoint) async -> MapConductorCore.GeoPoint?
  final public func fromScreenOffsetSync(offset: CoreFoundation.CGPoint) -> MapConductorCore.GeoPoint?
  @objc deinit
}
extension MapConductorForMapbox.MapboxMapView : Swift.Sendable {}
