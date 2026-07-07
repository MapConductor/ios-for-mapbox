import Foundation
import MapboxMaps
import MapConductorCore
import UIKit

@MainActor
final class MapboxGroundImageOverlayRenderer: AbstractGroundImageOverlayRenderer<MapboxGroundImageHandle> {
    private weak var mapView: MapView?
    private var mapboxMap: MapboxMap? { mapView?.mapboxMap }

    init(mapView: MapView?) {
        self.mapView = mapView
        super.init()
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {}

    func unbind() { mapView = nil }

    // MARK: - Sync helpers

    func createGroundImageSync(state: GroundImageState) -> MapboxGroundImageHandle? {
        guard let mapboxMap, let coordinates = state.bounds.toImageCoordinates() else { return nil }

        let sourceId = sourceId(for: state.id)
        let layerId = layerId(for: state.id)

        removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: sourceId, layerId: layerId)
        addImageLayer(
            mapboxMap: mapboxMap,
            sourceId: sourceId,
            layerId: layerId,
            coordinates: coordinates,
            image: state.image,
            opacity: state.opacity
        )

        return MapboxGroundImageHandle(
            sourceId: sourceId,
            layerId: layerId,
            applied: state.fingerPrint().toAppliedGroundImage()
        )
    }

    func updateGroundImageSync(
        groundImage: MapboxGroundImageHandle,
        current: GroundImageEntity<MapboxGroundImageHandle>,
        prev: GroundImageEntity<MapboxGroundImageHandle>
    ) -> MapboxGroundImageHandle? {
        guard let mapboxMap else { return groundImage }

        guard mapboxMap.sourceExists(withId: groundImage.sourceId),
              mapboxMap.layerExists(withId: groundImage.layerId) else {
            removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: groundImage.sourceId, layerId: groundImage.layerId)
            return createGroundImageSync(state: current.state)
        }

        let finger = current.fingerPrint
        let prevFinger = groundImage.applied
        guard let coordinates = current.state.bounds.toImageCoordinates() else { return groundImage }

        if finger.image != prevFinger.image {
            try? mapboxMap.updateImageSource(withId: groundImage.sourceId, image: current.state.image)
            try? mapboxMap.setSourceProperty(for: groundImage.sourceId, property: "coordinates", value: coordinates)
        } else if finger.bounds != prevFinger.bounds {
            try? mapboxMap.setSourceProperty(for: groundImage.sourceId, property: "coordinates", value: coordinates)
        }

        if finger.opacity != prevFinger.opacity {
            try? mapboxMap.updateLayer(withId: groundImage.layerId, type: RasterLayer.self) { layer in
                layer.rasterOpacity = .constant(current.state.opacity.clampedOpacity)
            }
        }

        return groundImage.copy(applied: finger.toAppliedGroundImage())
    }

    func removeGroundImageSync(entity: GroundImageEntity<MapboxGroundImageHandle>) {
        guard let mapboxMap, let handle = entity.groundImage else { return }
        removeSourceAndLayerIfExists(mapboxMap: mapboxMap, sourceId: handle.sourceId, layerId: handle.layerId)
    }

    // MARK: - AbstractGroundImageOverlayRenderer

    override func createGroundImage(state: GroundImageState) async -> MapboxGroundImageHandle? {
        createGroundImageSync(state: state)
    }

    override func updateGroundImageProperties(
        groundImage: MapboxGroundImageHandle,
        current: GroundImageEntity<MapboxGroundImageHandle>,
        prev: GroundImageEntity<MapboxGroundImageHandle>
    ) async -> MapboxGroundImageHandle? {
        updateGroundImageSync(groundImage: groundImage, current: current, prev: prev)
    }

    override func removeGroundImage(entity: GroundImageEntity<MapboxGroundImageHandle>) async {
        removeGroundImageSync(entity: entity)
    }

    // MARK: - Private

    private func addImageLayer(
        mapboxMap: MapboxMap,
        sourceId: String,
        layerId: String,
        coordinates: [[Double]],
        image: UIImage,
        opacity: Double
    ) {
        var source = ImageSource(id: sourceId)
        source.coordinates = coordinates
        try? mapboxMap.addSource(source)
        try? mapboxMap.updateImageSource(withId: sourceId, image: image)

        var layer = RasterLayer(id: layerId, source: sourceId)
        layer.rasterOpacity = .constant(opacity.clampedOpacity)
        try? mapboxMap.addLayer(layer)
    }

    private func removeSourceAndLayerIfExists(mapboxMap: MapboxMap, sourceId: String, layerId: String) {
        if mapboxMap.layerExists(withId: layerId) { try? mapboxMap.removeLayer(withId: layerId) }
        if mapboxMap.sourceExists(withId: sourceId) { try? mapboxMap.removeSource(withId: sourceId) }
    }

    private func sourceId(for id: String) -> String {
        "mc-gimg-src-\(styleIdPart(id))"
    }

    private func layerId(for id: String) -> String {
        "mc-gimg-lyr-\(styleIdPart(id))"
    }

    private func styleIdPart(_ id: String) -> String {
        String(id.map { ch in
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                return ch
            }
            return "_"
        })
    }
}

private extension GeoRectBounds {
    func toImageCoordinates() -> [[Double]]? {
        guard let sw = southWest, let ne = northEast else { return nil }
        return [
            [sw.longitude, ne.latitude],
            [ne.longitude, ne.latitude],
            [ne.longitude, sw.latitude],
            [sw.longitude, sw.latitude]
        ]
    }
}

private extension GroundImageFingerPrint {
    func toAppliedGroundImage() -> AppliedGroundImage {
        AppliedGroundImage(
            bounds: bounds,
            image: image,
            opacity: opacity
        )
    }
}

private extension Double {
    var clampedOpacity: Double {
        min(max(self, 0.0), 1.0)
    }
}
