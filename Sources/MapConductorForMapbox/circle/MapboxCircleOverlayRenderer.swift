import CoreLocation
import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxCircleOverlayRenderer: AbstractCircleOverlayRenderer<Feature> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let circleLayer: CircleLayer
    private let circleManager: CircleManager<Feature>

    init(mapView: MapView?, circleManager: CircleManager<Feature>, circleLayer: CircleLayer) {
        self.mapView = mapView
        self.circleManager = circleManager
        self.circleLayer = circleLayer
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        circleLayer.ensureAdded(to: mapboxMap)
    }

    func unbind() {
        guard let mapboxMap else { return }
        circleLayer.remove(from: mapboxMap)
        mapView = nil
    }

    override func createCircle(state: CircleState) async -> Feature? {
        makeFeature(for: state)
    }

    override func updateCircleProperties(
        circle: Feature,
        current: CircleEntity<Feature>,
        prev: CircleEntity<Feature>
    ) async -> Feature? {
        makeFeature(for: current.state)
    }

    override func removeCircle(entity: CircleEntity<Feature>) async {}

    override func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = circleManager.allEntities().compactMap { entity -> Feature? in
            let updated = makeFeature(for: entity.state)
            entity.circle = updated
            return updated
        }
        circleLayer.setFeatures(features, mapboxMap: mapboxMap)
    }

    // MARK: - Helper

    private func makeFeature(for state: CircleState) -> Feature {
        var feature = Feature(
            geometry: .point(Point(CLLocationCoordinate2D(
                latitude: state.center.latitude,
                longitude: state.center.longitude
            )))
        )
        feature.identifier = .string("circle-\(state.id)")

        // circleRadius should use the SDK-native zoom. Adding the app-level +1 offset
        // here halves metersPerPixel and makes the circle render at 2x radius.
        let zoom = mapboxMap?.cameraState.zoom ?? 0.0
        let metersPerPixel = mapboxMetersPerPixel(latitude: state.center.latitude, zoom: zoom)
        let scale = max(1.0, Double(mapView?.contentScaleFactor ?? UIScreen.main.scale))
        let radiusPoints = metersPerPixel > 0 ? (state.radiusMeters / metersPerPixel) / scale : 0.0

        feature.properties = [
            CircleLayer.Prop.radiusPixels: .number(radiusPoints),
            CircleLayer.Prop.fillColor: .string(state.fillColor.toMapboxColorString()),
            CircleLayer.Prop.strokeColor: .string(state.strokeColor.toMapboxColorString()),
            CircleLayer.Prop.strokeWidth: .number(state.strokeWidth),
            CircleLayer.Prop.circleId: .string(state.id)
        ]
        return feature
    }
}

// MARK: - Meters per pixel helper

internal func mapboxMetersPerPixel(latitude: Double, zoom: Double, tileSize: Int = 512) -> Double {
    let earthCircumference = 40075016.686
    let pixelsAtZoom = Double(tileSize) * pow(2.0, zoom)
    return earthCircumference * cos(latitude * .pi / 180.0) / pixelsAtZoom
}
