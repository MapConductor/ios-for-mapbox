import CoreLocation
import Foundation
import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxMarkerRenderer: MarkerOverlayRendererProtocol {
    typealias ActualMarker = Feature

    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    let markerLayer: MarkerLayer
    private let markerManager: MarkerManager<Feature>
    private let defaultMarkerIcon: BitmapIcon = DefaultMarkerIcon().toBitmapIcon()

    private var iconNameByMarkerId: [String: String] = [:]
    private var lastBitmapIconByMarkerId: [String: BitmapIcon] = [:]
    private var markerAnimationRunners: [String: MarkerAnimationRunner] = [:]

    var animateStartListener: OnMarkerEventHandler?
    var animateEndListener: OnMarkerEventHandler?

    init(mapView: MapView?, markerManager: MarkerManager<Feature>, markerLayer: MarkerLayer) {
        self.mapView = mapView
        self.markerManager = markerManager
        self.markerLayer = markerLayer
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        markerLayer.ensureAdded(to: mapboxMap)
        ensureDefaultIcon(mapboxMap: mapboxMap)
        Task { await onPostProcess() }
    }

    func unbind() {
        guard let mapboxMap else { return }
        markerLayer.remove(from: mapboxMap)
        markerAnimationRunners.values.forEach { $0.stop() }
        markerAnimationRunners.removeAll()
        iconNameByMarkerId.removeAll()
        lastBitmapIconByMarkerId.removeAll()
        mapView = nil
    }

    // MARK: - MarkerOverlayRendererProtocol

    func onAdd(data: [MarkerOverlayAddParams]) async -> [Feature?] {
        data.map { params in makeFeature(for: params.state, bitmapIcon: params.bitmapIcon) }
    }

    func onChange(data: [MarkerOverlayChangeParams<Feature>]) async -> [Feature?] {
        data.map { params in
            var feature = params.prev.marker ?? makeFeature(for: params.current.state, bitmapIcon: params.bitmapIcon)
            updateFeature(&feature, state: params.current.state, bitmapIcon: params.bitmapIcon)
            return feature
        }
    }

    func onRemove(data: [MarkerEntity<Feature>]) async {
        guard let mapboxMap else { return }
        for entity in data {
            markerAnimationRunners[entity.state.id]?.stop()
            markerAnimationRunners.removeValue(forKey: entity.state.id)
            if let iconName = iconNameByMarkerId.removeValue(forKey: entity.state.id) {
                try? mapboxMap.removeImage(withId: iconName)
            }
            lastBitmapIconByMarkerId.removeValue(forKey: entity.state.id)
        }
    }

    func onAnimate(entity: MarkerEntity<Feature>) async {
        guard markerAnimationRunners[entity.state.id] == nil else { return }
        guard let animation = entity.state.getAnimation() else { return }
        guard let mapView else { return }

        mapView.layoutIfNeeded()
        if mapView.window == nil || mapView.bounds.isEmpty {
            await deferAnimate(entity: entity)
            return
        }

        let target = CLLocationCoordinate2D(
            latitude: entity.state.position.latitude,
            longitude: entity.state.position.longitude
        )
        let targetPoint = mapView.mapboxMap.point(for: target)
        guard targetPoint.x.isFinite && targetPoint.y.isFinite else {
            await deferAnimate(entity: entity)
            return
        }

        let startPoint = CGPoint(x: targetPoint.x, y: animationStartY(in: mapView.bounds))
        let startCoord = mapView.mapboxMap.coordinate(for: startPoint)
        let startGeoPoint = GeoPoint(latitude: startCoord.latitude, longitude: startCoord.longitude, altitude: 0)
        let targetGeoPoint = GeoPoint(latitude: target.latitude, longitude: target.longitude, altitude: 0)

        let pathPoints = animation == .Bounce
            ? bouncePath(for: mapView, target: target)
            : MarkerAnimationRunner.makeLinearPath(start: startGeoPoint, target: targetGeoPoint)

        // Unhide the marker
        if var e = markerManager.getEntity(entity.state.id), var feature = e.marker {
            feature.properties?[MarkerLayer.Prop.isHidden] = .number(0)
            e.marker = feature
            markerManager.updateEntity(e)
        }

        animateStartListener?(entity.state)

        let runner = MarkerAnimationRunner(
            duration: animation == .Bounce ? 2.0 : 0.3,
            pathPoints: pathPoints,
            onUpdate: { [weak self] point in
                guard let self else { return }
                if var e = self.markerManager.getEntity(entity.state.id), var feature = e.marker {
                    feature.geometry = .point(Point(CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    )))
                    e.marker = feature
                    self.markerManager.updateEntity(e)
                }
                Task { @MainActor [weak self] in await self?.onPostProcess() }
            },
            onCompletion: { [weak self] in
                entity.state.animate(nil)
                self?.markerAnimationRunners.removeValue(forKey: entity.state.id)
                self?.animateEndListener?(entity.state)
                Task { @MainActor [weak self] in await self?.onPostProcess() }
            }
        )
        markerAnimationRunners[entity.state.id] = runner
        runner.start()
    }

    func onPostProcess() async {
        guard let mapboxMap else { return }
        let features = markerManager.allEntities().compactMap { entity -> Feature? in
            guard let feature = entity.marker else { return nil }
            return feature
        }
        markerLayer.setFeatures(features, mapboxMap: mapboxMap)
    }

    // MARK: - Helpers

    func markerId(at point: CGPoint) async -> String? {
        guard let mapboxMap else { return nil }
        let options = RenderedQueryOptions(layerIds: [markerLayer.layerId], filter: nil)
        return await withCheckedContinuation { continuation in
            mapboxMap.queryRenderedFeatures(with: point, options: options) { queryResult in
                if case .success(let features) = queryResult,
                   let first = features.first,
                   let id = first.queriedFeature.feature.properties?[MarkerLayer.Prop.markerId]??.rawValue as? String {
                    continuation.resume(returning: id)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func makeFeature(for state: MarkerState, bitmapIcon: BitmapIcon) -> Feature {
        var feature = Feature(
            geometry: .point(Point(CLLocationCoordinate2D(
                latitude: state.position.latitude,
                longitude: state.position.longitude
            )))
        )
        feature.identifier = .string("marker-\(state.id)")

        let iconName: String
        if state.icon != nil {
            iconName = customIconName(for: state.id)
            ensureCustomIcon(bitmapIcon, name: iconName)
            lastBitmapIconByMarkerId[state.id] = bitmapIcon
        } else {
            iconName = MarkerLayer.Prop.defaultMarkerId
            lastBitmapIconByMarkerId.removeValue(forKey: state.id)
        }

        let offset = iconOffset(bitmapIcon)
        feature.properties = [
            MarkerLayer.Prop.markerId: .string(state.id),
            MarkerLayer.Prop.iconId: .string(iconName),
            MarkerLayer.Prop.iconOffsetX: .number(offset.x),
            MarkerLayer.Prop.iconOffsetY: .number(offset.y),
            MarkerLayer.Prop.isHidden: .number(state.getAnimation() != nil ? 1 : 0)
        ]
        return feature
    }

    private func updateFeature(_ feature: inout Feature, state: MarkerState, bitmapIcon: BitmapIcon) {
        feature.geometry = .point(Point(CLLocationCoordinate2D(
            latitude: state.position.latitude,
            longitude: state.position.longitude
        )))

        var props = feature.properties ?? [:]

        if state.icon == nil {
            if lastBitmapIconByMarkerId[state.id] != nil {
                props[MarkerLayer.Prop.iconId] = .string(MarkerLayer.Prop.defaultMarkerId)
                let defOffset = iconOffset(defaultMarkerIcon)
                props[MarkerLayer.Prop.iconOffsetX] = .number(defOffset.x)
                props[MarkerLayer.Prop.iconOffsetY] = .number(defOffset.y)
                lastBitmapIconByMarkerId.removeValue(forKey: state.id)
                if let iconName = iconNameByMarkerId[state.id] {
                    try? mapboxMap?.removeImage(withId: iconName)
                }
            }
        } else {
            let iconName = customIconName(for: state.id)
            if lastBitmapIconByMarkerId[state.id] != bitmapIcon || mapboxMap?.imageExists(withId: iconName) == false {
                ensureCustomIcon(bitmapIcon, name: iconName)
                lastBitmapIconByMarkerId[state.id] = bitmapIcon
                let offset = iconOffset(bitmapIcon)
                props[MarkerLayer.Prop.iconId] = .string(iconName)
                props[MarkerLayer.Prop.iconOffsetX] = .number(offset.x)
                props[MarkerLayer.Prop.iconOffsetY] = .number(offset.y)
            }
        }
        feature.properties = props
    }

    private func ensureDefaultIcon(mapboxMap: MapboxMap) {
        let id = MarkerLayer.Prop.defaultMarkerId
        guard mapboxMap.imageExists(withId: id) == false else { return }
        try? mapboxMap.addImage(defaultMarkerIcon.bitmap, id: id, sdf: false)
    }

    private func ensureCustomIcon(_ icon: BitmapIcon, name: String) {
        guard let mapboxMap else { return }
        try? mapboxMap.addImage(icon.bitmap, id: name, sdf: false)
        iconNameByMarkerId[icon.bitmap.description] = name
    }

    private func customIconName(for markerId: String) -> String {
        let name = "mapconductor_marker_\(markerId)"
        iconNameByMarkerId[markerId] = name
        return name
    }

    private func iconOffset(_ icon: BitmapIcon) -> CGPoint {
        let w = icon.size.width
        let h = icon.size.height
        let anchorX = icon.anchor.x
        let anchorY = icon.anchor.y
        // Mapbox icon-offset is in pixels from center [dx, dy]
        let dx = (0.5 - anchorX) * w
        let dy = (0.5 - anchorY) * h
        return CGPoint(x: dx, y: dy)
    }

    private func animationStartY(in bounds: CGRect) -> CGFloat {
        bounds.minY - 10
    }

    private func bouncePath(for mapView: MapView, target: CLLocationCoordinate2D) -> [GeoPoint] {
        let targetPt = mapView.mapboxMap.point(for: target)
        var points: [GeoPoint] = []
        let bounces = 3
        for i in 0...bounces * 10 {
            let t = Double(i) / Double(bounces * 10)
            let bounce = abs(sin(t * Double.pi * Double(bounces))) * (1.0 - t)
            let y = targetPt.y - bounce * 80
            let coord = mapView.mapboxMap.coordinate(for: CGPoint(x: targetPt.x, y: y))
            points.append(GeoPoint(latitude: coord.latitude, longitude: coord.longitude, altitude: 0))
        }
        return points
    }

    private func deferAnimate(entity: MarkerEntity<Feature>) async {
        try? await Task.sleep(nanoseconds: 100_000_000)
        await onAnimate(entity: entity)
    }
}
