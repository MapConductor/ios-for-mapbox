import Combine
import CoreLocation
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxCircleController: CircleController<Feature, MapboxCircleOverlayRenderer> {
    private var circleSubscriptions: [String: AnyCancellable] = [:]
    private var circleStatesById: [String: CircleState] = [:]
    private var latestStates: [CircleState] = []
    private var isStyleLoaded = false

    init(mapView: MapView?) {
        let circleManager = CircleManager<Feature>()
        let layer = CircleLayer(
            sourceId: "mapconductor-circles-source-\(UUID().uuidString)",
            layerId: "mapconductor-circles-layer-\(UUID().uuidString)"
        )
        let renderer = MapboxCircleOverlayRenderer(
            mapView: mapView,
            circleManager: circleManager,
            circleLayer: layer
        )
        super.init(circleManager: circleManager, renderer: renderer)
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

    func syncCircles(_ circles: [Circle]) {
        let newIds = Set(circles.map { $0.id })
        let oldIds = Set(circleStatesById.keys)
        var newStatesById: [String: CircleState] = [:]
        var shouldSyncList = false

        for circle in circles {
            let state = circle.state
            if let existing = circleStatesById[state.id], existing !== state {
                circleSubscriptions[state.id]?.cancel()
                circleSubscriptions.removeValue(forKey: state.id)
                shouldSyncList = true
            }
            newStatesById[state.id] = state
            if !circleManager.hasEntity(state.id) { shouldSyncList = true }
        }

        circleStatesById = newStatesById
        latestStates = circles.map { $0.state }
        if oldIds != newIds { shouldSyncList = true }

        if isStyleLoaded, shouldSyncList {
            Task { [weak self] in
                guard let self else { return }
                await self.add(data: self.latestStates)
            }
        }

        for circle in circles { subscribeToCircle(circle.state) }

        for id in oldIds.subtracting(newIds) {
            circleSubscriptions[id]?.cancel()
            circleSubscriptions.removeValue(forKey: id)
        }
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let hit = find(position: position) else { return false }
        dispatchClick(event: CircleEvent(state: hit.state, clicked: position))
        return true
    }

    // Override to re-compute pixel radius when zoom changes
    override func onCameraChanged(mapCameraPosition: MapCameraPosition) async {
        await renderer.onPostProcess()
    }

    private func subscribeToCircle(_ state: CircleState) {
        guard circleSubscriptions[state.id] == nil else { return }
        circleSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.circleStatesById[state.id] != nil else { return }
                Task { [weak self] in
                    guard let self else { return }
                    await self.update(state: state)
                }
            }
    }

    func unbind() {
        circleSubscriptions.values.forEach { $0.cancel() }
        circleSubscriptions.removeAll()
        circleStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        destroy()
    }
}
