import Combine
import MapboxMaps
import MapConductorCore

@MainActor
final class MapboxGroundImageController {
    private let renderer: MapboxGroundImageOverlayRenderer
    private let groundImageManager: GroundImageManager<MapboxGroundImageHandle>

    private var groundImageSubscriptions: [String: AnyCancellable] = [:]
    private var groundImageStatesById: [String: GroundImageState] = [:]
    private var latestStates: [GroundImageState] = []
    private var isStyleLoaded = false

    init(mapView: MapView?) {
        self.groundImageManager = GroundImageManager<MapboxGroundImageHandle>()
        self.renderer = MapboxGroundImageOverlayRenderer(mapView: mapView)
    }

    func onStyleLoaded(_ mapboxMap: MapboxMap) {
        isStyleLoaded = true
        renderer.onStyleLoaded(mapboxMap)
        if !latestStates.isEmpty {
            syncDirectly(latestStates)
        }
    }

    func syncGroundImages(_ groundImages: [GroundImage]) {
        let newIds = Set(groundImages.map { $0.id })
        let oldIds = Set(groundImageStatesById.keys)
        var newStatesById: [String: GroundImageState] = [:]
        var shouldSync = false

        for groundImage in groundImages {
            let state = groundImage.state
            if let existing = groundImageStatesById[state.id], existing !== state {
                groundImageSubscriptions[state.id]?.cancel()
                groundImageSubscriptions.removeValue(forKey: state.id)
                shouldSync = true
            }
            newStatesById[state.id] = state
            if !groundImageManager.hasEntity(state.id) { shouldSync = true }
        }

        groundImageStatesById = newStatesById
        latestStates = groundImages.map { $0.state }
        if oldIds != newIds { shouldSync = true }

        for groundImage in groundImages { subscribeToGroundImage(groundImage.state) }

        for id in oldIds.subtracting(newIds) {
            groundImageSubscriptions[id]?.cancel()
            groundImageSubscriptions.removeValue(forKey: id)
        }

        guard isStyleLoaded, shouldSync else { return }
        syncDirectly(latestStates)
    }

    func handleTap(at coordinate: CLLocationCoordinate2D) -> Bool {
        let position = GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
        guard let entity = groundImageManager.find(position: position) else { return false }
        let event = GroundImageEvent(state: entity.state, clicked: position)
        entity.state.onClick?(event)
        return true
    }

    private func syncDirectly(_ states: [GroundImageState]) {
        let previous = Set(groundImageManager.allEntities().map { $0.state.id })
        let newIds = Set(states.map { $0.id })

        for id in previous.subtracting(newIds) {
            if let entity = groundImageManager.getEntity(id) {
                renderer.removeGroundImageSync(entity: entity)
                _ = groundImageManager.removeEntity(id)
            }
        }

        for state in states {
            if let prevEntity = groundImageManager.getEntity(state.id) {
                if prevEntity.fingerPrint != state.fingerPrint() {
                    if let handle = renderer.updateGroundImageSync(
                        groundImage: prevEntity.groundImage!,
                        current: GroundImageEntity(groundImage: prevEntity.groundImage, state: state),
                        prev: prevEntity
                    ) {
                        groundImageManager.registerEntity(GroundImageEntity(groundImage: handle, state: state))
                    }
                }
            } else {
                if let handle = renderer.createGroundImageSync(state: state) {
                    groundImageManager.registerEntity(GroundImageEntity(groundImage: handle, state: state))
                }
            }
        }
    }

    private func subscribeToGroundImage(_ state: GroundImageState) {
        guard groundImageSubscriptions[state.id] == nil else { return }
        groundImageSubscriptions[state.id] = state.asFlow()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.groundImageStatesById[state.id] != nil, self.isStyleLoaded else { return }
                self.syncDirectly(self.latestStates)
            }
    }

    func unbind() {
        groundImageSubscriptions.values.forEach { $0.cancel() }
        groundImageSubscriptions.removeAll()
        groundImageStatesById.removeAll()
        latestStates.removeAll()
        isStyleLoaded = false
        renderer.unbind()
        groundImageManager.destroy()
    }
}
