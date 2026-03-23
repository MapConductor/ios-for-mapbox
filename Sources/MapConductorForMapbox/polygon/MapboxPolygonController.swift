import Combine
import CoreLocation
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxPolygonController: PolygonController<[Feature], MapboxPolygonOverlayRenderer> {
    private var polygonSubscriptions: [String: AnyCancellable] = [:]
    private var polygonStatesById: [String: PolygonState] = [:]
    private var latestStates: [PolygonState] = []
    private var isStyleLoaded = false

    init(mapView: MapView?) {
        let polygonManager = PolygonManager<[Feature]>()
        let layer = PolygonLayer(
            sourceId: "mapconductor-polygons-source-\(UUID().uuidString)",
            fillLayerId: "mapconductor-polygons-fill-\(UUID().uuidString)",
            lineLayerId: "mapconductor-polygons-line-\(UUID().uuidString)"
        )
        let renderer = MapboxPolygonOverlayRenderer(
            mapView: mapView,
            polygonManager: polygonManager,
            polygonLayer: layer
        )
        super.init(polygonManager: polygonManager, renderer: renderer)
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        isStyleLoaded = true
        renderer.onStyleLoaded(mapboxMap)
        if !latestStates.isEmpty {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }
    }

    func syncPolygons(_ polygons: [MapConductorCore.Polygon]) {
        let newIds = Set(polygons.map { $0.id })
        let oldIds = Set(polygonStatesById.keys)
        var newStatesById: [String: PolygonState] = [:]
        var shouldSyncList = false

        for polygon in polygons {
            let state = polygon.state
            if let existing = polygonStatesById[state.id], existing !== state {
                polygonSubscriptions[state.id]?.cancel()
                polygonSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !polygonManager.hasEntity(state.id) { shouldSyncList = true }
        }

        polygonStatesById = newStatesById
        latestStates = polygons.map { $0.state }
        if oldIds != newIds { shouldSyncList = true }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for polygon in polygons { subscribeToPolygon(polygon.state) }

        for id in oldIds.subtracting(newIds) {
            polygonSubscriptions[id]?.cancel()
            polygonSubscriptions.removeValue(forKey: id)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        dispatchClick(event: PolygonEvent(state: hit.state, clicked: position))
        return true
    }

    private func subscribeToPolygon(_ state: PolygonState) {
        guard polygonSubscriptions[state.id] == nil else { return }
        polygonSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.polygonStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        polygonSubscriptions.values.forEach { $0.cancel() }
        polygonSubscriptions.removeAll()
        polygonStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        destroy()
    }
}
